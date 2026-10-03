# World of Nads Authentication

How a native Godot client (Android, iOS, desktop) proves who the player is, and
how that identity reaches the game backend.

## Roles

| Component | Authority |
| --- | --- |
| **Privy** | Identity. Owns authentication, wallets, and the access token that proves a human controls an account. |
| **WON backend** (`backend/`) | Accounts, sessions, device linking. The only thing allowed to say "this is user X". |
| **Godot client** (`godot/`) | Game client. Displays a QR code, polls, and holds a session token. Never decides who the player is. |

Privy authenticates the *person*. The backend authenticates the *client* and maps
it to a WON account. Those are separate problems and are deliberately not merged:
the client never holds a Privy secret, never holds a wallet private key, and
never reimplements Privy's crypto.

## Flow

```
  ┌──────────┐                          ┌──────────────┐            ┌─────────┐
  │  Godot   │                          │ WON backend  │            │  Web    │
  │  client  │                          │              │            │  /auth  │
  └────┬─────┘                          └──────┬───────┘            └────┬────┘
       │                                       │                           │
       │ 1. POST /auth/device/start            │                           │
       │    {platform, device_id}              │                           │
       ├──────────────────────────────────────►│                           │
       │                                       │                           │
       │ 2. 200 {device_login_id, code,        │                           │
       │         secret, auth_url, expires_in} │                           │
       │◄──────────────────────────────────────┤                           │
       │                                       │                           │
       │   display QR + "KJI-FYE"              │                           │
       │                                       │                           │
       │ 3. GET /auth/device/status  (poll)    │                           │
       ├──────────────────────────────────────►│                           │
       │◄──────────────────────────────────────┤  {status: "pending"}      │
       │        ... every poll_interval_ms ... │                           │
       │                                       │                           │
       │                              4. player opens                   │
       │                                 worldofnads.xyz/auth?code=KJI-FYE│
       │                                       │◄──────────────────────────┤
       │                                       │                           │
       │                              5. POST /auth/device/approve       │
       │                                 Authorization: Bearer <Privy AT>│
       │                                 {code}                         │
       │                                       │◄──────────────────────────┤
       │                                       │                           │
       │                                       │  verify Privy token       │
       │                                       │  status pending→approved  │
       │                                       │                           │
       │ 6. GET /auth/device/status            │                           │
       ├──────────────────────────────────────►│                           │
       │◄──────────────────────────────────────┤  {status: "approved"}     │
       │                                       │                           │
       │ 7. POST /auth/device/exchange         │                           │
       │    {device_login_id, secret}          │                           │
       ├──────────────────────────────────────►│  status approved→used     │
       │                                       │  resolve/ensure WON user  │
       │ 8. 200 {access_token, refresh_token,  │                           │
       │         user:{id,username,            │                           │
       │               privy_user_id,          │                           │
       │               wallet_address}}         │                           │
       │◄──────────────────────────────────────┤                           │
       │                                       │                           │
       │ 9. enter game, Authorization: Bearer  │                           │
       │    <access_token> on every request    │                           │
```

Step 5 happens on the web, behind an authenticated Privy session, and requires
an explicit button press. Holding a valid Privy session is **not** sufficient to
approve a device: otherwise walking past an unlocked laptop would silently link
that person's phone.

## Endpoints

All under the backend origin (`WON_WEB_ORIGIN` builds the approval URL; the API
base is configured separately in the client).

### `POST /auth/device/start`

Creates a pending device-linking ticket. Unauthenticated.

Request:

```json
{ "platform": "android", "device_id": "<64 hex>", "device_label": "Android 14" }
```

Response `201`:

```json
{
  "ok": true,
  "device_login_id": "dl_0123456789abcdef0123456789abcdef",
  "code": "KJI-FYE",
  "code_display": "KJI-FYE",
  "auth_url": "https://worldofnads.xyz/auth?code=KJI-FYE",
  "secret": "<64 hex>",
  "expires_in": 120,
  "expires_at": "2026-01-01T00:02:00.000Z",
  "poll_interval_ms": 1500
}
```

`secret` is the high-entropy half of the credential and is required at exchange.
It is returned **once**, here, and never displayed. `code` is only a handle for
the human to type; `secret` is what actually authorises the exchange.

