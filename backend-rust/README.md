# room-server (Rust)

The realtime arena room server for World of Nads. This is the **Phase 1 spike**
of the migration described in [`docs/rust-game-server-migration.md`](../docs/rust-game-server-migration.md):
one room, implemented in Rust, that is **wire-compatible** with the current Node
game server (`backend/index.js`). The Godot client connects unchanged.

Everything that is *not* the 20 Hz room simulation (auth, Firebase, Postgres
analytics, on-chain settlement, `/events` fan-out, matchmaking, HTTP API) stays
in the Node control plane. This crate only owns the game socket.

## What it does today

- Serves the game WebSocket on `/` (and any non-`/events` path) and the events
  feed on `/events`, matching the Node upgrade routing.
- MessagePack frames with the **same `type`s and field names** as Node:
  - server → client: `connect`, `state_full`, `state_delta`, `reward_update`
    (and `event` on the events feed).
  - client → server: `update_state`, `pickup_request`, `use_request`,
    `drop_request`, `request_full_state`, `client_event`.
- Area-of-interest replication over an 18 m grid (`CELL_REPLICATION_RADIUS` 3),
  distance-banded update rates (20/15/6 Hz), 2 s full snapshots, 1 s match
  heartbeat.
- Server-authoritative movement validation (horizontal/vertical speed caps,
  1.75× slide), item holds (chicken / lootbox / 5 power-ups), storm shrink,
  XP/MON reward ticks, and the full round lifecycle (countdown → match → winner
  event → batch reset that closes all clients with `round_finished`).
- Health endpoint at `/health`.

## What is intentionally not here yet (Phase 2+)

- Session-token verification (the control plane issues tokens; the spike accepts
  the username part of `<token>:<username>`). Tracked in the migration doc.
- Matchmaking / room sharding, per-room allocation, and the VM topology.
- Postgres/Firebase/on-chain I/O and the `/events` HTTP JSON snapshot.
- Backpressure bounds (`MAX_CLIENT_BUFFERED_BYTES`) — unbounded channels for now.

## Build / test / run

The toolchain lives in WSL (Ubuntu). Keep the build artifacts off the Windows
disk by pointing `CARGO_TARGET_DIR` at the WSL home:

```bash
cd backend-rust
source "$HOME/.cargo/env"
export CARGO_TARGET_DIR="$HOME/wons-target"
cargo test          # unit tests (protocol shape, movement clamp, item holds)
cargo run           # listens on 0.0.0.0:8080
```

Live smoke test (starts the server, connects a client, prints decoded frames):

```bash
bash scripts/smoke.sh                                   # local binary
bash scripts/smoke.sh ws://127.0.0.1:18080/?username=x  # anything already running
```

Zero-install Node probe (Node 22+, no npm, no WSL/Docker needed) — great for checking
a deployed instance from Windows:

```bash
node scripts/smoke.mjs --selftest                              # decoder check, no network
node scripts/smoke.mjs wss://wons-room-server.onrender.com/?username=probe
```

Point the Godot client at it by using `LOCAL_URL` (`ws://localhost:8080`).

## Docker

```bash
docker build -t wons-room-server backend-rust
docker run --rm -p 8080:8080 wons-room-server

# build + run + protocol-test + health check + cleanup in one shot:
bash scripts/docker-smoke.sh    # host 18080 -> container $PORT (8090, to exercise $PORT)
```

The container honors `$PORT` (falls back to 8080) and exposes `/health`.

## Render (interim test deployment)

`render.yaml` at the repo root declares a single Docker web service
(`wons-room-server`) built from this crate. It intentionally declares *only* that
service, so a Blueprint sync can never touch the existing dashboard-configured
Node backend. Deploy either way:

- Render → Blueprints → New Blueprint → pick this repo (reads `render.yaml`), or
- Manual Web Service: Docker runtime, Dockerfile `./backend-rust/Dockerfile`,
  context `./backend-rust`, health check `/health`.

Then verify remotely:

```bash
bash scripts/smoke.sh 'wss://wons-room-server.onrender.com/?username=smoke'
```

The Godot client selects it through `ROOM_URL` in
`godot/scripts/player/PlayerManager.gd`; set that const back to `LIVE_URL` to
talk to the Node room server again. Note the free plan sleeps after ~15 min
without traffic (~1 min cold start), which the client's reconnect backoff rides
out; switch `plan:` to `starter` if that gets annoying.

## Configuration

Constants mirror `backend/index.js` and live in `src/config.rs`. The listen port
honors `$PORT` (Render/PaaS convention) and otherwise defaults to 8080.

Two env vars tie this service to the control plane, and each must hold the **same
value on both services**:

| variable | used for | half-set failure |
|---|---|---|
| `CONTROL_PLANE_URL` | base URL for `GET /internal/matches` and the settlement POST | defaults to the public API |
| `INTERNAL_SECRET` | `x-internal-secret` on both internal routes | control plane set, this unset → 403 on the registry and on settlement: rooms fall back to `default` and escrowed matches stay unsettled until `refundExpired` |
| `SESSION_TOKEN_SECRET` | verifies the `<expiresAt>.<hmac>` token on connect (`src/auth.rs`) | set here but not on the control plane → every web player is rejected with `1008 invalid_token`; set on neither → any token is accepted, so clients can skip the control plane |

For local runs, export them in the shell before `cargo run` (the crate reads the
process environment, not `backend/.env`):

```bash
export INTERNAL_SECRET=... SESSION_TOKEN_SECRET=...
```

When `INTERNAL_SECRET` is unset on the control plane its internal routes accept
anonymous requests — including the settlement route that pays the escrow — so
only leave it unset on a throwaway deployment.
