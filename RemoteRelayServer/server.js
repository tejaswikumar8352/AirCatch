/**
 * AirCatch Remote Relay Server
 * 
 * WebSocket relay server that connects AirCatchHost (Mac) and AirCatchClient (iPad)
 * when they're on different networks.
 * 
 * SECURITY HARDENED:
 * - Rate limiting per IP (connection + registration)
 * - Room code brute-force protection with temporary IP bans
 * - Maximum connections per IP
 * - Message size limits (16MB)
 * - Backpressure management for video frames (256KB threshold)
 * - Faster ping interval (15s) for quicker disconnect detection
 * - Idle room cleanup
 * - Security headers on HTTP responses
 * - Graceful shutdown
 * 
 * Protocol:
 * - First message is JSON: { "type": "register", "role": "host"|"client", "roomCode": "XXXXXX", "channel": "video"|"control" }
 * - channel is optional for backwards compatibility (defaults to combined video+control)
 * - After registration, all messages are binary data relayed to the paired peer on same channel
 * 
 * Multi-channel support:
 * - "video" channel: High-bandwidth video frames (can drop under backpressure)
 * - "control" channel: Low-latency control/audio (never dropped, priority)
 * - Legacy (no channel): Combined mode, both video and control on same socket
 */

const WebSocket = require('ws');
const http = require('http');
const https = require('https');
const fs = require('fs');

const PORT = process.env.PORT || 8080;
const TLS_KEY_PATH = process.env.TLS_KEY_PATH;
const TLS_CERT_PATH = process.env.TLS_CERT_PATH;
const TLS_CA_PATH = process.env.TLS_CA_PATH;

// ==================== SECURITY CONFIGURATION ====================

const SECURITY = {
    // Maximum connections per IP address
    MAX_CONNECTIONS_PER_IP: 6,
    // Maximum message size (16MB - matches client maxTCPPayloadLength)
    MAX_MESSAGE_SIZE: 16 * 1024 * 1024,
    // Rate limiting: max registration attempts per IP per minute
    MAX_REGISTRATIONS_PER_MINUTE: 10,
    // Room code brute-force: max failed room attempts per IP before temporary ban
    MAX_FAILED_ROOM_ATTEMPTS: 5,
    // Temporary ban duration (ms) after too many failed room attempts
    BAN_DURATION_MS: 60 * 1000,
    // Maximum rooms allowed on server
    MAX_ROOMS: 200,
    // Room idle timeout (ms) - clean up rooms with no activity
    ROOM_IDLE_TIMEOUT_MS: 5 * 60 * 1000,
    // Maximum room code length
    MAX_ROOM_CODE_LENGTH: 12,
    // Maximum registration message size
    MAX_REGISTRATION_SIZE: 1024,
};

// ==================== PERFORMANCE CONFIGURATION ====================

const PERFORMANCE = {
    // Backpressure threshold before dropping video frames (256KB - 4x previous)
    BACKPRESSURE_THRESHOLD: 256 * 1024,
    // Start shedding non-critical control packets once control buffers grow.
    CONTROL_BACKPRESSURE_THRESHOLD: 64 * 1024,
    // Emergency threshold: aggressively shed best-effort control traffic.
    CONTROL_HARD_BACKPRESSURE_THRESHOLD: 256 * 1024,
    // WebSocket ping interval (15s for faster reconnection detection, was 30s)
    PING_INTERVAL_MS: 15000,
};

const PACKET = {
    VIDEO_FRAME: 0x01,
    TOUCH_EVENT: 0x02,
    SCROLL_EVENT: 0x06,
    QUALITY_REPORT: 0x08,
    PING: 0x09,
    PONG: 0x0A,
    VIDEO_FRAME_CHUNK: 0x0C,
    AUDIO_PCM: 0x0F,
    KEY_EVENT: 0x07,
    MEDIA_KEY_EVENT: 0x10,
};

