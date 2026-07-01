# WONs Contract Architecture

## Overview

| Contract | Status | Purpose |
|----------|--------|---------|
| WONsMatchEngine | To deploy | Accepts sponsor deposits, splits 80/20 (winner/lootbox), settles matches on-chain |
| WONsLootBox | To deploy | Holds 20% pool per match, streams MON to nearby players, destroys value on steal, pays final holder |
| WONsSkins | To deploy | ERC1155 skin factory: create → mint (pay MON + XP gate) → burn (2 commons → 1 random rare) |
| WONsXP | To deploy | Soulbound ERC20 XP token, only the game server can mint, non-transferable |
| WONsBridge | To deploy | Testnet/mainnet bridge: deposit real MON → testnet MON, withdrawable anytime |
| WONsRegistry | WONs2 | Decentralized relay registry + frontend IPFS hash for unstoppable game |

## Contract Dependencies

```
WONsMatchEngine ──calls──> WONsLootBox.fundPool / settle / drainPool
WONsSkins       ──reads──> WONsXP.balanceOf (level gate on mint)
Game Server     ──calls──> WONsMatchEngine.settleMatch
Game Server     ──calls──> WONsXP.mintXP (per-second reward commits)
Game Server     ──calls──> WONsLootBox.batchStream / steal
```

## Reward Architecture (Server-Authoritative)

| Source | Reward | Token | Mechanism |
|--------|--------|-------|-----------|
| Chicken holder (per sec) | XP | WONsXP (soulbound) | Server tracks hold time, mints XP on-chain every ~5s |
| Lootbox proximity (per sec) | MON | Native MON | Server tracks proximity, streams from lootbox pool |
| Lootbox steal | Value loss | Native MON | Contract deducts 0.001 MON from pool per steal |
| Prize pool (winner) | MON lump sum | Native MON | MatchEngine pays 80% to winner on settle |
| Lootbox (final holder) | MON remaining | Native MON | MatchEngine triggers LootBox.settle to pay final holder |

## Match Lifecycle

1. **Sponsor** calls `WONsMatchEngine.createSponsoredMatch(totalPrize: X MON)`
   - 80% of X stays in MatchEngine → winner prize
   - 20% of X sent to `WONsLootBox.fundPool()` → lootbox pool
2. **Game server** runs match (3 min), tracks rewards server-side
3. Every ~5 seconds (optional): server commits XP via `WONsXP.mintXP()` and MON via `WONsLootBox.batchStream()`
4. **Match end**: server calls `WONsMatchEngine.settleMatch(winner, participants, lootBoxFinalHolder)`
   - MatchEngine pays winner 80%
   - MatchEngine calls `WONsLootBox.settle(finalHolder)` → pays remaining pool
   - Winner NFT + participation NFTs minted
5. **Cancel**: sponsor calls `cancelSponsoredMatch()` before start → full refund including lootbox pool

## XP Level Gating (Skins)

```
requiredXP = level * level * 100  (Level 1=0, Level 2=400, Level 5=2500, Level 10=10000)

WONsSkins.mintSkin() checks:
  1. msg.value >= skin.mintPrice      (pay in MON)
  2. WONsXP.balanceOf(msg.sender) >= skin.requiredXP  (level gate)
  3. skin.minted < skin.maxSupply     (supply cap)

Burn: 2 Common skins → owner calls mintRareFromBurn() → 1 random Rare skin
```

## Deployed Addresses (Monad Testnet — chainId 10143)

MatchEngine: `0x5EA4AAfa6d8da9F9C0556C0A99F79c39F1Ae7D6b` (old escrow — replace after deploy)
LootBox:      TBD
Skins:        TBD
XP Token:     TBD
Bridge:       TBD
Registry:     TBD

## Environment Variables

### Backend (.env)
```
MN_RPC_URL=https://testnet-rpc.monad.xyz
TRUSTED_AUTHORITY_PRIVATE_KEY=0x...
MATCH_ENGINE_ADDRESS=0x...
XP_TOKEN_ADDRESS=0x...
LOOTBOX_ADDRESS=0x...
SKINS_ADDRESS=0x...
```

### Frontend (.env)
```
VITE_MATCH_ENGINE_ADDRESS=0x...
VITE_SKINS_CONTRACT_ADDRESS=0x...
VITE_XP_TOKEN_ADDRESS=0x...
```
