#!/usr/bin/env bash
# Smoke-test a room server through the msgpack protocol.
#
#   bash scripts/smoke.sh                                   # build, start LOCAL server, test, stop
#   bash scripts/smoke.sh ws://127.0.0.1:18080/?username=x  # just test an already-running server
#   bash scripts/smoke.sh wss://wons-room-server.onrender.com/?username=x   # remote (Render)
set -uo pipefail
cd "$(dirname "$0")/.."
source "$HOME/.cargo/env"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/wons-target}"
unset LD_LIBRARY_PATH

cargo build --bin room-server --example smoke 2>&1 | tail -n 3
CLIENT="$CARGO_TARGET_DIR/debug/examples/smoke"

if [ $# -ge 1 ]; then
  echo "== client -> $1 =="
  "$CLIENT" "$1"
  exit $?
fi

echo "== client -> local server =="
"$CARGO_TARGET_DIR/debug/room-server" >/tmp/room-server.log 2>&1 &
SRV=$!
sleep 2
"$CLIENT" "ws://127.0.0.1:8080/?username=smoke" || true
kill "$SRV" 2>/dev/null || true
sleep 0.5
echo "----- server log -----"
cat /tmp/room-server.log
