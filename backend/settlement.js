// Settlement of a finished round: result -> ledger -> chain.
//
// The room server (Rust) owns the simulation and posts the round result here.
// The control plane owns the ledger. This module turns one result into:
//
//   1. the reward rows the dashboard's Rewards tab reads (`rewards/<id>`),
//   2. every player's persistent totals for the leaderboard
//      (`users/<name>.won`, `.wonMon`, `.xp`),
//   3. the match record's result + settlement status (`matches/<id>`),
//   4. an on-chain payout when the round has exactly one prize winner.
//
// The lootbox is settled first: its holders were paid MON while they carried it
// (Whitepaper 5.4), so those rows exist before the pool's remainder is handed to
// the final holder. See `reconcileLootBox`.
//
// The order matters: the ledger is written first, so a chain outage can never
// lose a result. Every write is idempotent per match id, so the room server's
// retries cannot double-credit anyone.
//
// Everything with a side effect is injected. That keeps this file free of
// Firebase / ethers / network imports and lets `node --test` cover the whole
// flow without any of them.

/** WONsMatchEngine charges FEE_BPS = 1000 (10%) at match creation. */
export const FEE_SHARE = 0.1;
/** ...then splits the net 80% to the winner and 20% to the lootbox pool. */
export const PRIZE_WINNER_SHARE = 0.8;
export const PRIZE_LOOTBOX_SHARE = 0.2;

/** Share of the gross prize the deployed contract pays the winner. */
export const WINNER_POOL_SHARE = (1 - FEE_SHARE) * PRIZE_WINNER_SHARE; // 0.72
/** Share of the gross prize the deployed contract puts in the lootbox pool. */
export const LOOTBOX_POOL_SHARE = (1 - FEE_SHARE) * PRIZE_LOOTBOX_SHARE; // 0.18

/** WONsLootBox.GAS_PER_STEAL: what one steal burns out of the box. */
export const LOOTBOX_STEAL_COST_MON = 0.001;
/** WONsLootBox.STREAM_BATCH_LIMIT: the most players one `batchStream` can pay. */
const STREAM_BATCH_LIMIT = 50;

/** Statuses a settled match can end in. */
export const STATUS = Object.freeze({
    SETTLED_ONCHAIN: 'settled_onchain',
    SPLIT_AWAITING_PAYOUT: 'split_awaiting_payout',
    OFFCHAIN_ONLY: 'offchain_only',
    ONCHAIN_FAILED: 'onchain_failed',
    // The escrow could not be read, so the result is in the ledger but the match
    // is not credited: the reporter retries and the chain leg finishes then.
    CHAIN_UNAVAILABLE: 'chain_unavailable',
    NO_PAYOUT: 'no_payout'
});

const MAX_PARTICIPANTS = 64; // WONsMatchEngine.MAX_PARTICIPANTS
const SHARE_TOLERANCE = 0.01;

export function round6(value) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.round(n * 1e6) / 1e6 : 0;
}

