/**
 * AirCatch Remote Relay Server
 * 
 * WebSocket relay server that connects AirCatchHost (Mac) and AirCatchClient (iPad)
 * when they're on different networks.
 * 
 * Protocol:
 * - First message from client is JSON: { "type": "register", "role": "host"|"client", "roomCode": "XXXXXX" }
 * - After registration, all messages are binary data relayed to the paired peer
 */

const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;

// Room storage: roomCode -> { host: WebSocket, client: WebSocket }
const rooms = new Map();

// WebSocket to room mapping for cleanup
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
                
                // Get or create room
                if (!rooms.has(roomCode)) {
                    rooms.set(roomCode, { host: null, client: null });
                }
                
                const room = rooms.get(roomCode);
                
                // Check if role is already taken
                if (room[role] !== null) {
                    ws.send(JSON.stringify({ type: 'error', message: `Room ${roomCode} already has a ${role}` }));
                    ws.close();
                    return;
                }
                
                // Register in room
                room[role] = ws;
                wsToRoom.set(ws, { roomCode, role });
                registered = true;
                
                console.log(`✅ ${role.toUpperCase()} registered in room ${roomCode}`);
                
                // Send success response
                ws.send(JSON.stringify({ 
                    type: 'registered', 
                    role: role,
                    roomCode: roomCode,
                    peerConnected: room[role === 'host' ? 'client' : 'host'] !== null
                }));
                
                // Notify peer if already connected
                const peer = room[role === 'host' ? 'client' : 'host'];
                if (peer && peer.readyState === WebSocket.OPEN) {
                    peer.send(JSON.stringify({ type: 'peer_connected', peerRole: role }));
                    ws.send(JSON.stringify({ type: 'peer_connected', peerRole: role === 'host' ? 'client' : 'host' }));
                }
                
            } catch (e) {
                ws.send(JSON.stringify({ type: 'error', message: 'Invalid JSON for registration' }));
                ws.close();
            }
            return;
        }
        
        // After registration, relay binary data to peer
        const roomInfo = wsToRoom.get(ws);
        if (!roomInfo) return;
        
        const room = rooms.get(roomInfo.roomCode);
        if (!room) return;
        
        const peerRole = roomInfo.role === 'host' ? 'client' : 'host';
        const peer = room[peerRole];
        
        if (peer && peer.readyState === WebSocket.OPEN) {
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
                // Clear this connection from room
                room[roomInfo.role] = null;
                
                // Notify peer of disconnect
                const peerRole = roomInfo.role === 'host' ? 'client' : 'host';
                const peer = room[peerRole];
                if (peer && peer.readyState === WebSocket.OPEN) {
                    peer.send(JSON.stringify({ type: 'peer_disconnected', peerRole: roomInfo.role }));
                }
                
                // Clean up empty rooms
                if (room.host === null && room.client === null) {
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
