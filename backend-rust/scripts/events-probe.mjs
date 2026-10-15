// Zero-dependency probe for the /events feed (mirrors backend-rust/scripts/smoke.mjs).
const url = process.argv[2] ?? "wss://wons-room-server.onrender.com/events";
console.log("probing", url);
const ws = new WebSocket(url);
ws.binaryType = "arraybuffer";
const timer = setTimeout(() => {
  console.log("TIMEOUT waiting for the first frame");
  process.exit(1);
}, 90000);
ws.onopen = () => console.log("websocket: open (101 upgrade accepted)");
ws.onmessage = (event) => {
  const text =
    typeof event.data === "string" ? event.data : Buffer.from(event.data).toString("utf8");
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    console.log("first frame is not JSON:", text.slice(0, 80));
    process.exit(1);
  }
  console.log("first frame type:", parsed.type, "events:", (parsed.events ?? []).length);
  const ok = parsed.type === "events_snapshot" && Array.isArray(parsed.events);
  console.log(ok ? "EVENTS OK" : "EVENTS UNEXPECTED");
  clearTimeout(timer);
  ws.close();
  process.exit(ok ? 0 : 1);
};
ws.onerror = () => {
  console.log("websocket: error");
  process.exit(1);
};
