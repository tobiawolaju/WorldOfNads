# Rust Game-Server Migration (Realtime Simulation Tier)

**Status:** Proposed (ADR)
**Owner:** TBD
**Related:** [`architecture.md`](../architecture.md), [`docs/authentication.md`](./authentication.md), [`docs/analytics.md`](./analytics.md)

---

## 1. Summary

Today the realtime arena, the HTTP API, authentication, Firebase/Postgres access, and
on-chain settlement all run inside a **single Node.js process** (`backend/index.js`)
holding **one global world**.

This document proposes splitting the system into two tiers:

- **Control plane (Node, stays on Render):** HTTP API, auth/session issuance, Firebase,
  Postgres analytics, on-chain settlement, the `/events` feed, admin endpoints, and
  **matchmaking / room allocation**.
- **Data plane (Rust, on a VM):** the realtime arena simulation — tick loop, AOI
  replication, movement validation, item interactions, match lifecycle, broadcasting —
  running as **many independent rooms**, each shardable across cores.

The **wire protocol stays byte-compatible** (WebSocket + MessagePack), so the
**Godot client does not change** except for the connect URL / room assignment.

The goal is not "Rust" for its own sake — it is **horizontal scale via room sharding**
and **stable tick latency without GC or blocking-call jitter**.

---

## 2. Why (what this actually buys)

| Concern | Today (Node, one world) | Target (Rust rooms, sharded) |
|---|---|---|
| Max concurrent in one arena | a few hundred, degrading | unchanged per room, but see next row |
| Total concurrent players | ~1 process ceiling | N rooms × capacity, across cores |
| Tick p99 / jitter | shared event loop (Firebase, pg, ethers) can stall it | dedicated runtime, no blocking integrations on the tick |
| GC pauses | possible | none |
| RAM / CPU per player | higher | lower → more players per $ |
| Failure isolation | one bad call affects everyone | per-room blast radius |
| Global round reset closes all clients | yes | per-room reset only |

**What Rust does NOT buy by itself:** capacity. Capacity comes from **sharding + a
matchmaker + AOI** (you already have AOI) + a binary protocol (you already have
MsgPack) + backpressure (you already have a `bufferedAmount` guard). Rust makes the
sharded design cheap and low-jitter; it is not a silver bullet on its own.

**PWA note:** the install/fullscreen work is a UX win only. It has **zero** effect on
server capacity or latency and is orthogonal to this migration.

---

## 3. Current architecture (as-is)

Single process, one world. All of the following are **module-level globals** in
`backend/index.js`:

- `players{}` — every connected player.
- `chicken{}` — the single global chicken (objective) state.
- `lootbox{}` — the single global lootbox state.
- `playerRewards{}`, storm state, `matchRunning`, `matchTimeLeft`, `matchStartCountdown`,
  `currentMatchId`, `eventHistory[]`.
- Spatial index: `playerCellIndex`, `cellOccupants` (grid cells).

Confirmed constants (`backend/index.js`):

| Constant | Value | Meaning |
|---|---|---|
| `PORT` | `8080` | HTTP + WS port |
| `BROADCAST_RATE` | `20` | ticks/sec |
| `FIXED_DT` | `1/20` | simulation dt |
| `CELL_SIZE` | `18.0` | AOI grid cell size (units) |
| `CELL_REPLICATION_RADIUS` | `3` | cells around player → ~7×7 ≈ 126u view |
| `FULL_SNAPSHOT_INTERVAL_MS` | `2000` | periodic full snapshot |
| `MATCH_HEARTBEAT_INTERVAL_MS` | `1000` | match-state heartbeat |
| `MAX_CLIENT_BUFFERED_BYTES` | `512*1024` | per-client send backpressure cap |
| `WS_RATE_LIMIT_WINDOW_MS` | `1000` | msg rate-limit window |
| `WS_RATE_LIMIT_MAX_MESSAGES` | `60` | msgs/window |
| `WS_MAX_MESSAGE_SIZE` | `4096` | inbound frame cap |
| `RATE_LIMIT_BAN_DURATION_MS` | `60000` | ban duration on abuse |
| `SESSION_TOKEN_EXPIRY_MS` | `1800000` | 30 min |
| `MAX_PLAYER_SPEED` | `12.0` | units/s horizontal anti-teleport |
| `MAX_PLAYER_VERTICAL_SPEED` | `36.0` | units/s vertical allowance |
| `MAX_THROW_IMPULSE` | `8.0` | throw cap |
| `STORM_SHRINK_INTERVAL` | `20.0` | storm shrink cadence (s) |
| `REWARD_TICK_INTERVAL_SEC` | `1.0` | reward accrual cadence |
| `MATCH_DURATION_SECONDS` | (see source) | round length |

