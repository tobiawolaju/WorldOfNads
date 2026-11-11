#!/usr/bin/env node
/**
 * Minimal dependency-free WebSocket server for local connectivity testing.
 * - Accepts WS connections on ws://127.0.0.1:8080 (or PORT env / --port)
 * - Completes RFC6455 handshake so clients like Godot WebSocketPeer can connect
 * - Logs connects/disconnects; optionally echoes text frames
 *
 * Usage:
 *   node tools/local-ws-test-server.mjs
 *   node tools/local-ws-test-server.mjs --port 8080
 *   node tools/local-ws-test-server.mjs --port 8080 --echo
 *
 * Note: This is NOT the game room server protocol; it's for WS connectivity tests
 * (e.g. godot/scenes/test_ws.tscn).
 */

import http from "node:http";
import crypto from "node:crypto";

const args = process.argv.slice(2);
function getArg(name, def = undefined) {
  const i = args.indexOf(name);
  if (i === -1) return def;
  const v = args[i + 1];
  return v && !v.startsWith("--") ? v : def;
}
const PORT = Number(getArg("--port", process.env.PORT || "8080"));
const HOST = getArg("--host", process.env.HOST || "127.0.0.1");
const ECHO = args.includes("--echo");
const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "text/plain" });
    res.end("ok\n");
    return;
  }
  res.writeHead(426, {
    "content-type": "text/plain",
    "upgrade": "websocket",
    "connection": "Upgrade",
  });
  res.end("WebSocket endpoint. Use ws:// to connect.\n");
});

server.on("upgrade", (req, socket) => {
  const upgrade = String(req.headers.upgrade || "").toLowerCase();
  const key = req.headers["sec-websocket-key"];
  if (upgrade !== "websocket" || !key || Array.isArray(key)) {
    socket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
    socket.destroy();
    return;
  }

  const accept = crypto
    .createHash("sha1")
    .update(key + WS_GUID)
    .digest("base64");

  const headers = [
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${accept}`,
    "\r\n",
  ];
  socket.write(headers.join("\r\n"));

  const peer = `${socket.remoteAddress || "?"}:${socket.remotePort || "?"}`;
  console.log(`[local-ws] connected ${peer} url=${req.url}`);

  let buf = Buffer.alloc(0);
  socket.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    buf = processFrames(socket, buf, peer);
  });
  socket.on("close", () => console.log(`[local-ws] closed ${peer}`));
  socket.on("end", () => console.log(`[local-ws] end ${peer}`));
  socket.on("error", (err) => console.log(`[local-ws] error ${peer}: ${err.message}`));
});

function processFrames(socket, buf, peer) {
  while (buf.length >= 2) {
    const b0 = buf[0];
    const b1 = buf[1];
    const opcode = b0 & 0x0f;
    const masked = (b1 & 0x80) !== 0;
    let len = b1 & 0x7f;
    let off = 2;

    if (len === 126) {
      if (buf.length < off + 2) return buf;
      len = buf.readUInt16BE(off);
      off += 2;
    } else if (len === 127) {
      if (buf.length < off + 8) return buf;
      const big = buf.readBigUInt64BE(off);
      if (big > BigInt(Number.MAX_SAFE_INTEGER)) {
        socket.destroy();
        return Buffer.alloc(0);
      }
      len = Number(big);
      off += 8;
    }

    const maskLen = masked ? 4 : 0;
    if (buf.length < off + maskLen + len) return buf;
    let payload = Buffer.from(buf.slice(off + maskLen, off + maskLen + len));
    if (masked) {
      const mask = buf.slice(off, off + 4);
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
    }
    buf = buf.slice(off + maskLen + len);

    if (opcode === 0x8) {
      // Close
      let code = 1000;
      let reason = "";
      if (payload.length >= 2) {
        code = payload.readUInt16BE(0);
        reason = payload.slice(2).toString("utf8");
      }
      console.log(`[local-ws] recv close ${peer} code=${code} reason='${reason}'`);
      // Echo close and end.
      const out = Buffer.alloc(2);
      out.writeUInt16BE(1000, 0);
      sendFrame(socket, 0x8, out);
      try { socket.end(); } catch {}
      return Buffer.alloc(0);
    } else if (opcode === 0x9) {
      // Ping -> Pong
      console.log(`[local-ws] recv ping ${peer} bytes=${payload.length}`);
      sendFrame(socket, 0xA, payload);
    } else if (opcode === 0xA) {
      console.log(`[local-ws] recv pong ${peer} bytes=${payload.length}`);
    } else if (opcode === 0x1) {
      const text = payload.toString("utf8");
      console.log(`[local-ws] recv text ${peer} bytes=${payload.length} preview=${JSON.stringify(text.slice(0, 120))}`);
      if (ECHO) sendFrame(socket, 0x1, Buffer.from(text, "utf8"));
    } else if (opcode === 0x2) {
      console.log(`[local-ws] recv binary ${peer} bytes=${payload.length}`);
      if (ECHO) sendFrame(socket, 0x2, payload);
    } else {
      console.log(`[local-ws] recv opcode=${opcode} ${peer} bytes=${payload.length}`);
    }
  }
  return buf;
}

function sendFrame(socket, opcode, payload) {
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x80 | (opcode & 0x0f); // FIN + opcode
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | (opcode & 0x0f);
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | (opcode & 0x0f);
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  try {
    socket.write(Buffer.concat([header, payload]));
  } catch {}
}

server.listen(PORT, HOST, () => {
  console.log(`[local-ws] listening on ws://${HOST}:${PORT}/ (health: http://${HOST}:${PORT}/health)`);
  console.log(`[local-ws] echo=${ECHO} (for Godot test_ws.tscn connectivity, echo not required)`);
});