function parseAirCatchPacket(message) {
    if (!Buffer.isBuffer(message) || message.length < 5) return null;
    const payloadLength = (
        (message[1] << 24) |
        (message[2] << 16) |
        (message[3] << 8) |
        message[4]
    ) >>> 0;
    const start = 5;
    const end = start + payloadLength;
    if (end > message.length || payloadLength > SECURITY.MAX_MESSAGE_SIZE) {
        return null;
    }
    return {
        type: message[0],
        payload: message.subarray(start, end),
    };
}

function shouldDropControlPacketUnderPressure(packet, bufferedAmount) {
    if (!packet) return bufferedAmount >= PERFORMANCE.CONTROL_HARD_BACKPRESSURE_THRESHOLD;
    const hardPressure = bufferedAmount >= PERFORMANCE.CONTROL_HARD_BACKPRESSURE_THRESHOLD;

    switch (packet.type) {
        // Heartbeat/telemetry packets are best-effort.
        case PACKET.PING:
        case PACKET.PONG:
        case PACKET.QUALITY_REPORT:
            return true;

        // Audio is best-effort for responsiveness in congested relay sessions.
        case PACKET.AUDIO_PCM:
        case PACKET.SCROLL_EVENT:
            return true;

        // Keep keyboard and media keys reliable.
        case PACKET.KEY_EVENT:
        case PACKET.MEDIA_KEY_EVENT:
            return false;

        case PACKET.TOUCH_EVENT: {
            // Under pressure, drop high-rate move events but keep presses/releases.
            try {
                const event = JSON.parse(packet.payload.toString('utf8'));
                const type = event && event.eventType;
                if (type === 'moved' || type === 'dragMoved') {
                    return true;
                }
                return false;
            } catch (_) {
                // If parsing fails, only drop at hard-pressure.
                return hardPressure;
            }
        }

        default:
            return hardPressure;
    }
}

// ==================== STATE ====================

// Room storage: roomCode -> { host, client, hostVideo, clientVideo, hostControl, clientControl, lastActivity }
const rooms = new Map();

// WebSocket to room mapping for cleanup
// { roomCode, role, channel } where channel is 'combined'|'video'|'control'
const wsToRoom = new Map();

// IP tracking for rate limiting
const ipConnections = new Map();     // IP -> Set<WebSocket>
const ipRegistrations = new Map();   // IP -> { count, resetAt }
const ipBans = new Map();            // IP -> banExpiry timestamp
const roomFailedAttempts = new Map(); // IP -> { count, resetAt }

// ==================== SERVER SETUP ====================

function requestHandler(req, res) {
    // Security headers on ALL responses
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    res.setHeader('Cache-Control', 'no-store');

    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            status: 'ok', 
            rooms: rooms.size,
            connections: wss ? wss.clients.size : 0,
            uptime: process.uptime()
        }));
        return;
    }
    
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('AirCatch Relay Server\n');
}

function createRelayServer() {
    if (TLS_KEY_PATH && TLS_CERT_PATH) {
        try {
            const tlsOptions = {
                key: fs.readFileSync(TLS_KEY_PATH),
                cert: fs.readFileSync(TLS_CERT_PATH),
            };

            if (TLS_CA_PATH) {
                tlsOptions.ca = fs.readFileSync(TLS_CA_PATH);
            }

            console.log(`[SECURITY] TLS enabled (key: ${TLS_KEY_PATH}, cert: ${TLS_CERT_PATH})`);
            return { server: https.createServer(tlsOptions, requestHandler), protocol: 'https' };
        } catch (error) {
            console.error(`[SECURITY] Failed to initialize TLS: ${error.message}`);
            process.exit(1);
        }
    }

    console.warn('[SECURITY] TLS disabled. Configure TLS_KEY_PATH and TLS_CERT_PATH for production.');
    return { server: http.createServer(requestHandler), protocol: 'http' };
}

const { server, protocol } = createRelayServer();

const wss = new WebSocket.Server({ 
    server,
    maxPayload: SECURITY.MAX_MESSAGE_SIZE,
    // Disable per-message deflate: video frames are already HEVC-compressed,
    // compressing them again just wastes CPU and adds latency
    perMessageDeflate: false,
});

console.log(`AirCatch Relay Server starting on port ${PORT}`);

// ==================== RATE LIMITING HELPERS ====================