Transport:
- `http.createServer(...)` with two `ws.WebSocketServer({ noServer: true })` instances
  (`gameWss`, `eventsWss`) upgraded from the same port. **Verify the upgrade-path split**
  in `backend/index.js` (~lines 873–960) — the client connects to the root host today.
- MessagePack (`@msgpack/msgpack`) for the game socket; JSON for `/events`.
- Heartbeat: server pings every 30s, terminates sockets that miss a pong.

Simulation of note:
- **Server-authoritative** movement: teleport/speed clamps (`MAX_PLAYER_SPEED`).
- Storm that shrinks; chicken proximity → XP; lootbox holder → MON.
- Match starts when `getPlayerCount() >= currentMinPlayersToStart` (currently **3**).
- Round end → `resetRoundForNextBatch()` which **closes every client** and resets the
  world (global).

Integrations coupled into the same event loop:
- `authService` / `authStore` (device-login auth).
- Firebase (`firebaseClient.js`): matches, users, skins, rewards.
- Postgres analytics (`analyticsService.js`).
- On-chain via `ethers` (`contractClient.js`): `settleMatchOnchain`, `batchStreamMON`,
  `mintXP`, `contractWithdraw`, `createSkinOnchain`, `calcMonPerSec`.
- Timers: 30s match-status worker, 15s limits refresh, 6h PFP refresh.

---

## 4. Target architecture (to-be)

```
                         ┌────────────────────────────────────────────┐
   Godot client ──wss──► │  Edge proxy (Caddy/nginx, TLS, sticky)      │
                         └──────────────┬───────────────┬─────────────┘
                                        │               │
                    /ws/room/<id>       │               │  /api/*, /events, /admin
                                        ▼               ▼
                        ┌───────────────────────┐   ┌──────────────────────────┐
                        │ Rust Room Shard #k     │   │ Node API (Render)         │
                        │ (one process / many    │   │ auth, session tokens,     │
                        │  rooms via tokio)      │   │ matchmaker, Firebase, pg, │
                        │ tick / AOI / validation│   │ ethers settlement, events │
                        └───────────┬───────────┘   └─────────────┬────────────┘
                                    │  signed internal HTTP       │
                                    └─────────────────────────────┘
```

### 4.1 Control plane (Node — unchanged responsibilities)

- Auth / device-login; issue **short-lived, room-scoped session tokens**.
- **Matchmaker**: assign a player to a room with free capacity; pick/host a shard;
  return `{ wsUrl, roomId, sessionToken }`.
- Settlement: on match end, the room reports the result; Node does Firebase +
  on-chain settlement (unchanged logic).
- `/events` feed, admin endpoints, analytics — unchanged.

### 4.2 Data plane (Rust room shard)

- One **tokio** runtime; each **room** is an independent task owning its own state
  (no globals). A process can host many rooms; scale by process count (cores) and VM count.
- 20 Hz tick, msgpack encode, AOI by grid cells (port `CELL_SIZE`/`CELL_REPLICATION_RADIUS`).
- Per-client send backpressure identical to `MAX_CLIENT_BUFFERED_BYTES`.
- No blocking integration calls on the tick. On match end → **async** signed HTTP POST to
  Node; the room resets only itself.

### 4.3 Room identity & capacity

- Room = `{ roomId, shard, capacity, minPlayersToStart, matchDuration }`.
- Matchmaker fills rooms to `capacity` (e.g. 40–60), then opens a new one.
  **This is the actual path to "hundreds concurrent or more."**

---

## 5. Wire protocol contract (must stay byte-compatible)

> **Action required:** before porting, dump the *exact* key names from `backend/index.js`
> for each message below (several reads of this file were unreliable during drafting).
> Treat this as the parity checklist, not the final schema.

**Connect:** `wss://<host>/<path>?username=<token>:<username>&skin=<name>`
Session token is the `<token>` prefix of `username` (format `<token>:<username>`).

**Client → server** (msgpack, `type`-tagged):

| `type` | Purpose |
|---|---|
| `update_state` | position/rotation/velocity + held item |
| `request_full_state` | ask for a `state_full` snapshot |
| `pickup_request` | attempt to pick up chicken/lootbox/item |
| `drop_request` | drop held item |
| `client_event` | gameplay events (feed/analytics) |
| `update_xp` | (legacy/optional) |

