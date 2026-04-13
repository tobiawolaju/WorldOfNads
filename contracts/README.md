# WONs Settlement Architecture

This folder now contains the first contract scaffold for the settlement model that matches the current codebase:

- The game remains fully offchain during the match.
- Sponsors lock prize funds onchain before the match starts.
- The backend acts as the trusted match authority.
- The contract releases the first-place prize automatically after backend settlement.
- Non-winning participants receive an onchain participation collectible.

## Why this matches the current repo

The existing implementation already works this way operationally:

- The React app selects a match and sends the player into the Godot game.
- The Godot client connects to the realtime Node WebSocket server.
- The backend determines the winner when the timer ends.

Relevant files:

- `frontend/src/pages/Dashboard.tsx`
- `frontend/src/pages/Play.tsx`
- `godot/scripts/Main.gd`
- `backend/index.js`

That means the cleanest contract design for the next step is not a fully trustless game contract. It is a sponsor escrow contract with backend-authorized settlement.

## Contract added

- `WONSponsorArenaEscrow.sol`

Core behavior:

1. `createSponsoredMatch`
   - Called by sponsor.
   - Transfers prize funds into the contract.
   - Creates a unique `matchId`.
   - Reserves one winner NFT token id and one participation NFT token id.

2. `settleMatch`
   - Called only by the trusted backend authority.
   - Accepts the winner wallet and participant wallet list.
   - Pays the winner from escrow.
   - Mints the winner collectible.
   - Mints participation collectibles to all non-winning participants.
   - Can only run once per `matchId`.

3. `cancelSponsoredMatch`
   - Lets the sponsor recover funds before settlement if a match is cancelled.

## Product flow mapped to your current app

### Frontend

Add a protected `/sponsor` route in the React app.

Recommended sponsor flow:

1. Sponsor chooses:
   - prize token
   - first place prize amount
   - match label / campaign metadata
   - winner NFT metadata URI
   - participation NFT metadata URI

2. Frontend calls `createSponsoredMatch`.

3. After the transaction confirms, frontend sends the match configuration to your backend so the backend can make it available in the match list.

The current hardcoded `matches` array in `frontend/src/pages/Dashboard.tsx` should become backend-driven data.

### Backend

The backend in `backend/index.js` already:

- tracks connected players
- starts and ends rounds
- resolves a winner
- emits match events

To support onchain settlement, extend it with:

1. Match registry
   - map game rounds to onchain `matchId`
   - store sponsor metadata and prize token details

2. Wallet roster capture
   - on join, collect the player's EVM wallet address from the authenticated frontend session
   - maintain `playerId -> walletAddress`

3. Settlement trigger
   - when the round ends and winner is resolved, translate winner `playerId` to `winnerWallet`
   - build the unique participant wallet list
   - call `settleMatch(matchId, winnerWallet, participantWallets)`

4. Settlement status
   - emit a new event such as `match_settlement_submitted`
   - emit success or failure so the frontend can show payout state

### Godot / gameplay

No onchain logic needs to live inside the Godot client.

Keep the Godot client focused on:

- movement
- item state
- round participation
- event display

That is consistent with the current architecture and keeps latency-sensitive gameplay offchain.

## Trust model

This is not fully trustless gameplay.

It is:

- offchain gameplay
- centralized winner resolution by the backend
- onchain escrow and payout settlement

That is acceptable for an MVP and is materially stronger than saying "blockchain is involved" without real escrow or settlement.

Recommended README language:

> WONs uses onchain escrow and backend-authorized settlement. Sponsors fund matches upfront, the realtime game server submits signed results, and the prize is released automatically onchain.

## Important integration gaps still to implement

1. Player wallet binding
   - Your backend currently resolves winners by internal websocket `playerId`, not by wallet.
   - You need a secure mapping from authenticated user session to EVM wallet address.

2. Match identity
   - Your current backend round loop is generic.
   - You need a persistent `matchId` per sponsor-backed round.

3. Server signer
   - The trusted authority should be a dedicated backend wallet, not a deployer wallet.

4. Metadata strategy
   - Decide whether NFT metadata is static per sponsor campaign or per match.

5. Token choice
   - For sponsor prize payouts, use an ERC-20 stable asset on Monad/EVM.
   - Keep participation collectibles cheap; do not over-design them initially.

## Recommended next implementation order

1. Add backend-backed match records instead of hardcoded dashboard matches.
2. Add sponsor creation UI and backend persistence.
3. Bind authenticated players to EVM wallet addresses on match join.
4. Deploy the escrow contract.
5. Add backend settlement transaction logic.
6. Update README copy to describe the actual trust model precisely.