function getClientIP(req) {
    return req.headers['x-forwarded-for']?.split(',')[0]?.trim()
        || req.headers['x-real-ip']
        || req.socket.remoteAddress
        || 'unknown';
}

function isIPBanned(ip) {
    const expiry = ipBans.get(ip);
    if (!expiry) return false;
    if (Date.now() > expiry) {
        ipBans.delete(ip);
        return false;
    }
    return true;
}

function checkConnectionLimit(ip) {
    const conns = ipConnections.get(ip);
    return !conns || conns.size < SECURITY.MAX_CONNECTIONS_PER_IP;
}

function trackConnection(ip, ws) {
    if (!ipConnections.has(ip)) ipConnections.set(ip, new Set());
    ipConnections.get(ip).add(ws);
}

function untrackConnection(ip, ws) {
    const conns = ipConnections.get(ip);
    if (conns) {
        conns.delete(ws);
        if (conns.size === 0) ipConnections.delete(ip);
    }
}

function checkRegistrationRate(ip) {
    const now = Date.now();
    const rec = ipRegistrations.get(ip);
    if (!rec || now > rec.resetAt) {
        ipRegistrations.set(ip, { count: 1, resetAt: now + 60000 });
        return true;
    }
    rec.count++;
    return rec.count <= SECURITY.MAX_REGISTRATIONS_PER_MINUTE;
}

function trackFailedRoomAttempt(ip) {
    const now = Date.now();
    const rec = roomFailedAttempts.get(ip);
    if (!rec || now > rec.resetAt) {
        roomFailedAttempts.set(ip, { count: 1, resetAt: now + 60000 });
        return;
    }
    rec.count++;
    if (rec.count >= SECURITY.MAX_FAILED_ROOM_ATTEMPTS) {
        ipBans.set(ip, now + SECURITY.BAN_DURATION_MS);
        roomFailedAttempts.delete(ip);
        console.log(`[SECURITY] IP ${ip} temporarily banned (room brute-force)`);
    }
}

// ==================== CONNECTION HANDLER ====================