**Server → client** (msgpack):

| `type` | Purpose | Known keys |
|---|---|---|
| `state_full` | full snapshot | `players`, `chicken`, `lootbox`, `items`, `match`, `q` |
| `state_delta` | per-tick delta | `players`, `removed[]`, `chicken`, `lootbox`, `items`, `match`, `q:1` |
| `reward_update` | XP/MON accrual (1 Hz) | (verify) |

**Server → client (`/events`, JSON):**

- On connect: `{ "type": "events_snapshot", "events": eventHistory }`
- Streamed events: `{ "type": "event", "event": {...} }` (verify exact envelope)

**Match state (`buildMatchState`) keys:** `timeLeft`, `isRunning`, `durationSeconds`,
`minPlayersToStart`, `maxPlayers`, `connectedPlayers`, `startCountdown`, `matchId`.

**Close codes:** `1008 'match_full'` when capacity exceeded.

**Full-snapshot cadence:** every `FULL_SNAPSHOT_INTERVAL_MS` (2000 ms); deltas otherwise.
The per-recipient diff uses `recipientNetworkState` to avoid resending unchanged entities —
port this too, or bandwidth will regress.

---

## 6. Simulation parity checklist

Port these behaviors 1:1 and assert equality against the Node server with a shared bot:

- [ ] Grid/AOI: cell assignment, occupant tracking, 7×7 replication window, deltas.
- [ ] Movement validation: `MAX_PLAYER_SPEED`, `MAX_PLAYER_VERTICAL_SPEED`,
      `MAX_THROW_IMPULSE` clamps; rejected updates.
- [ ] Inbound limits: `WS_MAX_MESSAGE_SIZE`, rate limit (`60/s`), ban window.
- [x] Send backpressure: skip a client whose queue exceeds `MAX_CLIENT_BUFFERED_BYTES`.
- [x] Heartbeat: ping 30s, terminate on missed pong, cleanup broadcasts `removed`.
- [ ] Match lifecycle: start at `minPlayersToStart`, countdown, timer, winner resolution,
      reward tick (1 Hz), storm shrink cadence.
- [ ] Items: chicken pickup/drop, lootbox pickup/drop, throw impulse, held-item cleanup on
      disconnect (`dropHeldItemsAtPlayer`).
- [ ] Session token validation (shared secret / JWKS).
- [ ] Skin resolution (`resolveSkinName`, `attachmentsForId`) — may stay in Node and be
      passed via the token/params, or be ported (decide).

---

### Parity audit (source-verified against `backend/index.js`)

`[x]` = ported and identical, `[ ]` = still to do.

- [x] Grid/AOI: cell assignment (18 m cells), 7x7 replication window, deltas.
- [x] Movement validation: `MAX_PLAYER_SPEED` (12), `MAX_PLAYER_VERTICAL_SPEED`
      (36), `MAX_THROW_IMPULSE` clamps. Note `throw_x/y/z` are **ignored by Node too**
      (velocities are only ever zeroed), so Rust ignoring them is parity, not drift.
- [x] Inbound limits: `WS_MAX_MESSAGE_SIZE` (4096) + rate limit (60 per 1000 ms) —
      enforced in `net.rs`.
- [x] Heartbeat: ping every 30 s with Node's `isAlive` sweep — a socket that misses the
      previous pong is dropped, and the close path still broadcasts `removed`.
- [x] Match lifecycle: `minPlayersToStart`, 5 s countdown, 180 s timer, winner
      resolution, 1 Hz reward tick, storm shrink cadence.
- [x] Items: chicken/lootbox/p1–p5 pickup/drop/use, held-item cleanup on close.
- [x] Send backpressure: `ClientTx` holds a per-client byte budget and skips bulk frames
      once `MAX_CLIENT_BUFFERED_BYTES` (512 KiB) is queued — Node's `bufferedAmount`
      guard, with Node's semantics: *skip the frame, keep the session*, never a
      disconnect. Control frames (ping/pong/close) bypass the budget so keepalives and
      shutdown still land on a saturated socket. The `/events` feed uses the same guard,
      and a subscriber's queue is released when its socket closes.
