import http from 'http';
import { WebSocketServer } from 'ws';

const port = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('AirCatch Relay is Running');
});
const wss = new WebSocketServer({ server, path: '/ws' });

const sessions = new Map();

// Rate limiting: track failed attempts per IP
const rateLimitMap = new Map(); // IP -> { attempts: number, blockedUntil: timestamp }
const MAX_ATTEMPTS = 5;
const BLOCK_DURATION_MS = 60 * 1000; // 1 minute block

function isRateLimited(ip) {
  const record = rateLimitMap.get(ip);
  if (!record) return false;
  
  if (Date.now() < record.blockedUntil) {
    return true; // Still blocked
  }
  
  // Block expired, reset
  if (record.blockedUntil > 0) {
    rateLimitMap.delete(ip);
  }
  return false;
}

function recordAttempt(ip, success) {
  if (success) {
    rateLimitMap.delete(ip); // Clear on success
    return;
  }
  
  const record = rateLimitMap.get(ip) || { attempts: 0, blockedUntil: 0 };
  record.attempts++;
  
  if (record.attempts >= MAX_ATTEMPTS) {
    record.blockedUntil = Date.now() + BLOCK_DURATION_MS;
    console.log(`Rate limited IP ${ip} for ${BLOCK_DURATION_MS / 1000}s after ${record.attempts} failed attempts`);
  }
  
  rateLimitMap.set(ip, record);
}

function getSession(sessionId) {
  if (!sessions.has(sessionId)) {
    sessions.set(sessionId, { host: null, client: null });
  }
  return sessions.get(sessionId);
}

wss.on('connection', (ws, req) => {
  // Get client IP (handles proxies)
  const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress || 'unknown';
  
  // Check rate limit on connection
  if (isRateLimited(ip)) {
    console.log(`Rejected rate-limited IP: ${ip}`);
    ws.close(4029, 'Too many attempts. Try again later.');
    return;
  }
  
  ws.clientIP = ip;
  
  ws.on('message', (data, isBinary) => {
    // 1. Binary Relay (Video Frames) - Forward transparently
    if (isBinary) {
      const sessionId = ws.sessionId;
      if (!sessionId) return; // Ignore if not registered

      const session = sessions.get(sessionId);
      if (!session) return;

      const target = ws.role === 'host' ? session.client : session.host;
      if (target && target.readyState === target.OPEN) {
        target.send(data, { binary: true });
      }
      return;
    }

    // 2. JSON Control Messages
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch {
      return;
    }

    const { type, sessionId, role, channel, payload } = message || {};
    if (!type || !sessionId) return;

    if (type === 'register') {
      const session = getSession(sessionId);
      
      // Validate: session should have matching counterpart within reasonable time
      // For now, just track registration
      if (role === 'host') {
        if (session.host && session.host !== ws) {
          // Another host trying to register - suspicious
          console.log(`Duplicate host registration attempt for session ${sessionId} from ${ip}`);
          recordAttempt(ip, false);
          ws.close(4001, 'Session already has a host');
          return;
        }
        session.host = ws;
      }
      if (role === 'client') {
        if (session.client && session.client !== ws) {
          // Another client trying to register - suspicious
          console.log(`Duplicate client registration attempt for session ${sessionId} from ${ip}`);
          recordAttempt(ip, false);
          ws.close(4001, 'Session already has a client');
          return;
        }
        session.client = ws;
      }
      
      ws.sessionId = sessionId;
      ws.role = role;
      recordAttempt(ip, true); // Successful registration
      console.log(`Registered ${role} for session ${sessionId} from ${ip}`);
      return;
    }

    if (type === 'relay' || type === 'candidate') {
      const session = getSession(sessionId);
      const target = ws.role === 'host' ? session.client : session.host;
      if (target && target.readyState === target.OPEN) {
        target.send(JSON.stringify({ type, sessionId, channel, payload }));
      }
    }
  });

  ws.on('close', () => {
    const sessionId = ws.sessionId;
    if (!sessionId) return;
    const session = sessions.get(sessionId);
    if (!session) return;
    if (session.host === ws) session.host = null;
    if (session.client === ws) session.client = null;
    if (!session.host && !session.client) sessions.delete(sessionId);
  });
});

// Cleanup stale rate limit records every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [ip, record] of rateLimitMap.entries()) {
    if (record.blockedUntil > 0 && now > record.blockedUntil) {
      rateLimitMap.delete(ip);
    }
  }
}, 5 * 60 * 1000);

server.listen(port, () => {
  console.log(`AirCatch relay listening on :${port} (with rate limiting)`);
});
