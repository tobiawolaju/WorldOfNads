# World of Nads — Scaling Considerations

World of Nads is designed for real-time, multiplayer matches with on-chain reward settlement. This document outlines scaling strategies and known limitations.

---

## 1. Components & Scaling Limits

| Component | Bottleneck | Current Design | Scaling Notes |
|-----------|-----------|----------------|---------------|
| Frontend (React + Godot WASM) | Browser FPS, network latency | Single-page app with embedded Godot client | Can scale horizontally; each player runs locally |
| WebSocket Backend | Concurrent connections, CPU/Physics | Authoritative server per region | Shard servers by region or match pool; autoscale with Kubernetes or similar |
| Off-Chain Indexer | Event volume | Tracks on-chain events & match results | Horizontal scaling possible; use queues for event processing |
| Smart Contracts | Transaction throughput | Monad Mainnet | Monad’s speed sufficient for match settlement; batch settlements for many matches to reduce gas |
| Wallets (Privy) | Key provisioning | Embedded non-custodial | No scaling concerns; handled by provider |

---

## 2. Matchmaking & Lobby Scaling

- Short, 1–5 minute matches minimize connection overhead.
- Regional shard servers keep latency low.
- Backend can horizontally scale; new match pools spin up automatically.
- Potential congestion if all 20-player lobbies start simultaneously → mitigate with queuing and auto-scaling.

---

## 3. On-Chain Settlement Scaling

- Contracts only handle **finalized match results**, not live gameplay.
- Settlement is **batched** to reduce gas spikes.
- If transaction load increases, implement **queue & relay system** to aggregate multiple match results per block.

---

## 4. Off-Chain Event Indexing

- Backend listens to smart contract events for auditing and rewards.
- Event streams can grow with user base → horizontal scaling with message queues (Kafka, RabbitMQ).
- Stateless indexers can run in multiple regions.

---

## 5. Latency & Performance Considerations

- WASM client runs at 60FPS; minimal perceived lag.
- Backend authoritative physics ensures fairness, even in high latency.
- Frontend prediction used to hide minor network jitter.

---

## 6. Growth & Future-Proofing

- Matches and regions can scale linearly by spinning up new servers.
- Off-chain state and match results are lightweight; storage scales horizontally.
- Contract logic is minimal → chain congestion unlikely unless mass tournaments launch simultaneously.

---

## 7. Conclusion

World of Nads is **designed to scale gracefully**:

- Real-time gameplay remains off-chain for performance
- Settlement is on-chain but minimal, avoiding gas congestion
- Backend and indexers scale horizontally without affecting fairness

This hybrid design ensures **Web2 feel, Web3 trust** at scale.

