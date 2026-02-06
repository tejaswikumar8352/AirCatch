/**
 * AirCatch Remote Relay Server
 * 
 * WebSocket relay server that connects AirCatchHost (Mac) and AirCatchClient (iPad)
 * when they're on different networks.
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

const PORT = process.env.PORT || 8080;

// Room storage: roomCode -> { 
//   host: WebSocket,           // Legacy combined socket
//   client: WebSocket,         // Legacy combined socket
//   hostVideo: WebSocket,      // Video-only socket (new)
//   clientVideo: WebSocket,    // Video-only socket (new)
//   hostControl: WebSocket,    // Control/audio socket (new)
//   clientControl: WebSocket   // Control/audio socket (new)
// }
const rooms = new Map();

// WebSocket to room mapping for cleanup
// { roomCode, role, channel } where channel is 'combined'|'video'|'control'
const wsToRoom = new Map();

const server = http.createServer((req, res) => {
    // Health check endpoint
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            status: 'ok', 
            rooms: rooms.size,
            uptime: process.uptime()
        }));
        return;
    }
    
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('AirCatch Relay Server\n');
});

const wss = new WebSocket.Server({ server });

console.log(`🚀 AirCatch Relay Server starting on port ${PORT}`);

wss.on('connection', (ws, req) => {
    const clientIP = req.socket.remoteAddress;
    console.log(`📱 New connection from ${clientIP}`);
    
    let registered = false;
    let role = null;
    let roomCode = null;
    let channel = null; // 'combined', 'video', or 'control'
    
    ws.on('message', (message) => {
        // Handle registration (first message must be JSON)
        if (!registered) {
            try {
                const data = JSON.parse(message.toString());
                
                if (data.type !== 'register') {
                    ws.send(JSON.stringify({ type: 'error', message: 'First message must be registration' }));
                    ws.close();
                    return;
                }
                
                if (!data.role || !['host', 'client'].includes(data.role)) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Invalid role. Must be "host" or "client"' }));
                    ws.close();
                    return;
                }
                
                if (!data.roomCode || data.roomCode.length < 4) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Invalid room code' }));
                    ws.close();
                    return;
                }
                
                role = data.role;
                roomCode = data.roomCode.toUpperCase();
                // Channel defaults to 'combined' for backwards compatibility
                channel = data.channel || 'combined';
                if (!['combined', 'video', 'control'].includes(channel)) {
                    channel = 'combined';
                }
                
                // Get or create room with multi-channel support
                if (!rooms.has(roomCode)) {
                    rooms.set(roomCode, { 
                        host: null, client: null,           // Legacy combined
                        hostVideo: null, clientVideo: null, // Video channel
                        hostControl: null, clientControl: null // Control channel
                    });
                }
                
                const room = rooms.get(roomCode);
                
                // Determine socket key based on role and channel
                const socketKey = channel === 'combined' ? role : `${role}${channel.charAt(0).toUpperCase() + channel.slice(1)}`;
                
                // Check if slot is already taken
                if (room[socketKey] !== null) {
                    ws.send(JSON.stringify({ type: 'error', message: `Room ${roomCode} already has a ${role} (${channel})` }));
                    ws.close();
                    return;
                }
                
                // Register in room
                room[socketKey] = ws;
                wsToRoom.set(ws, { roomCode, role, channel });
                registered = true;
                
                console.log(`✅ ${role.toUpperCase()} (${channel}) registered in room ${roomCode}`);
                
                // Check peer connectivity based on channel
                const isPeerConnected = channel === 'combined' 
                    ? room[role === 'host' ? 'client' : 'host'] !== null
                    : room[role === 'host' ? `client${channel.charAt(0).toUpperCase() + channel.slice(1)}` : `host${channel.charAt(0).toUpperCase() + channel.slice(1)}`] !== null;
                
                // Send success response
                ws.send(JSON.stringify({ 
                    type: 'registered', 
                    role: role,
                    roomCode: roomCode,
                    channel: channel,
                    peerConnected: isPeerConnected
                }));
                
                // Notify peer if already connected (same channel)
                const peerKey = channel === 'combined'
                    ? (role === 'host' ? 'client' : 'host')
                    : (role === 'host' ? `client${channel.charAt(0).toUpperCase() + channel.slice(1)}` : `host${channel.charAt(0).toUpperCase() + channel.slice(1)}`);
                const peer = room[peerKey];
                if (peer && peer.readyState === WebSocket.OPEN) {
                    peer.send(JSON.stringify({ type: 'peer_connected', peerRole: role, channel: channel }));
                    ws.send(JSON.stringify({ type: 'peer_connected', peerRole: role === 'host' ? 'client' : 'host', channel: channel }));
                }
                
            } catch (e) {
                ws.send(JSON.stringify({ type: 'error', message: 'Invalid JSON for registration' }));
                ws.close();
            }
            return;
        }
        
        // After registration, relay binary data to peer on same channel
        const roomInfo = wsToRoom.get(ws);
        if (!roomInfo) return;
        
        const room = rooms.get(roomInfo.roomCode);
        if (!room) return;
        
        // Determine peer socket key based on channel
        const peerKey = roomInfo.channel === 'combined'
            ? (roomInfo.role === 'host' ? 'client' : 'host')
            : (roomInfo.role === 'host' 
                ? `client${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}` 
                : `host${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}`);
        const peer = room[peerKey];
        
        if (peer && peer.readyState === WebSocket.OPEN) {
            // BACKPRESSURE: Only apply to video channel
            // Control channel is always prioritized (never dropped)
            if (roomInfo.channel === 'video' || roomInfo.channel === 'combined') {
                const BACKPRESSURE_THRESHOLD = 64 * 1024;
                const isVideoFrame = message.length > 5 && (message[0] === 0x0C || message[0] === 0x01); // videoFrameChunk or videoFrame
                
                if (peer.bufferedAmount > BACKPRESSURE_THRESHOLD && isVideoFrame) {
                    // Drop video frame to prevent buffer bloat
                    return;
                }
            }
            
            // Relay the message (binary data) to peer
            peer.send(message);
        }
    });
    
    ws.on('close', () => {
        console.log(`👋 Connection closed from ${clientIP}`);
        
        const roomInfo = wsToRoom.get(ws);
        if (roomInfo) {
            const room = rooms.get(roomInfo.roomCode);
            if (room) {
                // Determine socket key for cleanup
                const socketKey = roomInfo.channel === 'combined' 
                    ? roomInfo.role 
                    : `${roomInfo.role}${roomInfo.channel.charAt(0).toUpperCase() + roomInfo.channel.slice(1)}`;
                
                // Clear this connection from room
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
                
                // Clean up empty rooms (all sockets must be null)
                const allEmpty = !room.host && !room.client && 
                                 !room.hostVideo && !room.clientVideo && 
                                 !room.hostControl && !room.clientControl;
                if (allEmpty) {
                    rooms.delete(roomInfo.roomCode);
                    console.log(`🗑️  Room ${roomInfo.roomCode} deleted (empty)`);
                }
            }
            wsToRoom.delete(ws);
        }
    });
    
    ws.on('error', (error) => {
        console.error(`❌ WebSocket error: ${error.message}`);
    });
    
    // Send ping every 30 seconds to keep connection alive
    const pingInterval = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) {
            ws.ping();
        } else {
            clearInterval(pingInterval);
        }
    }, 30000);
    
    ws.on('close', () => clearInterval(pingInterval));
});

server.listen(PORT, () => {
    console.log(`✅ AirCatch Relay Server running on port ${PORT}`);
    console.log(`   Health check: http://localhost:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('📴 Shutting down...');
    wss.clients.forEach(ws => ws.close());
    server.close(() => process.exit(0));
});