/** The gross prize of a match, in MON. Matches store both a number and a label. */
export function parsePrizeMon(match) {
    const direct = Number(match?.prizeAmount);
    if (Number.isFinite(direct) && direct > 0) return direct;

    const text = String(match?.prize ?? '').replace(/[^0-9.]/g, '');
    const parsed = Number(text);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

/**
 * Validates the report the room server posts. Returns an error string or null.
 *
 * A round always has a `reason`, a `split` object and the players. The shares
 * must add up to 1 (within rounding) whenever there are any, because the ledger
 * distributes a fixed pool: a bad share would either create or destroy money.
 */
export function validateReport(report) {
    if (!report || typeof report !== 'object' || Array.isArray(report)) {
        return 'the body must be an object';
    }
    if (report.reason !== 'instant' && report.reason !== 'buzzer') {
        return 'reason must be "instant" or "buzzer"';
    }
    const split = report.split;
    if (!split || typeof split !== 'object' || !Array.isArray(split.shares)) {
        return 'split.shares must be an array';
    }
    for (const share of split.shares) {
        if (!share || typeof share.playerId !== 'string' || !share.playerId) {
            return 'every share needs a playerId';
        }
        if (typeof share.playerName !== 'string' || !share.playerName) {
            return 'every share needs a playerName';
        }
        if (
            typeof share.share !== 'number' ||
            !Number.isFinite(share.share) ||
            share.share < 0 ||
            share.share > 1
        ) {
            return 'every share must be a number between 0 and 1';
        }
    }
    if (split.shares.length > 0) {
        const total = split.shares.reduce((sum, share) => sum + share.share, 0);
        if (Math.abs(total - 1) > SHARE_TOLERANCE) {
            return `the shares must add up to 1, got ${round6(total)}`;
        }
    }
    if (!Array.isArray(report.players)) {
        return 'players must be an array';
    }
    for (const player of report.players) {
        if (!player || typeof player.playerId !== 'string' || !player.playerId) {
            return 'every player needs a playerId';
        }
        if (typeof player.playerName !== 'string' || !player.playerName) {
            return 'every player needs a playerName';
        }
    }
    if (report.winner !== null && report.winner !== undefined) {
        if (typeof report.winner !== 'object' || typeof report.winner.playerId !== 'string' || !report.winner.playerId) {
            return 'the winner needs a playerId';
        }
        if (typeof report.winner.playerName !== 'string' || !report.winner.playerName) {
            return 'the winner needs a playerName';
        }
    }
    if (report.lootboxHolder !== null && report.lootboxHolder !== undefined) {
        if (
            typeof report.lootboxHolder !== 'object' ||
            typeof report.lootboxHolder.playerId !== 'string' ||
            !report.lootboxHolder.playerId
        ) {
            return 'the lootbox holder needs a playerId';
        }
    }
    if (report.lootboxSteals !== undefined) {
        const steals = Number(report.lootboxSteals);
        if (!Number.isFinite(steals) || steals < 0) {
            return 'lootboxSteals must be a non-negative number';
        }
    }
    if (report.endedAt !== undefined && !Number.isFinite(Number(report.endedAt))) {
        return 'endedAt must be a number';
    }
    return null;
}

/**
 * Splits the match's real prize pool into per-player payouts.
 *
 * The pools come from the escrow record when the match exists on-chain; that is
 * the only source that knows what the contract will actually pay. Matches that
 * were never escrowed fall back to the contract's published shares of the gross
 * prize so their ledger still adds up.
 *
 * `box` is the reconciled lootbox (see `reconcileLootBox`): the MON each holder
 * already streamed out of it on-chain, and what is left for the final holder.
 * Without it the whole pool is credited to the holder, which is the off-chain
 * behaviour (no escrow, no stream, nobody to pay early).
 */
export function buildPayouts({ match, report, onchain, box }) {
    const grossMon = parsePrizeMon(match);
    const winnerPoolMon =
        onchain && Number(onchain.winnerPrizeMon) > 0
            ? round6(onchain.winnerPrizeMon)
            : round6(grossMon * WINNER_POOL_SHARE);
    const lootBoxPoolMon =
        onchain && Number(onchain.lootBoxPoolMon) > 0
            ? round6(onchain.lootBoxPoolMon)
            : round6(grossMon * LOOTBOX_POOL_SHARE);

    const payouts = [];
    for (const share of report.split.shares) {
        if (!(share.share > 0)) continue;
        payouts.push({
            kind: 'prize',
            playerId: share.playerId,
            playerName: share.playerName,
            share: round6(share.share),
            amountMon: round6(winnerPoolMon * share.share)
        });
    }

    // Whitepaper 5.4: the box pays while the round runs. These are the amounts
    // the holders earned and were paid on-chain, so they are ledger entries in
    // their own right - not part of the settle payout.
    for (const row of Array.isArray(box?.streamed) ? box.streamed : []) {
        if (!(Number(row.amountMon) > 0)) continue;
        payouts.push({
            kind: 'stream',
            playerId: row.playerId,
            playerName: row.playerName,
            share: 0,
            amountMon: round6(row.amountMon)
        });
    }

    // What is left in the box after the streams and the steal burns is what
    // `settle` pays. The recipient is the final holder, or - matching the
    // escrow's own fallback - the first prize winner when nobody held the box.
    const lootBoxPayoutMon =
        box && box.done ? round6(Number(box.remainingMon) || 0) : lootBoxPoolMon;
    const firstPrize = payouts.find((payout) => payout.kind === 'prize');
    const lootRecipient =
        report.lootboxHolder ||
        (firstPrize ? { playerId: firstPrize.playerId, playerName: firstPrize.playerName } : null);

    if (lootRecipient && lootBoxPayoutMon > 0) {
        payouts.push({
            kind: 'lootbox',
            playerId: lootRecipient.playerId,
            playerName: lootRecipient.playerName,
            share: 1,
            amountMon: lootBoxPayoutMon
        });
    }

    const totalMon = round6(payouts.reduce((sum, payout) => sum + payout.amountMon, 0));
    return {
        grossMon,
        winnerPoolMon,
        lootBoxPoolMon,
        lootBoxPayoutMon,
        payouts,
        totalMon
    };
}

/**
 * Brings the lootbox up to date on-chain before the match settles.
 *
 * The round report says who held the box and for how long (`players[].mon`) and
 * how often it changed hands (`lootboxSteals`). This replays both against
 * `WONsLootBox`: every steal burns `GAS_PER_STEAL`, every holder is paid their
 * stream, and whatever is left is what `settle` will hand the final holder.
 *
 * Progress is persisted in `settlement.box`, so a retried report never pays a
 * stream twice: already-applied steals and already-paid holders are skipped.
 * Returns `{ done: true, ... }` on success and `{ error }` when the chain leg
 * could not finish - the caller then leaves the match uncredited to be retried.
 */
export async function reconcileLootBox({ matchId, report, poolMon, previous, deps, log = () => {} }) {
    const pool = round6(Number(poolMon) || 0);
    if (!(pool > 0)) {
        // No escrow behind the box (never funded, or no prize): nothing to stream.
        return {
            done: true,
            skipped: true,
            poolMon: 0,
            steals: 0,
            appliedSteals: 0,
            burnedMon: 0,
            streamed: [],
            remainingMon: 0,
            txHashes: []
        };
    }
    if (previous && previous.done) return previous;

    let box;
    if (previous && previous.done === false) {
        // Resume where the failed attempt stopped. The error itself is not part of
        // the progress (and `undefined` cannot be written to Firebase).
        const { error: _previousError, ...resumed } = previous;
        box = {
            ...resumed,
            streamed: Array.isArray(previous.streamed)
                ? previous.streamed.map((row) => ({ ...row }))
                : [],
            txHashes: Array.isArray(previous.txHashes) ? [...previous.txHashes] : []
        };
    } else {
        box = {
            done: false,
            poolMon: pool,
            steals: 0,
            appliedSteals: 0,
            burnedMon: 0,
            streamed: [],
            remainingMon: pool,
            txHashes: []
        };
    }

    const save = async () => {
        await deps.updateMatchRecord(matchId, { settlement: { box } });
    };

    // 1. Replay the steals. Each one burns GAS_PER_STEAL, and the box cannot
    //    burn more than it holds.
    const steals = Math.max(0, Math.floor(Number(report?.lootboxSteals) || 0));
    box.steals = steals;
    const affordable = Math.floor(round6(pool / LOOTBOX_STEAL_COST_MON) + 1e-9);
    const target = Math.min(steals, affordable);
    while (box.appliedSteals < target) {
        const result = await deps.stealLootBox({
            matchId,
            holderName: report?.lootboxHolder?.playerName || null
        });
        if (!result || !result.success) {
            return { ...box, error: result?.error || 'the steal could not be replayed on-chain' };
        }
        box.appliedSteals += 1;
        box.burnedMon = round6(box.appliedSteals * LOOTBOX_STEAL_COST_MON);
        if (result.txHash) box.txHashes.push(result.txHash);
        await save();
    }

    // 2. Pay the stream. Amounts are clamped to what the box still holds, in
    //    report order, so the batch can never try to pay out more than the pool.
    const alreadyPaid = new Set(box.streamed.map((row) => String(row.playerName).toLowerCase()));
    const seen = new Set(alreadyPaid);
    let left = round6(Math.max(0, pool - box.burnedMon));
    for (const row of box.streamed) left = round6(left - (Number(row.amountMon) || 0));

    const pending = [];
    for (const player of Array.isArray(report?.players) ? report.players : []) {
        if (box.streamed.length + pending.length >= STREAM_BATCH_LIMIT) break;
        const name = String(player?.playerName || '');
        const key = name.toLowerCase();
        if (!key || seen.has(key)) continue;
        const amount = round6(Number(player.mon) || 0);
        if (!(amount > 0)) continue;
        // Nobody can be paid without a wallet. Their MON stays in the box and is
        // settled to the final holder instead of disappearing.
        const wallet = await deps.getPlayerWallet(name);
        if (!wallet) continue;
        seen.add(key);
        const clamped = round6(Math.min(amount, left));
        if (!(clamped > 0)) break;
        pending.push({ playerId: player.playerId, playerName: name, amountMon: clamped });
        left = round6(left - clamped);
    }

    if (pending.length > 0) {
        const result = await deps.streamLootBox({ matchId, rows: pending });
        if (!result || !result.success) {
            return { ...box, error: result?.error || 'the lootbox stream could not be paid on-chain' };
        }
        if (result.txHash) box.txHashes.push(result.txHash);
        box.streamed.push(...pending);
        await save();
    }

    // 3. The contract is the truth for what is left: that is exactly what
    //    `settle` pays the final holder.
    let remaining;
    try {
        remaining = round6(Number(await deps.getLootBoxPool(matchId)));
    } catch (error) {
        return { ...box, error: error?.message || String(error) };
    }
    const expected = round6(
        Math.max(
            0,
            pool -
                box.burnedMon -
                box.streamed.reduce((sum, row) => sum + (Number(row.amountMon) || 0), 0)
        )
    );
    box.remainingMon = round6(Math.min(Math.max(0, remaining), expected));
    box.done = true;
    delete box.error;
    await save();
    log('the lootbox was reconciled on-chain', {
        matchId,
        poolMon: box.poolMon,
        burnedMon: box.burnedMon,
        streamed: box.streamed.length,
        remainingMon: box.remainingMon
    });
    return box;
}

/** Reward rows are keyed by match + player + kind so a retry overwrites, never duplicates. */
export function rewardIdFor(matchId, username, kind = 'prize') {
    const safe = String(username || 'player').replace(/[.#$\[\]/]/g, '_');
    const safeMatch = String(matchId || 'match').replace(/[.#$\[\]/]/g, '_');
    return `settlement-${safeMatch}-${safe}-${kind}`;
}

/**
 * Runs the settlement.
 *
 * Returns `{ httpStatus, status, ... }`. The HTTP status is part of the result
 * so the route stays a thin adapter and the flow is testable end to end.
 */
export async function settleRound({ matchId, report, deps }) {
    const log = deps.log || (() => {});

    const invalid = validateReport(report);
    if (invalid) {
        return { httpStatus: 422, status: 'invalid', matchId, error: invalid };
    }
    if (!matchId || typeof matchId !== 'string') {
        return { httpStatus: 422, status: 'invalid', matchId, error: 'a match id is required' };
    }

    const match = await deps.getMatch(matchId);
    if (!match) {
        return { httpStatus: 404, status: 'unknown_match', matchId };
    }

    // Idempotency: the room server retries, and a retry must not pay twice.
    if (match.settlement && match.settlement.credited) {
        return {
            httpStatus: 200,
            status: 'already_settled',
            matchId,
            settlement: match.settlement
        };
    }
    if (match.status === 'cancelled') {
        log('settlement skipped: the match was cancelled', { matchId });
        return { httpStatus: 200, status: 'already_settled', matchId, reason: 'cancelled' };
    }

    // A failed *read* must not look like "this match was never escrowed": that
    // would record `offchain_only` while the prize still sits in the escrow. The
    // ledger is still written (the players are owed the money), but the match is
    // left uncredited and the room server is told to retry so the chain leg can
    // finish on a later attempt.
    let onchain = null;
    let chainReadError = null;
    try {
        onchain = await deps.getOnchainMatch(matchId);
    } catch (error) {
        chainReadError = error?.message || String(error);
        log('the escrow could not be read; writing the ledger and asking for a retry', {
            matchId,
            error: chainReadError
        });
    }

    if (onchain && onchain.settled) {
        log('settlement skipped: the escrow is already settled', { matchId });
        return { httpStatus: 200, status: 'already_settled', matchId, reason: 'settled_onchain' };
    }
    if (onchain && onchain.cancelled) {
        log('settlement skipped: the escrow was cancelled', { matchId });
        return { httpStatus: 200, status: 'already_settled', matchId, reason: 'cancelled_onchain' };
    }

    // The box is the only part of the payout that moves while the round runs:
    // holders stream MON out of it and every steal burns gas out of it. Reconcile
    // it first, because the ledger has to say what was really paid, and because
    // the settle call pays whatever the box has left.
    let box = null;
    if (onchain && !chainReadError) {
        const previousBox = match.settlement && match.settlement.box ? match.settlement.box : null;
        box = await reconcileLootBox({
            matchId,
            report,
            poolMon: onchain.lootBoxPoolMon,
            previous: previousBox,
            deps,
            log
        });
        if (box.error) {
            // Streams and steals are real money: without a reconciled box the
            // ledger cannot say who was paid, so nothing is credited and the room
            // server retries. Progress is kept in `settlement.box`.
            log('the lootbox could not be reconciled; asking for a retry', {
                matchId,
                error: box.error
            });
            await deps.updateMatchRecord(matchId, {
                status: 'settling',
                settlement: { status: STATUS.CHAIN_UNAVAILABLE, credited: false, box }
            });
            return {
                httpStatus: 503,
                status: STATUS.CHAIN_UNAVAILABLE,
                matchId,
                error: box.error
            };
        }
    }

    const ledger = buildPayouts({ match, report, onchain, box });
    const settledAt = new Date().toISOString();

    if (ledger.payouts.length === 0) {
        const settlement = {
            status: chainReadError ? STATUS.CHAIN_UNAVAILABLE : STATUS.NO_PAYOUT,
            credited: !chainReadError,
            reason: report.reason,
            settledAt,
            error: chainReadError,
            payouts: []
        };
        await deps.updateMatchRecord(matchId, {
            status: chainReadError ? 'settling' : 'settled',
            settledAt,
            result: report,
            settlement
        });
        log('settlement finished with no payout', { matchId });
        return {
            httpStatus: chainReadError ? 503 : 200,
            status: settlement.status,
            matchId,
            settlement
        };
    }

    const winner = report.winner || null;
    const prizePayouts = ledger.payouts.filter((payout) => payout.kind === 'prize');
    // A split is a round with more than one paid winner. Counting raw shares
    // instead would treat a second zero-share entry as a split and then fail in
    // `payOnchainSplit`, which cannot split a pool between one wallet.
    const isSplit = prizePayouts.length > 1;

    // The escrow pays the lootbox pool to the final holder, but falls back to the
    // first prize winner when that player has no wallet to receive it. Credit
    // whoever actually receives it, so the ledger never claims money nobody got.
    const lootRow = ledger.payouts.find((payout) => payout.kind === 'lootbox');
    if (lootRow && !(await deps.getPlayerWallet(lootRow.playerName))) {
        const fallback = prizePayouts[0];
        if (fallback) {
            log('the lootbox holder has no wallet; the escrow pays the pool to the winner', {
                matchId,
                holder: lootRow.playerName,
                winner: fallback.playerName
            });
            lootRow.playerId = fallback.playerId;
            lootRow.playerName = fallback.playerName;
        }
    }

    // ---- 1. Ledger. Written before anything touches the chain. -------------
    const rewardIds = [];
    for (const payout of ledger.payouts) {
        const id = rewardIdFor(matchId, payout.playerName, payout.kind);
        const wallet = await deps.getPlayerWallet(payout.playerName);
        await deps.saveReward(
            {
                username: payout.playerName,
                wallet: wallet || null,
                matchId,
                source: match.sponsor || 'WorldOfNads',
                category: payout.kind === 'lootbox' ? 'lootbox' : 'earned',
                kind: payout.kind,
                amount: `${payout.amountMon.toFixed(4)} MON`,
                amountMon: payout.amountMon,
                share: payout.share,
                pending: false,
                txHash: null,
                createdAt: settledAt
            },
            id
        );
        rewardIds.push(id);
    }

    // ---- 2. Player totals (leaderboard + XP). ------------------------------
    let winsCredited = 0;
    for (const player of report.players) {
        const isWinner = winner && player.playerId === winner.playerId;
        const wonMon = ledger.payouts
            .filter((payout) => payout.playerId === player.playerId)
            .reduce((sum, payout) => sum + payout.amountMon, 0);

        const credit = await deps.creditPlayerResult(player.playerName, {
            matchId,
            win: isWinner ? 1 : 0,
            wonMon: round6(wonMon),
            xp: Math.max(0, Math.round(Number(player.xp) || 0))
        });
        if (isWinner && credit && credit.credited) winsCredited += 1;
        if (credit && credit.reason === 'unknown_user') {
            log('a player in the result has no profile', {
                matchId,
                player: player.playerName
            });
        }
    }

    // ---- 3. Chain payout. A split needs settleMatchSplit (V2 engine). ------
    let chainStatus = STATUS.OFFCHAIN_ONLY;
    let txHash = null;
    let chainError = null;

    if (chainReadError) {
        chainStatus = STATUS.CHAIN_UNAVAILABLE;
        chainError = chainReadError;
    } else if (onchain) {
        if (isSplit) {
            try {
                const result = await payOnchainSplit(matchId, prizePayouts, report, deps);
                if (result.success) {
                    chainStatus = STATUS.SETTLED_ONCHAIN;
                    txHash = result.txHash || null;
                } else if (result.unsupported) {
                    // The deployed V1 escrow has no split entry point.
                    chainStatus = STATUS.SPLIT_AWAITING_PAYOUT;
                    chainError = result.error || 'the escrow cannot pay a split round';
                } else {
                    chainStatus = STATUS.ONCHAIN_FAILED;
                    chainError = result.error || 'the escrow call failed';
                }
            } catch (error) {
                chainStatus = STATUS.ONCHAIN_FAILED;
                chainError = error?.message || String(error);
            }
            if (chainError) {
                log('the escrow payout failed; the ledger is still written', {
                    matchId,
                    error: chainError
                });
            }
        } else {
            try {
                const result = await payOnchain(matchId, prizePayouts[0], report, deps);
                if (result.success) {
                    chainStatus = STATUS.SETTLED_ONCHAIN;
                    txHash = result.txHash || null;
                } else {
                    chainStatus = STATUS.ONCHAIN_FAILED;
                    chainError = result.error || 'the escrow call failed';
                }
            } catch (error) {
                chainStatus = STATUS.ONCHAIN_FAILED;
                chainError = error?.message || String(error);
            }
            if (chainError) {
                log('the escrow payout failed; the ledger is still written', {
                    matchId,
                    error: chainError
                });
            }
        }
    }

    const chainUnavailable = chainStatus === STATUS.CHAIN_UNAVAILABLE;
    const pending =
        chainUnavailable ||
        chainStatus === STATUS.SPLIT_AWAITING_PAYOUT ||
        chainStatus === STATUS.ONCHAIN_FAILED;
    if (pending || txHash) {
        for (const id of rewardIds) {
            const patch = { pending };
            if (txHash) patch.txHash = txHash;
            await deps.patchReward(id, patch);
        }
    }

    // ---- 4. Match record. `credited` flips last so a crash re-runs safely. --
    // `credited` stays false when the escrow could not be read, so a retried
    // report re-runs this whole flow instead of treating the match as done.
    const settlement = {
        status: chainStatus,
        credited: !chainUnavailable,
        reason: report.reason,
        settledAt,
        grossMon: ledger.grossMon,
        winnerPoolMon: ledger.winnerPoolMon,
        lootBoxPoolMon: ledger.lootBoxPoolMon,
        lootBoxPayoutMon: ledger.lootBoxPayoutMon,
        totalMon: ledger.totalMon,
        payouts: ledger.payouts,
        rewardIds,
        winsCredited,
        txHash,
        error: chainError,
        box
    };
    await deps.updateMatchRecord(matchId, {
        status: chainUnavailable ? 'settling' : 'settled',
        settledAt,
        result: report,
        settlement,
        ...(txHash ? { settleTxHash: txHash } : {})
    });

    log('settlement finished', {
        matchId,
        status: chainStatus,
        totalMon: ledger.totalMon,
        winners: prizePayouts.length
    });

    // 503 tells the room server to retry: the ledger is durable, the chain leg is not done.
    const httpStatus = chainUnavailable ? 503 : 200;
    return { httpStatus, status: chainStatus, matchId, settlement, ...(chainError ? { error: chainError } : {}) };
}

/**
 * Resolves the wallets of everyone in the round, plus any extra address that
 * must be included (the winner). Deduped case-insensitively: the same person
 * playing on two profiles would otherwise be listed twice, and the contract
 * caps the list at 64 entries.
 */
async function participantWallets(report, extra, deps) {
    const participants = [];
    const seen = new Set();
    const add = (address) => {
        if (!address) return;
        const key = String(address).toLowerCase();
        if (seen.has(key)) return;
        seen.add(key);
        participants.push(address);
    };

    for (const address of extra) add(address);
    for (const player of report.players) {
        if (participants.length >= MAX_PARTICIPANTS) break;
        add(await deps.getPlayerWallet(player.playerName));
    }
    return participants;
}

/**
 * Pays a split round: every prize winner is paid its share of the winner pool.
 *
 * `sharesBps` must add up to exactly 10000. The shares come from the round
 * report, so any rounding dust goes to the first winner instead of being lost.
 *
 * Two usernames can resolve to one wallet (the same player on two profiles).
 * The escrow rejects duplicate winners, so their shares are merged first.
 */
async function payOnchainSplit(matchId, prizePayouts, report, deps) {
    if (!prizePayouts || prizePayouts.length < 2) {
        return { success: false, error: 'a split needs at least two prize winners' };
    }

    const byWallet = new Map();
    for (const payout of prizePayouts) {
        const wallet = await deps.getPlayerWallet(payout.playerName);
        if (!wallet) {
            return { success: false, error: `no wallet for ${payout.playerName}` };
        }
        const key = String(wallet).toLowerCase();
        const entry = byWallet.get(key) || { wallet, bps: 0 };
        entry.bps += Math.floor(payout.share * 10000);
        byWallet.set(key, entry);
    }

    const winners = Array.from(byWallet.values()).map((entry) => entry.wallet);
    const sharesBps = Array.from(byWallet.values()).map((entry) => entry.bps);
    if (winners.length === 0) {
        return { success: false, error: 'a split needs at least one payable winner' };
    }

    const totalBps = sharesBps.reduce((sum, bps) => sum + bps, 0);
    sharesBps[0] += 10000 - totalBps;

    const participants = await participantWallets(report, winners, deps);
    const lootHolderWallet = report.lootboxHolder
        ? await deps.getPlayerWallet(report.lootboxHolder.playerName)
        : null;

    return deps.settleOnchainSplit({
        matchId,
        winners,
        sharesBps,
        participants,
        lootHolderName: report.lootboxHolder?.playerName || null,
        // Mirrors the escrow's own fallback, so the ledger and the chain agree on
        // who receives the pool when the holder has no wallet.
        lootHolderWallet: lootHolderWallet || winners[0]
    });
}

/**
 * Builds the address list the escrow expects and asks it to pay.
 *
 * Only resolved wallets are sent (an unfunded wallet cannot receive), and the
 * winner is always included. The contract caps the list at 64 entries.
 */
async function payOnchain(matchId, prizePayout, report, deps) {
    if (!prizePayout) {
        return { success: false, error: 'there is no prize winner to pay' };
    }

    const winnerWallet = await deps.getPlayerWallet(prizePayout.playerName);
    if (!winnerWallet) {
        return { success: false, error: `no wallet for the winner ${prizePayout.playerName}` };
    }

    const participants = await participantWallets(report, [winnerWallet], deps);
    const lootHolderWallet = report.lootboxHolder
        ? await deps.getPlayerWallet(report.lootboxHolder.playerName)
        : null;

    return deps.settleOnchain({
        matchId,
        winnerName: prizePayout.playerName,
        winnerWallet,
        participants,
        lootHolderName: report.lootboxHolder?.playerName || null,
        // Mirrors the escrow's own fallback (see payOnchainSplit).
        lootHolderWallet: lootHolderWallet || winnerWallet
    });
}
