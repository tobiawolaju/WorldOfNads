# WONS Bot Runner

A lightweight HTTP-triggered bot swarm that runs WebSocket bots against the World of Nads room server. Deploy it on Render as a Web Service and control the number/room from a phone in one tap.

## Quick start

Local:
```bash
cd bot-runner
npm ci  # (ws + @msgpack/msgpack already small)
node bot.js
```

Deploy on Render (recommended): create a new Web Service pointing to `bot-runner/` with Build `npm install`, Start `node bot.js`. It will listen on `$PORT`.

## API

- `GET /?matchId=YOUR_MATCH&botCount=25` — start 25 bots joining `YOUR_MATCH`. Bots only spawn when `botCount>0`; passing `0` stops them.
- `GET /?matchId=default&botCount=10` — test the default room.
- `GET /status` — live snapshot of connected bots, who is holding what, recent closes, etc.
- `POST /` — same but with JSON body `{ "matchId": "...", "botCount": 25, "server": "...", "prefix": "bot", "skin": "Hellion", "speed": 5 }`

## What the bots do

- `update_state`: moves towards the highest-priority target, keeps separation from other bots.
- Unheld lootbox → highest priority ("find lootbox and check in").
- Power-ups → `use_request` shortly after grabbing them.
- Carrying an objective (Chicken/LootBox) → flee from the nearest chaser ("run").
- If another player is holding the target, they will `pickup_request` it ("steal").
- Uses MessagePack (`@msgpack/msgpack`) to match the Rust server exactly.

## Environment variables

| Var | Default | Notes |
|---|---|---|
| `PORT` | `3000` | Render sets this automatically. |
| `BOT_SERVER_URL` | `wss://wons-room-server.onrender.com` | Point to your deployed Rust room server (or `ws://localhost:8080`). |
| `BOT_COUNT` | `10` | Default count if query omits it. |
| `BOT_MAX_COUNT` | `300` | Ceiling to avoid accidental overspawning. |
| `BOT_TICK_MS` | `33` | Simulation tick. |
| `BOT_MOVE_SPEED` | `5.0` | Target base speed (clamped well under server max 12). |
| `BOT_PICKUP_RADIUS` | `2.5` | Grab an unheld item. |
| `BOT_STEAL_RADIUS` | `1.8` | Steal a held item. |
| `BOT_PERSONAL_SPACE` | `1.1` | Avoid crowding fellow bots. |
| `BOT_SEPARATION_WEIGHT` | `1.6` | How strongly they repel each other. |

## Matching the room

- Use `matchId` to join a specific allocated room (matches Node's `?match=`). For the Rust server, `room`/`match` are accepted; the HTTP param `matchId` is mapped to that.
- The Rust room server only opens rooms for match IDs that exist in its registry; "default" is always allowed. If you need to test an unallocated ID on a strict setup, point at the legacy Node server instead.

## Troubleshooting

- `SMOKE FAILED` / `closed`: usually a wrong server URL, or the Render Rust room is sleeping (cold start on free plan takes ~30s). Retry once.
- Rate-limited (1023): throttle bot count down slightly; 60 msg/s per socket is the guard.
- Room "unknown_match": the match ID isn't allocated; either create it in the dashboard or use `default`.
- Bots don't spawn: check `/status`; also ensure the server accepts WS upgrades on `/`.