Rate limited per IP and per device.

### `GET /auth/device/status?device_login_id=...`

One poll. Unauthenticated.

```json
{
  "ok": true,
  "status": "pending",
  "expires_at": "2026-01-01T00:02:00.000Z",
  "expires_in_seconds": 118,
  "poll_interval_ms": 1500
}
```

`status` is one of `pending`, `approved`, `used`, `expired`, `cancelled`.
`poll_interval_ms` is `0` once the ticket is terminal. The response deliberately
does not say *who* approved it.

### `GET /auth/device/lookup?code=KJI-FYE`

Web side. Resolves a typed code to a ticket summary so `/auth` can show what is
being approved. Unauthenticated but rate limited, because it must not be usable
to enumerate live codes.

Response `200`:

```json
{
  "ok": true,
  "device_login_id": "dl_...",
  "code_display": "KJI-FYE",
  "platform": "android",
  "device_label": "Android 14",
  "status": "pending",
  "expires_at": "2026-01-01T00:02:00.000Z",
  "expires_in_seconds": 118,
  "bound": false
}
```

No user information is returned: lookup happens before sign-in.

### `POST /auth/device/approve`

Web side. **Requires `Authorization: Bearer <Privy access token>`.**

```json
{ "device_login_id": "dl_..." }
```

`{ "code": "KJI-FYE" }` is also accepted; the web page uses the id from lookup.

The backend verifies the Privy token with Privy's official SDK, resolves or
creates the WON account for that Privy DID, and flips the ticket to `approved`.
The body carries no identity — only which ticket to bind. An already-bound
ticket is rejected with `device_login_already_bound` rather than re-pointed.

```json
{ "ok": true, "device_login_id": "dl_...", "user": { "id": "won_...", "username": "nads_abc123" } }
```

### `POST /auth/device/cancel`

Client side. Invalidates an abandoned ticket so a code left on screen cannot be
approved later. Unauthenticated, but requires `secret` — a code alone is not
enough to cancel.

```json
{ "device_login_id": "dl_...", "secret": "<64 hex>" }
```

### `POST /auth/device/exchange`

Trades an approved ticket for a WON session. This is the only step that mints
credentials, and it requires `secret`.

```json
{ "device_login_id": "dl_...", "secret": "<64 hex>", "platform": "android", "device_id": "<64 hex>" }
```

Response `200`:

```json
{
  "ok": true,
  "access_token": "<opaque>",
  "refresh_token": "<opaque>",
  "token_type": "Bearer",
  "token_expires_in": 3600,
  "expires_in": 3600,
  "user": {
    "id": "won_...",
    "username": "nads_abc123",
    "privy_user_id": "did:privy:...",
    "wallet_address": "0x..."
  }
}
```

The session id is intentionally not exposed; the client only ever holds tokens and
never addresses a session by id.

Errors:

| Status | `error` | Meaning |
| --- | --- | --- |
| `400` | `device_login_credentials_required` | Malformed id or missing/too-short secret |
| `404` | `device_login_not_found` | Unknown or already-burned ticket |
| `403` | `invalid_device_secret` | Wrong secret for a real ticket |
| `409` | `device_login_pending` / `_expired` / `_used` / `_cancelled` | Ticket not in an exchangeable state |
| `403` | `device_mismatch` | `device_id` differs from the one recorded at issue |
| `429` | `too_many_requests` | Too many exchange attempts; see `retry_after` |

### `POST /auth/refresh`

Rotates the token pair. The old refresh token dies immediately, so a leaked one
is usable at most once and the theft is detectable.

```json
{ "refresh_token": "<opaque>", "device_id": "<64 hex>" }
```

Returns the same shape as exchange, with a new access token and a new refresh
token. Presenting a refresh token from a different `device_id` than the one
recorded at issue is rejected (`403`) and revokes the session.

### `POST /auth/logout`

```json
{ "refresh_token": "<opaque>" }
```

Revokes server-side. Best-effort from the client: tokens are cleared locally
regardless, and an unrevoked session expires on its own TTL.

### `GET /auth/me`

Validates the current access token and returns authoritative identity.

`Authorization: Bearer <WON access token>`

