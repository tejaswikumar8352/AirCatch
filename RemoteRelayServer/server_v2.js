/**
 * AirCatch Relay Server v2
 * Supports both WebSocket relay (current) and WebRTC signaling (future)
 */

const WebSocket = require("ws");
const http = require("http");

const PORT = process.env.PORT || 8080;
const BACKPRESSURE_THRESHOLD = 64 * 1024;

const rooms = new Map();
const wsToRoom = new Map();

const server = http.createServer((req, res) => {
    if (req.url === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ 
            status: "ok", 
            rooms: rooms.size, 
            uptime: process.uptime(),
            version: "2.0"
        }));
        return;
    }
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("AirCatch Relay Server v2\n");
});

const wss = new WebSocket.Server({ server });

console.log("AirCatch Relay Server v2 starting on port " + PORT);

wss.on("connection", (ws, req) => {
    const clientIP = req.socket.remoteAddress;
    console.log("New connection from " + clientIP);
    
    let registered = false;
    let role = null;
    let roomCode = null;
    
    ws.on("message", (message) => {
        if (!registered) {
            try {
                const data = JSON.parse(message.toString());
                if (data.type === "register") {
                    handleRegistration(ws, data);
                    registered = true;
                    role = data.role;
                    roomCode = data.roomCode.toUpperCase();
                    return;
                }
            } catch (e) {}
            return;
        }
        
        const roomInfo = wsToRoom.get(ws);
        if (!roomInfo) return;
        
        const room = rooms.get(roomInfo.roomCode);
        if (!room) return;
        
        const targetRole = roomInfo.role === "host" ? "client" : "host";
        const target = room[targetRole];
        
        if (!target || target.readyState !== WebSocket.OPEN) return;
        
        if (target.bufferedAmount > BACKPRESSURE_THRESHOLD) {
            return;
        }
        
        if (Buffer.isBuffer(message)) {
            target.send(message);
        } else {
            try {
                const data = JSON.parse(message.toString());
                target.send(JSON.stringify(data));
                console.log("Relayed " + (data.type || "data") + " from " + roomInfo.role);
            } catch (e) {
                target.send(message);
            }
        }
    });
    
    ws.on("close", () => {
        console.log("Connection closed from " + clientIP);
        handleDisconnect(ws);
    });
    
    ws.on("error", (error) => {
        console.error("WebSocket error: " + error.message);
    });
    
    const pingInterval = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.ping();
        else clearInterval(pingInterval);
    }, 30000);
    
    ws.on("close", () => clearInterval(pingInterval));
});

function handleRegistration(ws, data) {
    const role = data.role;
    const roomCode = data.roomCode.toUpperCase();
    
    if (!role || !["host", "client"].includes(role)) {
        ws.send(JSON.stringify({ type: "error", message: "Invalid role" }));
        ws.close();
        return;
    }
    
    if (!roomCode || roomCode.length < 4) {
        ws.send(JSON.stringify({ type: "error", message: "Invalid room code" }));
        ws.close();
        return;
    }
    
    if (!rooms.has(roomCode)) {
        rooms.set(roomCode, { host: null, client: null });
    }
    
    const room = rooms.get(roomCode);
    
    if (room[role] !== null) {
        ws.send(JSON.stringify({ type: "error", message: "Room " + roomCode + " already has a " + role }));
        ws.close();
        return;
    }
    
    room[role] = ws;
    wsToRoom.set(ws, { roomCode, role });
    
    console.log(role.toUpperCase() + " registered in room " + roomCode);
    
    ws.send(JSON.stringify({
        type: "registered",
        role: role,
        roomCode: roomCode,
        peerConnected: room[role === "host" ? "client" : "host"] !== null
    }));
    
    const peer = room[role === "host" ? "client" : "host"];
    if (peer && peer.readyState === WebSocket.OPEN) {
        peer.send(JSON.stringify({ type: "peer_connected", peerRole: role }));
        ws.send(JSON.stringify({ type: "peer_connected", peerRole: role === "host" ? "client" : "host" }));
    }
}

function handleDisconnect(ws) {
    const roomInfo = wsToRoom.get(ws);
    if (!roomInfo) return;
    
    const room = rooms.get(roomInfo.roomCode);
    if (room) {
        room[roomInfo.role] = null;
        
        const peerRole = roomInfo.role === "host" ? "client" : "host";
        const peer = room[peerRole];
        if (peer && peer.readyState === WebSocket.OPEN) {
            peer.send(JSON.stringify({ type: "peer_disconnected", peerRole: roomInfo.role }));
        }
        
        if (room.host === null && room.client === null) {
            rooms.delete(roomInfo.roomCode);
            console.log("Room " + roomInfo.roomCode + " deleted");
        }
    }
    wsToRoom.delete(ws);
}

server.listen(PORT, () => {
    console.log("AirCatch Relay Server v2 running on port " + PORT);
    console.log("Health check: http://localhost:" + PORT + "/health");
});

process.on("SIGTERM", () => {
    console.log("Shutting down...");
    wss.clients.forEach(ws => ws.close());
    server.close(() => process.exit(0));
});
