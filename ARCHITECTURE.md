# Architecture Overview

World of Nads is built as a **hybrid real-time game system** where performance-critical gameplay runs off-chain, while security-critical actions are settled on-chain.

The architecture intentionally separates:
- **Fast, adversarial gameplay**
- **Trust-minimized settlement**
- **Seamless user onboarding**

Blockchain is used as infrastructure, not as a gameplay constraint.

---

## High-Level System Diagram

Client (Browser)
→ Matchmaking / Game Backend
→ Monad (Settlement & Rewards)

---

## Frontend (Client Layer)

**Tech**
- React
- Godot (WebAssembly export)
- Privy Auth + Embedded Wallets

**Responsibilities**
- User authentication (email / social login via Privy)
- Wallet creation (non-custodial, embedded)
- UI, lobby flow, and match lifecycle
- Running the actual game client (Godot WASM)

**Details**
- The core game is built in **Godot** and exported to **WASM**.
- The WASM bundle is embedded inside a React app.
- React handles auth, routing, state, and wallet interactions.
- Godot handles:
  - Player input
  - Rendering
  - Client-side prediction
  - Game feel

Players can enter a match without seeing wallets, seed phrases, or signing popups.

---

## Authentication & Wallets

**Provider:** Privy

- Users log in with email or social accounts.
- Privy automatically provisions an **embedded, non-custodial wallet**.
- Wallets are used only when required (rewards, cosmetics, payouts).
- No wallet setup is required to start playing.

This removes the largest UX friction in Web3 games.

---

## Backend (Game Services)

**Tech**
- Node.js
- WebSocket servers
- Stateless APIs + in-memory match state

**Responsibilities**
- Matchmaking & lobby creation
- Session orchestration
- Real-time communication relay
- Match lifecycle tracking
- Submitting finalized results to chain

**Design Principles**
- Backend is **authoritative for movement & physics**
- Backend is **not authoritative over rewards**
- Backend cannot alter match outcomes once finalized

The backend can be restarted or replaced without corrupting on-chain state.

---

## Game Networking Model

- Clients connect to region-based WebSocket servers
- Server runs authoritative movement / collision
- Short match durations (1–5 minutes)
- No long-lived on-chain game state

This keeps latency low and cheating controllable without on-chain overhead.

---

## Smart Contracts (Settlement Layer)

**Chain:** Monad  
**Role:** Final authority on rewards

**Responsibilities**
- Accept finalized match results
- Distribute rewards to winners
- Emit settlement events for indexing

**Non-Responsibilities**
- No real-time gameplay logic
- No movement, physics, or timing enforcement

Smart contracts act as a **financial and trust boundary**, not a game engine.

---

## Trust Model

| Component | Trust Level |
|--------|-------------|
| Frontend | Untrusted |
| Backend | Semi-trusted (no custody, no payouts) |
| Smart Contracts | Trust-minimized |
| Chain | Final authority |

Even if the backend misbehaves:
- Funds cannot be misdirected
- Rewards remain deterministic
- Past matches remain auditable

---

## Why This Architecture

- On-chain gameplay is too slow and expensive for real-time games
- Fully off-chain games lack trust and ownership
- Hybrid systems capture the benefits of both

World of Nads uses blockchain **only where it improves correctness**, not where it hurts UX.

---

## Design Goal

Ship a game that:
- Feels like Web2
- Settles like Web3
- Scales like a real product