```json
{
  "ok": true,
  "user": { "id": "won_...", "username": "...", "privy_user_id": "...", "wallet_address": "0x..." },
  "expires_in": 3540
}
```

This is what makes persistent login trustworthy: the client cannot assert its own
identity, it can only ask.

## Identity model

Three identifiers, deliberately not interchangeable:

| Field | Meaning | Stable? | Usable as DB key? |
| --- | --- | --- | --- |
| `user_id` | Immutable WON account id | Yes | **Yes** — this is the identity |
| `privy_user_id` | Privy DID | Yes | No — it is the auth provider's id |
| `wallet_address` | Blockchain address | No, can change | **No** |

The existing player model is unchanged: `users/{username}` stays keyed by the
same username the frontend already derives, so web and native land on one
account. `wonUserId` is added to that record as an immutable field, and
`won_user_index/{privy_did}` maps a Privy DID to its username. A player who signs
in on the website and then links the app gets the same account, not a second one.

The wallet address is stored for display and for settlement. It is never an
identity: a player can link a different wallet later and must keep their account.

## Database records

Firebase RTDB, alongside the existing `users/` tree. No new database.

```
device_logins/{device_login_id}          # dl_<32 hex>
  device_login_id      string
  code_hash            string   HMAC-SHA256(code, WON_AUTH_SECRET)
  secret_hash          string   SHA-256(secret), unpeppered
  status               string   pending|approved|used|expired|cancelled
  platform             string   android|ios|desktop|web
  device_id            string
  device_label         string
  request_ip_hash      string|null   HMAC of the caller IP (abuse signal only)
  user_id              string|null
  privy_user_id        string|null
  username             string|null
  wallet_address       string|null
  created_at           number   epoch ms
  expires_at           number   epoch ms
  approved_at          number|null
  used_at              number|null
  updated_at           number   epoch ms, set on each status change

device_login_codes/{code_hash} -> device_login_id      # index, for O(1) lookup by code

native_sessions/{session_id}                # ns_<32 hex>
  session_id          string
  user_id             string
  username            string
  privy_user_id       string
  device_login_id     string|null
  platform            string
  device_id           string
  access_token_hash   string   SHA-256(access token)
  access_expires_at   number
  refresh_token_hash  string   SHA-256(refresh token)
  refresh_expires_at  number
  created_at          number
  last_used_at        number
  revoked_at          number|null
  user                object   denormalised {id, username, privy_user_id, wallet_address}

native_access_index/{access_token_hash}  -> session_id
native_refresh_index/{refresh_token_hash} -> session_id

won_user_index/{privy_did}                    # Privy DID -> existing users/ key
  user_id             string
  privy_user_id       string
  username            string   key into users/{username}
  wallet_address      string
  created_at          string   ISO timestamp
  last_login_at       string   ISO timestamp
```

Codes are stored as HMAC digests rather than plaintext. A database read therefore
does not hand an attacker a set of live codes to type into `/auth`. Codes are
also short-lived, so even a plaintext read would have a narrow window.

Access and refresh tokens are stored as SHA-256 digests. They are opaque random
strings, not signed claims, so there is no signing key to leak: compromising the
database yields digests that cannot be replayed, because the backend hashes the
incoming token before comparing.

## State transitions

Device login:

```
                 ┌──────────┐
   start ───────►│ pending  │
                 └────┬─────┘
        approve       │       expire (TTL)      cancel
        (web)        │            │              │
                      ▼            ▼              ▼
                 ┌──────────┐ ┌─────────┐  ┌───────────┐
                 │ approved │ │ expired │  │ cancelled │
                 └────┬─────┘ └─────────┘  └───────────┘
                      │ exchange
                      ▼
                 ┌──────────┐
                 │   used   │   terminal, single-use
                 └──────────┘
```

`pending → approved` requires a verified Privy token. `pending → expired` is
derived from `expires_at` and is computed on read, so a ticket cannot be revived
by editing its record. `approved → used` happens exactly once inside the exchange
handler; a second exchange with the same `secret` returns `409`.

Session:

```
   exchange ──► active ──refresh──► active (rotated, old RT dead)
                  │
                  ├── logout ─────► revoked
                  ├── refresh fails ─► revoked
                  └── access TTL ─► access 401 → refresh → replay
```

