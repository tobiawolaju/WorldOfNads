# Project instructions

## Never install dependencies locally

Dependency installation is handled by CI when code is pushed (**Vercel** /
**Render**). Do **not** run package-manager install commands in this workspace,
for example:

- `pnpm install` / `pnpm i` / `pnpm add`
- `npm install` / `npm ci` / `npm i` / `npm add`
- `yarn install` / `yarn add`
- `bun install` / `bun add`

These are hard-blocked by `opencode.jsonc` permission rules.

**Why:** `frontend/node_modules` and the pnpm store are multi-GB, and this
machine has very little free disk space. The push itself is what triggers the
install in the deployment environment.

If a command fails because dependencies are missing, do **not** recreate them
locally — assume CI installs them. If you believe local installation is truly
required, stop and ask the user first.

## Project layout

- `frontend/` — Vite app, built with **pnpm** (`frontend/pnpm-lock.yaml`).
- `backend/` — game server (Rust).
- `contracts-monad/`, `contracts-solana/` — smart contracts.
- `godot/` — game client.
- Deployment config lives in `vercel.json`.
