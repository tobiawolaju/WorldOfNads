# Audit Notes (Pre-Main Audit)

This folder is a lightweight, pre-release audit log meant to show due diligence.
It is not a professional security audit.

## Quick checks performed

- Manual gameplay sanity checks: movement, chicken pickup/drop, scoring flow
- WebSocket state sync at 20Hz stays stable under normal load
- Match settlement flow reaches escrow and attempts payout

## Contract addresses

- Match Escrow (Monad): `0x5EA4AAfa6d8da9F9C0556C0A99F79c39F1Ae7D6b`

## Security considerations (current)

- Server is a trusted authority for winner selection and payout triggers
- Input validation is basic; malformed client state should be hardened
- Reconnect logic is in place, but abuse/throttle limits are not fully enforced

## Recent fixes

- Client stop-match control removed; only the server timer can end rounds (see `SEC-011`).

## Known limitations

- No formal load testing results included yet
- No external audit report
- Some gameplay edge cases (disconnects mid-hold) need more testing

## Next steps / TODO

- Add rate limiting and abuse throttling on the WebSocket server
- Add automated tests for match settlement logic
- Document testnet vs mainnet contract separation clearly