- [x] Capacity rejection: same guard as Node (`playerCount() >= maxPlayers` → close at
      connect), fed by the same value the room reports as `match.maxPlayers`. Node reads
      `currentMaxPlayers` from its matchmaker/DB; Rust reads `MAX_PLAYERS` (unset or
      `unlimited` = Node's default of no cap).
- [x] Rate-limit ban window (`RATE_LIMIT_BAN_DURATION_MS`, 60 s + IP ban). The peer IP
      is read from `X-Forwarded-For` (first hop) with an `X-Real-IP` fallback, so it is
      the real client behind Render's proxy; the 61st message in a window bans the IP for
      60 s and closes with `1008 rate_limited`.
- [x] Session token verification: a `token:username` connect form is validated against an
      in-process token store (30 min expiry) and rejected with `1008 invalid_token`
      otherwise. Minting/sharing tokens with the control plane is still open (this is a
      local store, not the Node issuer's).
- [x] Close codes: `1009 message_too_large`, `1008 rate_limited`, `1008 invalid_token`,
      `1008 match_full`, `1008 server_full` (room-count cap).
- [ ] Control-plane skin/xp: Node reads the Firebase profile + wallet; Rust uses the
      `skin`/`skinId` query param and sends `xp: 0`.

### Wire contract (audited against `backend/index.js`)

| Message | Node | Rust | Status |
|---|---|---|---|
| `connect` | `{type,id,username,skin,xp}` | `ConnectMsg` | identical |
| player | `{id,x,y,z,r,a,skin}` | `PlayerNet` | identical |
| `state_full` | `{type,q,players(+u),chicken,lootbox,items,match}` | `StateFull` | identical |
| `state_delta` | optional `players/removed/chicken/lootbox/items/match` | `StateDelta` | identical |
| match | `{t,r,d,min,max,sr,pl,c}`, `max:null` when unset | `MatchNet` | identical |
| constants | rates 20/15/6 Hz, 12/28 m, 2 s / 1 s, scales 100/1000 | `config.rs` | identical |

## 7. Control-plane API additions (Node)

Internal, authenticated (HMAC/JWT with a shared secret), not public:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/matchmake` | Public: returns `{ wsUrl, roomId, sessionToken }` |
| `GET`  | `/internal/rooms` | List rooms + capacity (ops/debug) |
| `POST` | `/internal/rooms/heartbeat` | Room → Node liveness + load |
| `POST` | `/internal/matches/:matchId/result` | Room → Node: final scores → Firebase + on-chain |
| `GET`  | `/internal/session/verify` | (Optional) if Rust can't verify tokens locally |

The Rust shard verifies session tokens locally (shared secret) to avoid a round-trip per
connect; Node remains the issuer.

---

## 8. VM / deployment topology

**Interim (now):** the room server also ships with `backend-rust/Dockerfile` plus a root
`render.yaml`, so a test instance can run on Render (`wss://wons-room-server.onrender.com`,
health check `/health`) before any VM exists. Godot's `ROOM_URL` const selects it. This is
deliberately a separate service from `worldofnads.onrender.com`: the Node control plane stays
untouched and rollback is flipping one constant.

- **Edge:** Caddy or nginx terminating TLS, proxying `wss` to room shards (sticky by
  `roomId`), and `/api/*`,`/events`,`/admin` to Node.
- **Rooms:** `room-server` binary run under Docker (or systemd) on the VM. One process per
  vCPU; many rooms per process. Config: `LISTEN_ADDR`, `AOI_*`, `TICK_HZ`,
  `SESSION_SECRET`, `NODE_INTERNAL_URL`, `NODE_INTERNAL_SECRET`.
- **Observability:** per-tick duration histogram, per-room player count, bytes/client,
  dropped-send counter, encode time, p50/p99. Expose `/metrics` (Prometheus).
- **Scaling:** add VM/process → matchmaker registers new capacity automatically via
  heartbeat.

---

## 9. Phased plan

**Phase 0 — De-risk in Node (no Rust yet).**
Get integrations off the tick (queue on-chain/Firebase work), add tick/latency/payload
metrics, and extract the global singleton state into a `Room` object. *Exit:* metrics
baseline + a room abstraction that mirrors the Rust `Room` type.

**Phase 1 — Rust spike, single room, protocol parity. — implementation done, in test.**
`room-server` (`backend-rust/`) speaks identical msgpack for one room: same `type`s and
field names, AOI grid replication, distance-banded rates, movement validation, item holds,
storm, reward ticks, round lifecycle. Verified by `cargo test` (4 tests: frame shape,
movement clamp, item authority), `scripts/smoke.sh` (live connect → `connect` +
`state_full` decoded), and a field-by-field diff against `backend/index.js` — including
the traps: Node ignores `update_xp` and `throw_x/y/z` too, so Rust ignoring them is
parity, not drift. Deployed for testing via Docker + Render (`render.yaml`), selected in
the client by `ROOM_URL`. *Remaining exit item:* drive it with `backend/bot.js` +
`backend/zig-zag-bot.js` and diff state vs Node for the same inputs.

**Phase 2 — Matchmaker + sharding. — match → room routing done; automated matchmaker TBD.**
The room server now serves **N rooms per process**: `AppState` holds a map of
`Arc<RoomHandle>` (each with its own simulation, clients, `/events` subscribers and tick
task). A client selects its shard with the `room` query param (sanitized, defaults to
`default`; `match` is accepted as an alias) ; rooms are created lazily, capped at 64, and
empty non-default rooms are retired after 2 minutes idle. Per-room tick tasks mean one
room cannot stall another, and a round reset closes only that room's clients.

**Special matches already get their own room, with no matchmaker required.** The Godot
client derives the room from the match it is playing — the `?match=<id>` query that the
web dashboard puts on the frame URL (`/play?match=...`), or the lobby hand-off
(`selected_match_id`) on native — and appends `room=<id>` to the game socket. The events
feed (`Events.gd`) subscribes to the same room, so chat/join toasts are per-match. A
sponsor match created in `SpounsorDashbaord.jsx` (`buildMatchId`) therefore lands every
participant in `room=match-<slug>-<ts>` automatically. With no match selected the client
joins `default`, unchanged. Per-room config (match `minPlayersToStart`/`maxPlayers`) is
**not** wired yet — the client does not carry those values, and Node has no creation-time
hook; that needs a config channel. Still to do: an automated matchmaker that hands out
room ids + a room registration/heartbeat endpoint. *Exit:* two rooms run concurrently on
one VM, players never cross rooms, per-room reset.

**Phase 3 — Production cutover & settlement path.**
Room → Node result POST → Firebase + on-chain settlement. Deploy rooms on the VM;
Node/Render keeps API. *Exit:* a full match settles on-chain via the new path.

**Phase 4 — Harden & scale.**
Soak test, reconnect storms, autoscale rooms, dashboards, alerts.

---

## 10. Testing & tooling

Already wired up for the spike:

- `cargo test` (via WSL) — protocol frame shape, movement clamping, item authority.
- `backend-rust/scripts/smoke.sh` — boots the server, connects `examples/smoke.rs`,
  prints decoded frames; used to validate local, Docker, and (pending) Render runs.
- `docker build -t wons-room-server backend-rust` — same binary that Render builds.

You already have the two best assets for this:

- `backend/bot.js`, `backend/zig-zag-bot.js` — **parity agents** (same inputs → diff
  Node vs Rust state) and **load generators** (N bots → measure tick p99, RAM, CPU).
- Add a **golden-protocol test**: record server frames from Node for a scripted bot
  session; replay through Rust; assert byte/field equality.
- **Soak**: 24h with churn (connect/disconnect/storm/rounds) to catch leaks and drift.

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Protocol drift breaks the Godot client | Golden-protocol test; byte-compat gate in CI before cutover |
| Simulation divergence (physics/AOI) | Deterministic parity harness with the existing bots |
| Session/auth mismatch | Shared secret + identical token claims; keep Node as issuer |
| Two systems during transition | Matchmaker flips traffic per room; Node remains fallback |
| VM ops burden | Docker + Caddy; systemd unit; documented runbook |
| On-chain blocking the tick | Rust never calls chain directly — only async POST to Node |

---

## 12. Environment notes

- `rustc`/`cargo`/`docker` are **only in WSL** on this machine (Ubuntu). Rust builds/tests
  must run via WSL; the Windows shell has Node but no Rust toolchain.
- `AGENTS.md` currently states the backend is Rust — **it is not**; `backend/` is Node.js.
  This should be corrected so planning isn't done against a false premise.

---

## 13. Open questions

1. Room target size (players/room) and desired total concurrency target (defines VM sizing)?
2. Should **skins/attachment resolution** move to Rust or stay in Node and be passed in?
3. Identity of the session token: keep the current HMAC format or move to JWT/JWKS?
4. Single VM initially, or multi-region from the start?
5. Keep the `/events` feed in Node (proposed) — confirm.
