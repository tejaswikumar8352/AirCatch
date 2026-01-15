import http from 'http';
import { WebSocketServer } from 'ws';

const port = process.env.PORT || 8080;

const server = http.createServer();
const wss = new WebSocketServer({ server, path: '/ws' });

const sessions = new Map();

function getSession(sessionId) {
  if (!sessions.has(sessionId)) {
    sessions.set(sessionId, { host: null, client: null });
  }
  return sessions.get(sessionId);
}

wss.on('connection', (ws) => {
  ws.on('message', (data) => {
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
      if (role === 'host') session.host = ws;
      if (role === 'client') session.client = ws;
      ws.sessionId = sessionId;
      ws.role = role;
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

server.listen(port, () => {
  console.log(`AirCatch relay listening on :${port}`);
});