wss.on('connection', (ws, req) => {
    const clientIP = getClientIP(req);
    
    // --- Security gate ---
    if (isIPBanned(clientIP)) {
        ws.close(1008, 'Temporarily banned');
        return;
    }
    if (!checkConnectionLimit(clientIP)) {
        ws.close(1008, 'Connection limit exceeded');
        return;
    }
    
    trackConnection(clientIP, ws);
    ws.isAlive = true;
    
    let registered = false;
    let role = null;
    let roomCode = null;
    let channel = null; // 'combined', 'video', or 'control'
    
    ws.on('pong', () => { ws.isAlive = true; });
    
    ws.on('message', (message) => {
        // Handle registration (first message must be JSON)
        if (!registered) {
            try {
                // SECURITY: Limit registration message size
                if (message.length > SECURITY.MAX_REGISTRATION_SIZE) {
                    ws.close(1009, 'Registration too large');
                    return;
                }
                
                if (!checkRegistrationRate(clientIP)) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Rate limited' }));
                    ws.close(1008, 'Rate limited');
                    return;
                }
                
                const data = JSON.parse(message.toString());
                
                if (data.type !== 'register') {
                    ws.send(JSON.stringify({ type: 'error', message: 'First message must be registration' }));
                    ws.close();
                    return;
                }
                
                if (!data.role || !['host', 'client'].includes(data.role)) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Invalid role' }));
                    ws.close();
                    return;
                }
                
                if (!data.roomCode || data.roomCode.length < 4 || data.roomCode.length > SECURITY.MAX_ROOM_CODE_LENGTH) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Invalid room code' }));
                    ws.close();
                    return;
                }
                
                // SECURITY: Sanitize room code - alphanumeric only
                const sanitizedCode = data.roomCode.toUpperCase().replace(/[^A-Z0-9]/g, '');
                if (sanitizedCode.length < 4) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Invalid room code characters' }));
                    ws.close();
                    return;
                }
                
                role = data.role;
                roomCode = sanitizedCode;
                // Channel defaults to 'combined' for backwards compatibility
                channel = data.channel || 'combined';
                if (!['combined', 'video', 'control'].includes(channel)) {
                    channel = 'combined';
                }
                
                // Check room limits (only when creating new rooms)
                if (!rooms.has(roomCode) && rooms.size >= SECURITY.MAX_ROOMS) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Server at capacity' }));
                    ws.close();
                    return;
                }
                
                // Get or create room with multi-channel support
                if (!rooms.has(roomCode)) {
                    rooms.set(roomCode, { 
                        host: null, client: null,
                        hostVideo: null, clientVideo: null,
                        hostControl: null, clientControl: null,
                        lastActivity: Date.now()
                    });
                }
                
                const room = rooms.get(roomCode);
                
                // Determine socket key based on role and channel
                const socketKey = channel === 'combined' ? role : `${role}${channel.charAt(0).toUpperCase() + channel.slice(1)}`;
                
                // Check if slot is already taken
                if (room[socketKey] !== null) {
                    // SECURITY: Generic error to prevent room enumeration
                    trackFailedRoomAttempt(clientIP);
                    ws.send(JSON.stringify({ type: 'error', message: 'Room unavailable' }));
                    ws.close();
                    return;
                }
                
                // Register in room
                room[socketKey] = ws;
                room.lastActivity = Date.now();
                wsToRoom.set(ws, { roomCode, role, channel });
                registered = true;
                
                console.log(`${role.toUpperCase()} (${channel}) registered in room ${roomCode}`);
                
                // Check peer connectivity based on channel
                const peerKey = channel === 'combined'
                    ? (role === 'host' ? 'client' : 'host')
                    : (role === 'host' ? `client${channel.charAt(0).toUpperCase() + channel.slice(1)}` : `host${channel.charAt(0).toUpperCase() + channel.slice(1)}`);
                const isPeerConnected = room[peerKey] !== null;
                
                // Send success response
                ws.send(JSON.stringify({ 
                    type: 'registered', 
                    role: role,
                    roomCode: roomCode,
                    channel: channel,
                    peerConnected: isPeerConnected
                }));
                
                // Notify peer if already connected (same channel)
                const peer = room[peerKey];
                if (peer && peer.readyState === WebSocket.OPEN) {
                    peer.send(JSON.stringify({ type: 'peer_connected', peerRole: role, channel: channel }));
                    ws.send(JSON.stringify({ type: 'peer_connected', peerRole: role === 'host' ? 'client' : 'host', channel: channel }));
                }
                
            } catch (e) {
                ws.send(JSON.stringify({ type: 'error', message: 'Invalid registration' }));
                ws.close();
            }
            return;
        }
        
        // ---- After registration: relay binary data to peer on same channel ----
        const roomInfo = wsToRoom.get(ws);
        if (!roomInfo) return;
        
        const room = rooms.get(roomInfo.roomCode);
        if (!room) return;
        
        room.lastActivity = Date.now();
        
        // Determine peer socket key based on channel
        const peerKey = roomInfo.channel === 'combined'
            ? (roomInfo.role === 'host' ? 'client' : 'host')
            : (roomInfo.role === 'host' 
                ? `client${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}` 
                : `host${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}`);
        const peer = room[peerKey];
        
        if (!peer || peer.readyState !== WebSocket.OPEN) return;
        
        const packet = parseAirCatchPacket(message);

        // PERFORMANCE: Video channel backpressure - drop video payload under pressure.
        if ((roomInfo.channel === 'video' || roomInfo.channel === 'combined') &&
            peer.bufferedAmount > PERFORMANCE.BACKPRESSURE_THRESHOLD) {
            if (packet && (packet.type === PACKET.VIDEO_FRAME || packet.type === PACKET.VIDEO_FRAME_CHUNK)) {
                return;
            }
        }

        // PERFORMANCE: Control channel backpressure - shed non-critical control traffic
        // to prevent touch/keyboard from being delayed behind stale queue.
        if ((roomInfo.channel === 'control' || roomInfo.channel === 'combined') &&
            peer.bufferedAmount > PERFORMANCE.CONTROL_BACKPRESSURE_THRESHOLD) {
            if (shouldDropControlPacketUnderPressure(packet, peer.bufferedAmount)) {
                return;
            }
        }
        
        peer.send(message);
    });
    
    ws.on('close', () => {
        untrackConnection(clientIP, ws);
        
        const roomInfo = wsToRoom.get(ws);
        if (roomInfo) {
            const room = rooms.get(roomInfo.roomCode);
            if (room) {
                const socketKey = roomInfo.channel === 'combined' 
                    ? roomInfo.role 
                    : `${roomInfo.role}${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}`;
                
                room[socketKey] = null;
                
                // Notify peer of disconnect (on same channel)
                const peerKey = roomInfo.channel === 'combined'
                    ? (roomInfo.role === 'host' ? 'client' : 'host')
                    : (roomInfo.role === 'host' 
                        ? `client${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}` 
                        : `host${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}`);
                const peer = room[peerKey];
                if (peer && peer.readyState === WebSocket.OPEN) {
                    peer.send(JSON.stringify({ type: 'peer_disconnected', peerRole: roomInfo.role, channel: roomInfo.channel }));
                }
                
                // Clean up empty rooms
                const allEmpty = !room.host && !room.client && 
                                 !room.hostVideo && !room.clientVideo && 
                                 !room.hostControl && !room.clientControl;
                if (allEmpty) {
                    rooms.delete(roomInfo.roomCode);
                }
            }
            wsToRoom.delete(ws);
        }
    });
    
    ws.on('error', (error) => {
        console.error(`WebSocket error from ${clientIP}: ${error.message}`);
    });
});

