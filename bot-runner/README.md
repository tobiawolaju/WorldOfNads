# WONS Bot Runner

A lightweight HTTP-triggered bot swarm that runs WebSocket bots against the World of Nads room server. Deploy it on Render as a Web Service and control the number/room from any device (phone, laptop) with a single tap/link.

## Setup guide (Render)

### Option 1: Deploy from this repo as a separate Web Service (fastest)

1. Go to [render.com](https://render.com/) → **New +** → **Web Service** → **Connect a repository** → select `WorldOfNads`.
2. Set **Root Directory** to `bot-runner`.
3. **Runtime**: Node.
4. **Build Command**: `npm install`.
5. **Start Command**: `node bot.js`.
6. **Plan**: Free (or Starter if you hit cold-start timeouts).
7. Click **Create Web Service**.

Render will build and deploy. Once healthy, you'll get a URL like `https://wons-bot-runner-xxxxx.onrender.com`.

### Option 2: Use the Blueprint (`render.yaml`) in this repo

If you use Render Blueprints, the root `render.yaml` defines both:

- `wons-room-server` (Rust Docker, `backend-rust/`)
- `wons-bot-runner` (Node, `bot-runner/`)

Syncing the Blueprint will create both services in one go. Ensure the `BOT_SERVER_URL` on the bot runner points at your `wons-room-server` instance (default is `wss://wons-room-server.onrender.com`).

## Usage

Open these links from your phone/browser. Replace `<your-bot-runner>` with your Render URL and `<matchId>` with the match you want to test.

### Start bots
```text
https://<your-bot-runner>.onrender.com/?matchId=<matchId>&botCount=20
```

Examples:
```text
https://<your-bot-runner>.onrender.com/?matchId=default&botCount=10
https://<your-bot-runner>.onrender.com/?matchId=my-match-123&botCount=25
```

### Stop bots
```text
https://<your-bot-runner>.onrender.com/?botCount=0&stop=1
```
Or simply:
```text
https://<your-bot-runner>.onrender.com/?botCount=0
```

### Check status
```text
https://<your-bot-runner>.onrender.com/status
```
Returns JSON: `connected`, `holding`, `totals` (pickups/steals/uses/frames), per-bot positions, last closes, server/room.

### Target a different server (optional)
```text
https://<your-bot-runner>.onrender.com/?matchId=default&botCount=15&server=wss://worldofnads.onrender.com
```
Defaults to `wss://wons-room-server.onrender.com` (the Rust room server). Point to the legacy Node server if you need to test it.

### Tune behavior (optional)
```text
https://<your-bot-runner>.onrender.com/?matchId=default&botCount=12&speed=5.5&skin=Hellion&prefix=test
```
- `speed` — base move speed (default `5.0`, clamped under server max 12)
- `skin` — one of `defaultnad`, `buggy`, `Aurum`, `Abbss`, `Hellion`, `Seraphim`, `mouch`, `john deo`
- `prefix` — username prefix (e.g. `load` → `load1`, `load2`, ...)

## What the bots do

- Move toward the highest-priority target with flock separation (don't clump).
- **LootBox first** — they prioritize the unheld LootBox ("check in"). If it's held, they try to **steal** it.
- **Power-ups** — grab unheld power-ups (`p1–p5`) and `use_request` them after a short delay.
- **Chicken** — will chase/steal it when higher priority targets aren't available.
- **Run while carrying** — if carrying Chicken or LootBox, they flee from the nearest chaser to spread out and exercise the chase/steal loop.
- **Auto-reconnect** — if disconnected, they retry every ~1.2s.
- **MessagePack** — uses the exact wire format (`update_state`, `pickup_request`, `use_request`, `drop_request`) the Godot client uses.

## Environment variables (Render)

Set these in the bot-runner service's **Environment** tab if you want to change defaults.

| Var | Default | Notes |
|---|---|---|
| `PORT` | `3000` | Render sets this; don't change. |
| `BOT_SERVER_URL` | `wss://wons-room-server.onrender.com` | Target room server (WS). |
| `BOT_COUNT` | `10` | Fallback when query omits `botCount`. |
| `BOT_MAX_COUNT` | `300` | Safety cap so you can't accidentally spawn thousands. |
| `BOT_TICK_MS` | `33` | Tick interval (ms). |
| `BOT_MOVE_SPEED` | `5.0` | Base speed. |
| `BOT_PICKUP_RADIUS` | `2.5` | Distance to grab unheld item. |
| `BOT_STEAL_RADIUS` | `1.8` | Distance to steal held item. |
| `BOT_PERSONAL_SPACE` | `1.1` | Repulsion radius from other bots. |
| `BOT_SEPARATION_WEIGHT` | `1.6` | Repulsion strength. |

## Troubleshooting

- **Cold start (free plan)**: If Render spun down, the first WS connect after wakeup can take 30–60s. Bots auto-reconnect; try the link once more if it looks stuck.
- **`unknown_match` close**: The Rust room server only allows allocated match IDs (from the dashboard/registry). Use `default` or a real match ID.
- **Rate-limited / closes quickly**: Drop `botCount` (60 msg/s per socket). `BOT_PERSONAL_SPACE`/separation help avoid message bursts.
- **Can't connect**: Visit `/health` on the bot runner (should return `ok`). Check `BOT_SERVER_URL` is correct and the target server is healthy (`/health` on the room server).
- **Works with JSON fallback**: The runner also accepts JSON frames, so pointing to the legacy Node backend (`wss://worldofnads.onrender.com`) works too.