`AuthAPI` implements the 401 path: on a 401 it refreshes **once**, replays the
original request **once**, and if that still fails it clears the session and
raises `session_expired`. There is no unbounded retry, and the per-call retry
budget is reset for every new request.

## Security assumptions

What the design relies on, and what it does not:

- **The backend is authoritative.** Nothing the Godot client reports about a
  wallet, score, reward, or user id is trusted. Identity comes from a Privy token
  verified server-side with `privy.utils().auth().verifyAccessToken`. The client
  is an untrusted input surface.
- **Privy verification fails closed.** If `PRIVY_APP_ID`/`PRIVY_APP_SECRET` are
  missing, approval returns an error rather than allowing an unverified identity
  through.
- **The short code is a ticket, never a credential.** It authorises nothing on
  its own: exchange additionally requires `secret`, which never leaves the
  client. The code expires in 120 seconds and is single-use.
- **Approval is explicit.** A valid Privy session on the web page does not
  auto-approve. A human presses the button.
- **Tokens are opaque and rotated.** No signing key exists to be leaked. Refresh
  rotates, so a stolen refresh token works at most once and the legitimate
  client's next refresh fails loudly.
- **Device binding is a theft speed bump, not a guarantee.** `device_id` is a
  random per-install value, not hardware-attested. It detects a refresh token
  replayed from a different machine; it is not a second factor.
- **Transport security is assumed.** Tokens are bearer credentials, so all of
  this requires HTTPS end to end. The client must not be pointed at a plaintext
  backend.
- **Rate limiting is per-IP and in-memory.** Sufficient to blunt code guessing;
  not sufficient against a distributed attacker. It resets on backend restart.
- **Client-side token storage is best effort on desktop.** Mobile exports should
  wire `WONCredentialStore.configure()` to the platform keystore. The desktop
  fallback writes to `user://`, which is per-user but not encrypted.

## Client implementation

```
godot/auth/AuthManager.gd      autoload; owns the session and the signals
godot/auth/AuthAPI.gd          all HTTP; bearer, 401 -> refresh -> replay once
godot/auth/AuthState.gd        session value object
godot/auth/DeviceLogin.gd      one linking attempt: start, poll, exchange
godot/auth/CredentialStore.gd  token persistence; keystore seam for mobile
godot/auth/QRProvider.gd       QR interface
godot/auth/QRGenerator.gd      built-in encoder, no addon required
godot/scripts/screens/Login.gd presentation for the login screen
godot/scenes/login.tscn        the login screen
```

AuthManager signals: `login_started`, `login_completed(state)`,
`login_failed(error)`, `session_refreshed(state)`, `logged_out(reason)`,
`login_required(reason)`, `restore_finished(authenticated)`, `state_changed`.

Public API: `is_authenticated()`, `get_user_id()`, `get_username()`,
`get_wallet_address()`, `get_privy_user_id()`, `get_profile()`,
`get_access_token()`, `get_session()`, `get_device_id()`, `request(...)`,
`begin_device_login()`, `cancel_device_login()`, `restart_device_login()`,
`refresh_session()`, `logout(reason)`, `await_restore()`.

Gameplay code should call `AuthManager.request(...)` rather than building its own
`Authorization` header, so token refresh stays in one place.

### Persistent login

On boot `AuthManager` validates any stored session: refresh if the access token
has expired, then confirm with `GET /auth/me`. Only a backend-confirmed session
counts. `home.tscn` awaits `AuthManager.await_restore()` and shows `login.tscn`
when there is no usable session, so the QR screen appears on first launch and
not on later launches.

A network failure during restore is deliberately *not* treated as "signed out" —
that would force a re-scan because of a blip. Only an explicit `401`/`403` from
the backend drops the session.

The web export keeps its existing username-token handshake and is skipped by the
gate, so this flow is additive rather than a replacement.

### Not yet wired: the gameplay WebSocket

The current session is a WON *HTTP* credential. The game WebSocket
(`PlayerManager.gd`) still authenticates with the legacy
`username=<session-token>:<name>` handshake, whose token is minted by
`POST /auth/request-token` and verified by `verifySessionToken`. A WON access
token is not that token, so passing it through `username=` would be rejected.