// ==================== PERIODIC CLEANUP ====================

// Ping/pong heartbeat for faster disconnect detection
const pingInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
            ws.terminate();
            return;
        }
        ws.isAlive = false;
        ws.ping();
    });
}, PERFORMANCE.PING_INTERVAL_MS);

// Clean up idle rooms and stale rate-limiting records every 60s
const cleanupInterval = setInterval(() => {
    const now = Date.now();
    
    for (const [code, room] of rooms) {
        if (now - room.lastActivity > SECURITY.ROOM_IDLE_TIMEOUT_MS) {
            if (room.host && room.host.readyState === WebSocket.OPEN) room.host.close(1000, 'Idle timeout');
            if (room.client && room.client.readyState === WebSocket.OPEN) room.client.close(1000, 'Idle timeout');
            if (room.hostVideo && room.hostVideo.readyState === WebSocket.OPEN) room.hostVideo.close(1000, 'Idle timeout');
            if (room.clientVideo && room.clientVideo.readyState === WebSocket.OPEN) room.clientVideo.close(1000, 'Idle timeout');
            if (room.hostControl && room.hostControl.readyState === WebSocket.OPEN) room.hostControl.close(1000, 'Idle timeout');
            if (room.clientControl && room.clientControl.readyState === WebSocket.OPEN) room.clientControl.close(1000, 'Idle timeout');
            rooms.delete(code);
            console.log(`Room ${code} cleaned up (idle timeout)`);
        }
    }
    
    // Purge stale rate-limiting entries
    for (const [ip, rec] of ipRegistrations) {
        if (now > rec.resetAt) ipRegistrations.delete(ip);
    }
    for (const [ip, rec] of roomFailedAttempts) {
        if (now > rec.resetAt) roomFailedAttempts.delete(ip);
    }
    for (const [ip, expiry] of ipBans) {
        if (now > expiry) ipBans.delete(ip);
    }
}, 60000);

// ==================== SERVER START ====================

server.listen(PORT, () => {
    console.log(`AirCatch Relay Server running on port ${PORT}`);
    console.log(`Health check: ${protocol}://localhost:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('Shutting down...');
    clearInterval(pingInterval);
    clearInterval(cleanupInterval);
    wss.clients.forEach(ws => ws.close(1001, 'Server shutting down'));
    server.close(() => process.exit(0));
});

process.on('SIGINT', () => {
    console.log('Shutting down...');
    clearInterval(pingInterval);
    clearInterval(cleanupInterval);
    wss.clients.forEach(ws => ws.close(1001, 'Server shutting down'));
    server.close(() => process.exit(0));
});
