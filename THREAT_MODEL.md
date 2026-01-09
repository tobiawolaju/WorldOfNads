# World of Nads — Threat Model

This document outlines the key security and trust considerations for World of Nads (WONs).

---

## 1. Trust Boundaries

| Component        | Trust Level | Threats / Considerations |
|-----------------|------------|-------------------------|
| Frontend (React + Godot WASM) | Untrusted | Malicious client may attempt to cheat, manipulate input, or spoof results. |
| Backend (Node.js WebSocket server) | Semi-trusted | Could manipulate match state, inject fake results, or drop players. |
| Smart Contract (Monad) | Trust-minimized | Acts as financial authority; cannot be manipulated without private key compromise. |
| Blockchain / Monad | Trusted | Final arbiter of rewards and settlement. Immutable once finalized. |
| Privy Wallets | Trusted | Handles key management; compromise could allow fund theft. |

---

## 2. Key Threat Vectors

### 2.1 Client-Side Cheating
- Input spoofing (speed hacks, collision bypass)
- Botting / auto-farming
- Exploit: player may try to send fake match results

**Mitigation**
- Backend authoritative for physics & collisions
- Server verifies all critical actions
- Match results validated before settlement on-chain

### 2.2 Backend Misbehavior
- Injecting false winners
- Dropping or stalling matches
- Tampering with cosmetic / off-chain state

**Mitigation**
- Backend cannot alter on-chain rewards
- Anyone can submit match results
- All events are logged and auditable

### 2.3 Network / DoS
- DDoS on WebSocket servers
- Latency spikes leading to unfair gameplay

**Mitigation**
- Region-based servers
- Short match durations
- Match state synchronized off-chain with replay logging

### 2.4 Blockchain Risks
- Smart contract bugs
- Chain rollback / reorg

**Mitigation**
- Simple settlement contract
- Minimal on-chain logic
- Event-driven off-chain indexing ensures consistency

### 2.5 Wallet / Key Compromise
- Privy user wallets stolen
- Users lose ability to claim rewards

**Mitigation**
- Embedded, non-custodial wallets
- Recovery flow via Privy’s infrastructure
- Users only exposed when claiming funds

---

## 3. Summary

World of Nads separates **gameplay trust** from **financial trust**:

- Backend can cheat on gameplay but **cannot steal funds**
- Users cannot manipulate settlement without owning keys
- Chain is the final arbiter of rewards

The system assumes:  
- Honest majority of clients  
- Backend remains available but untrusted  

