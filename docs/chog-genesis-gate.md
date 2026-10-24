# Chog Genesis ownership gate

The CHOG reveal/power-up is only available to a player whose authenticated wallet
holds at least one **Chog Genesis** NFT on **Monad mainnet** (chain id `143`), and
only while that player is in a CHOG room.

This is a gate around the *existing* `chog` input. No new button, UI or power-up
system was added.

## Contract verification

Collection: <https://opensea.io/collection/chog-genesis>

Contract: `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763`

Verified directly against `https://rpc.monad.xyz` before implementation:

| Check | Result |
| --- | --- |
| `eth_chainId` | `0x8f` = **143** (Monad mainnet) |
| `eth_getCode` | non-empty contract |
| `name()` | `Chog Genesis` |
| `symbol()` | `CHOG` |
| `totalSupply()` | `1969` |
| `ownerOf(1)` / `balanceOf(owner)` | `0x3d38…e7e0` / `1` |

The backend also verifies `eth_chainId` at runtime and refuses to read a balance
from any other chain. A testnet RPC (`10143`) can therefore never answer this
question.

## Endpoint

`GET /api/nft/chog-genesis/ownership`

Requires `Authorization: Bearer <token>`. Two existing credential types are
accepted:

* **WON session token** (native/desktop device login). The wallet is
  `session.user.wallet_address`, the address Privy linked to the account.
* **Privy access token** (web build). The token is verified with the Privy SDK
  (`verifyPrivyAccessToken`), then the user record is fetched server-side with
  `fetchPrivyUser()`; the wallet is that user's linked Ethereum wallet.

A client-supplied address (query string, body, header) is never used.

Responses:

```json
{ "has_chog_nft": true }
```

```json
{ "has_chog_nft": false }
```

Errors:

| Status | `error` | Meaning |
| --- | --- | --- |
| 401 | `missing_access_token` / `invalid_access_token` | no verified identity |
| 400 | `invalid_wallet_address` | the authenticated account has no valid EVM address |
| 429 | `rate_limited` | per-identity fixed window (20/min) exceeded; `Retry-After` set |
| 503 | `identity_unavailable` / `ownership_unavailable` | Privy/RPC unavailable, timeout, wrong chain, malformed result |

`503` is **not** a negative answer. The client treats every non-200 as `ERROR`
(deny) and retries later.

Cache: per lower-cased wallet, 5 minutes by default. Two wallets can never share
an entry. Failed RPC calls are not cached.

## Client gate (`godot/scripts/player.gd`)

`ChogEligibility` (`godot/scripts/chog_eligibility.gd`) is a deny-by-default
state machine: `UNKNOWN`, `ELIGIBLE`, `INELIGIBLE`, `ERROR`. Only a fresh
`ELIGIBLE` verdict for the current identity **and** `_is_chog_room()` authorises
the `chog` input. `UNKNOWN`, `INELIGIBLE`, `ERROR`, a stale verdict, a changed
account, or a non-CHOG room all ignore the press without activating the
reveal/power-up.

Identity key:

* native: `won:<wallet address>` from `AuthManager`;
* web: `privy:<sha256(Privy access token)>`, because the web client does not
  receive a wallet address.

The web token is written to `sessionStorage["wons_privy_token"]` by
`frontend/src/pages/Play.tsx` during the `/play` → `/play.html` hand-off. It is
never placed in the URL. Direct `/play.html` hits without this hand-off fail
closed (no verdict → input denied).

Checks run:

* once when the local player spawns (deferred, after PlayerManager assigns
  `root`/`is_local`);
* on each `chog` press if a verdict is due;
* every 5 s as a cheap due-check (never one request per frame);
* again on `AuthManager.logged_out` / `login_completed`;
* at most once per TTL or per retry window.

## Server-side authorization

The eligibility verdict is server-authoritative: the client cannot supply the
wallet, the balance, or a boolean. Server-tracked pickups (the ordinary arena
power-ups, chicken and lootbox) remain validated by the Rust room server exactly
as before.

The CHOG reveal's random power-up is a **client-side held power-up** with no
pickup instance and no server request (`_use_held_power_up` with
`held_local_pickup == null`). There is therefore no server "activation request"
to authorise for it, and a modified client can still run local code. Closing
that residual gap would require moving the CHOG grant into the server's item
authority; it is intentionally not part of this change.

## Environment

Add to the Node backend service (`worldofnads` on Render):

| Variable | Required | Default |
| --- | --- | --- |
| `MONAD_MAINNET_RPC_URL` | recommended | `https://rpc.monad.xyz` |
| `CHOG_GENESIS_CONTRACT_ADDRESS` | no | `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763` |
| `CHOG_NFT_CACHE_TTL_MS` | no | `300000` |
| `CHOG_NFT_RPC_TIMEOUT_MS` | no | `8000` |

`MONAD_MAINNET_RPC_URL` **must** point at mainnet (143); the code refuses any
other chain. It is separate from `MN_RPC_URL`, which is the game's testnet
provider. `PRIVY_APP_ID` / `PRIVY_APP_SECRET` (already required by device auth)
are used for the web path.

No new frontend or Godot build variable is required.

## Tests

```bash
node --test backend/chogNft.test.js
node --test backend/chogNft.test.js backend/settlement.test.js backend/analytics.test.js
```

`godot/tools/_test_chog_gate.gd` is a headless selftest:

```bash
godot --headless --path godot --script res://tools/_test_chog_gate.gd
```

Last run on this branch:

* `node --test backend/chogNft.test.js backend/settlement.test.js backend/analytics.test.js` — **62 pass, 0 fail** (16 of them are the Chog gate tests).
* `_test_chog_gate.gd` — **28 checks, all pass**, exit code 0.
* `_test_hidden_extras.gd` — still passes (the reveal visuals are untouched).
* A live read against Monad mainnet returned `true` for the verified holder
  `0x3d38fee3e1a4c43d8fcf715aa6c9ff025074e7e0` and `false` for
  `0x0000000000000000000000000000000000000001`.

The testnet/mainnet isolation test feeds a chain id of `10143` and asserts that
no `eth_call` is ever made.