Linking the two is deliberately left out of this change, because it means
teaching the WebSocket to accept and verify a WON access token (look it up in
`native_access_index`, check `access_expires_at` and `revoked_at`) and is a
larger security surface than the login screen itself. Until then, a native
player who signs in has an authenticated HTTP session but joins the game as an
anonymous `player-<id>` unless they also enter through the web handshake.

The join path to add later is in `PlayerManager._build_ws_url_with_username`:
prefer `AuthManager.get_access_token()` over the URL `username` param on native,
and extend the server's `gameWss.on('connection')` parser to verify a native
token before falling back to `verifySessionToken`.

### Not yet wired: mid-game session loss

If a session is revoked while the player is already in a match, `AuthManager`
drops it and emits `logged_out` / `login_required`, and the next authenticated
HTTP call fails cleanly. Nothing currently navigates back to `login.tscn` from an
arbitrary gameplay scene — only the boot gate in `home.tscn` does that. Closing
this means a single global listener (e.g. in the `Game` autoload) that reacts to
`AuthManager.login_required` and routes to the login scene, with a guard against
re-entering it when the login scene is already current.

### QR generation

`WONQRProvider` is a small interface (`generate`, `is_available`, `provider_name`),
so the built-in encoder can be replaced by an addon or native plugin without
touching the auth logic.

`WONQRGenerator` is dependency-free: byte mode, error-correction level M
preferring L only when needed, Reed-Solomon over GF(256), all eight data masks
with penalty scoring, versions 1-10. It is verified against
`godot/auth/verify-qr.mjs` (`node godot/auth/verify-qr.mjs`), which checks the
format and version tables against ISO/IEC 18004 and round-trips **every** payload
length from 1 to 271 bytes through an independent decoder with Reed-Solomon
syndrome validation. Payloads beyond the v10-L ceiling are reported as
unavailable rather than truncated — the short code on screen remains a working
fallback.

## Environment variables

Backend:

| Variable | Purpose | Default |
| --- | --- | --- |
| `WON_AUTH_SECRET` | HMAC pepper for device-login code digests and request-IP hashes. **Required in production.** Falls back to `AUTH_TOKEN_SECRET`, then to a throwaway per-process value. | — |
| `WON_WEB_ORIGIN` | Origin serving `/auth`; used to build the QR URL | `https://worldofnads.xyz` |
| `DEVICE_LOGIN_TTL_SECONDS` | Ticket lifetime (clamped 30-900) | `120` |
| `NATIVE_ACCESS_TOKEN_TTL_SECONDS` | Access token lifetime (clamped 300-86400) | `3600` |
| `NATIVE_REFRESH_TOKEN_TTL_SECONDS` | Refresh token lifetime (clamped 1h-1y) | `2592000` (30d) |
| `DEVICE_LOGIN_START_LIMIT` | `/auth/device/start` per IP per window | `5` |
| `DEVICE_LOGIN_START_WINDOW_MS` | `/auth/device/start` window | `60000` |
| `DEVICE_LOGIN_APPROVE_LIMIT` | `/auth/device/approve` per Privy user per window | `10` |
| `DEVICE_LOGIN_EXCHANGE_LIMIT` | `/auth/device/exchange` per IP per window | `20` |
| `PRIVY_APP_ID` | Privy application | — |
| `PRIVY_APP_SECRET` | Privy server secret; never leaves the backend | — |
| `PRIVY_JWT_VERIFICATION_KEY` | Optional: skip a Privy API round-trip per token verification | — |

Client:

| Setting | Purpose |
| --- | --- |
| `won/backend/base_url` (project setting) | Backend base URL; editor-only override for local development |

`WON_AUTH_SECRET` is shared between the backend and nothing else. Rotating it
invalidates every outstanding device-login code (their hashes no longer match).
Native sessions are keyed by unpeppered SHA-256 token digests, so they survive a
rotation; use `POST /auth/logout`, or revoke rows in `native_sessions`, to kill
those.

## Testing

```bash
# Backend: 14 checks over the full device login lifecycle.
# Requires WON_AUTH_SECRET (and Firebase creds, inherited from the environment).
WON_AUTH_SECRET=$(openssl rand -hex 32) node backend/scripts/test-device-auth.mjs

# QR encoder: table conformance plus exhaustive round-trip.
node godot/auth/verify-qr.mjs
```
