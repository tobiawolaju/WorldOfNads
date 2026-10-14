#!/usr/bin/env bash
# Diagnostic: start the server, probe /health, a websocket handshake, and the fallback path.
source "$HOME/.cargo/env"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/wons-target}"
unset LD_LIBRARY_PATH

"$CARGO_TARGET_DIR/debug/room-server" >/tmp/rs.log 2>&1 &
SRV=$!
sleep 1.5

echo "== /health =="
curl -s -i --max-time 2 http://127.0.0.1:8080/health
echo
echo "== handshake to /?username=test =="
curl -s -i --max-time 2 \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  "http://127.0.0.1:8080/?username=test"
echo
echo "== fallback /foo =="
curl -s -i --max-time 2 http://127.0.0.1:8080/foo
echo
echo "== server log =="
cat /tmp/rs.log

kill "$SRV" 2>/dev/null
wait "$SRV" 2>/dev/null
true
