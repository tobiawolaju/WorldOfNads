// Tests for the round settlement flow. No Firebase, no ethers, no network:
// every side effect is a mock, which is the point of `settlement.js` taking its
// dependencies as arguments.
//
// Run with: node --test backend/settlement.test.js

import test from 'node:test';
import assert from 'node:assert/strict';

import {
    buildPayouts,
    LOOTBOX_STEAL_COST_MON,
    parsePrizeMon,
    reconcileLootBox,
    rewardIdFor,
    round6,
    settleRound,
    validateReport,
    STATUS
} from './settlement.js';

const addressOf = (name) =>
    `0x${Buffer.from(name).toString('hex').padEnd(40, '0').slice(0, 40)}`;

function makeDeps({ match, onchain = null, chain = null, chainSplit = null, steal = null, stream = null } = {}) {
    const state = {
        match: match ? { ...match } : null,
        onchain,
        rewards: new Map(),
        users: new Map(),
        credits: new Map(),
        chainCalls: [],
        splitChainCalls: [],
        stealCalls: [],
        streamCalls: [],
        streamedRows: [],
        logs: []
    };

    const deps = {
        getMatch: async () => state.match,
        getOnchainMatch: async () => state.onchain,
        getPlayerWallet: async (name) => addressOf(name),
        saveReward: async (data, id) => {
            state.rewards.set(id, { ...data, id });
            return id;
        },
        patchReward: async (id, patch) => {
            state.rewards.set(id, { ...state.rewards.get(id), ...patch });
        },
        creditPlayerResult: async (name, credit) => {
            const key = `${name}:${credit.matchId}`;
            const previous = state.credits.get(key);
            const delta = {
                win: Number(credit.win || 0) - Number(previous?.win || 0),
                wonMon: round6(Number(credit.wonMon || 0) - Number(previous?.wonMon || 0)),
                xp: Math.round(Number(credit.xp || 0) - Number(previous?.xp || 0))
            };
            if (previous && delta.win === 0 && delta.wonMon === 0 && delta.xp === 0) {
                return { credited: false, reason: 'already_credited' };
            }
            state.credits.set(key, {
                win: Number(credit.win || 0),
                wonMon: round6(credit.wonMon),
                xp: Math.round(Number(credit.xp || 0))
            });
            const current = state.users.get(name) || { won: 0, wonMon: 0, xp: 0 };
            state.users.set(name, {
                won: current.won + delta.win,
                wonMon: round6(current.wonMon + delta.wonMon),
                xp: current.xp + delta.xp
            });
            return { credited: true };
        },
        updateMatchRecord: async (id, patch) => {
            state.match = { ...state.match, ...patch };
        },
        settleOnchain: async (request) => {
            state.chainCalls.push(request);
            return chain || { success: true, txHash: '0xtx' };
        },
        settleOnchainSplit: async (request) => {
            state.splitChainCalls.push(request);
            return chainSplit || { success: true, txHash: '0xtx-split' };
        },
        stealLootBox: async (request) => {
            state.stealCalls.push(request);
            return steal || { success: true, txHash: `0xsteal-${state.stealCalls.length}` };
        },
        streamLootBox: async (request) => {
            state.streamCalls.push(request);
            const outcome = stream || { success: true, txHash: `0xstream-${state.streamCalls.length}` };
            // Only a successful batch moved money out of the box.
            if (outcome.success) state.streamedRows.push(...request.rows);
            return outcome;
        },
        // Mirrors WONsLootBox: the pool loses a burn per steal and whatever it
        // streamed, so the clamp in reconcileLootBox is exercised for real.
        getLootBoxPool: async () => {
            const pool = Number(onchain?.lootBoxPoolMon) || 0;
            const burned = state.stealCalls.length * LOOTBOX_STEAL_COST_MON;
            const streamed = state.streamedRows.reduce((sum, row) => sum + row.amountMon, 0);
            return round6(Math.max(0, pool - burned - streamed));
        },
        log: (message, meta) => {
            state.logs.push({ message, meta });
        }
    };

    return { deps, state };
}

const MATCH = {
    matchId: 'match-test-1',
    sponsor: 'WorldOfNads',
    prize: '10 MON',
    prizeAmount: 10,
    status: 'completed'
};

const ONCHAIN = {
    winnerPrizeMon: 7.2,
    lootBoxPoolMon: 1.8,
    settled: false,
    cancelled: false
};

const SINGLE_REPORT = {
    reason: 'buzzer',
    endedAt: 1792158750095,
    winner: { playerId: 'p1', playerName: 'alice', possessionSeconds: 40 },
    split: {
        isSplit: false,
        shares: [{ playerId: 'p1', playerName: 'alice', seconds: 40, share: 1 }]
    },
    players: [
        { playerId: 'p1', playerName: 'alice', possessionSeconds: 40, xp: 400, mon: 0.5 },
        { playerId: 'p2', playerName: 'bob', possessionSeconds: 10, xp: 100, mon: 0.25 }
    ],
    lootboxHolder: { playerId: 'p2', playerName: 'bob' }
};

const SPLIT_REPORT = {
    reason: 'buzzer',
    endedAt: 1792158750095,
    winner: { playerId: 'p1', playerName: 'alice', possessionSeconds: 10 },
    split: {
        isSplit: true,
        shares: [
            { playerId: 'p1', playerName: 'alice', seconds: 10, share: 0.2 },
            { playerId: 'p2', playerName: 'bob', seconds: 40, share: 0.8 }
        ]
    },
    players: [
        { playerId: 'p2', playerName: 'bob', possessionSeconds: 40, xp: 400, mon: 0.5 },
        { playerId: 'p1', playerName: 'alice', possessionSeconds: 10, xp: 100, mon: 0.25 }
    ],
    lootboxHolder: { playerId: 'p2', playerName: 'bob' }
};

// -- validation -----------------------------------------------------------

test('a valid report passes validation', () => {
    assert.equal(validateReport(SINGLE_REPORT), null);
    assert.equal(validateReport(SPLIT_REPORT), null);
});

test('shares that do not add up to one are rejected', () => {
    const report = {
        ...SPLIT_REPORT,
        split: {
            isSplit: true,
            shares: [
                { playerId: 'p1', playerName: 'alice', share: 0.5 },
                { playerId: 'p2', playerName: 'bob', share: 0.9 }
            ]
        }
    };
    assert.match(validateReport(report), /add up to 1/);
});

test('a report without a reason is rejected', () => {
    assert.match(validateReport({ ...SINGLE_REPORT, reason: 'timeout' }), /reason/);
});

test('the prize can be read from the number or the label', () => {
    assert.equal(parsePrizeMon({ prizeAmount: 5 }), 5);
    assert.equal(parsePrizeMon({ prize: '10 MON' }), 10);
    assert.equal(parsePrizeMon({}), 0);
});

// -- payout maths ---------------------------------------------------------

test('the winner takes the winner pool and the box splits into streams plus a remainder', () => {
    const { payouts, totalMon, winnerPoolMon, lootBoxPoolMon } = buildPayouts({
        match: MATCH,
        report: SINGLE_REPORT,
        onchain: ONCHAIN
    });

    assert.equal(winnerPoolMon, 7.2);
    assert.equal(lootBoxPoolMon, 1.8);
    assert.equal(payouts.length, 4);
    assert.deepEqual(
        payouts.map((p) => [p.kind, p.playerName, p.amountMon]),
        [
            ['prize', 'alice', 7.2],
            // 0.5 + 0.25 streamed out of the box while it was carried...
            ['stream', 'alice', 0.5],
            ['stream', 'bob', 0.25],
            // ...leaving the final holder what is left.
            ['lootbox', 'bob', 1.05]
        ]
    );
    assert.equal(totalMon, 9);
});

test('a split distributes the winner pool by share', () => {
    const { payouts } = buildPayouts({ match: MATCH, report: SPLIT_REPORT, onchain: ONCHAIN });
    const prizes = payouts.filter((p) => p.kind === 'prize');
    assert.deepEqual(
        prizes.map((p) => [p.playerName, p.amountMon]),
        [
            ['alice', 1.44],
            ['bob', 5.76]
        ]
    );
});

test('a match that was never escrowed uses the contract shares of the gross prize', () => {
    const { payouts, winnerPoolMon, lootBoxPoolMon } = buildPayouts({
        match: { ...MATCH, prize: '5 MON', prizeAmount: 5 },
        report: SINGLE_REPORT,
        onchain: null
    });
    assert.equal(winnerPoolMon, 3.6);
    assert.equal(lootBoxPoolMon, 0.9);
    assert.equal(payouts[0].amountMon, 3.6);
    // The 0.9 box is split the way the HUD showed it: 0.5 + 0.25 streamed, 0.15
    // left for the final holder.
    const byKind = (kind) => payouts.filter((p) => p.kind === kind);
    assert.equal(byKind('stream').length, 2);
    assert.equal(byKind('lootbox')[0].amountMon, 0.15);
    assert.equal(
        round6(payouts.reduce((sum, payout) => sum + payout.amountMon, 0)),
        4.5
    );
});

test('reward ids are deterministic so a retry overwrites instead of duplicating', () => {
    assert.equal(rewardIdFor('match-1', 'alice'), rewardIdFor('match-1', 'alice'));
    assert.notEqual(rewardIdFor('match-1', 'alice'), rewardIdFor('match-1', 'bob'));
    assert.equal(rewardIdFor('match/1', 'a.b'), 'settlement-match_1-a_b-prize');
    // A player can win the prize and carry the lootbox: separate rows.
    assert.equal(rewardIdFor('match-1', 'alice', 'lootbox'), 'settlement-match-1-alice-lootbox');
});

// -- settlement flow ------------------------------------------------------

test('an unknown match is a 404 and writes nothing', async () => {
    const { deps, state } = makeDeps({ match: null });
    const result = await settleRound({ matchId: 'nope', report: SINGLE_REPORT, deps });

    assert.equal(result.httpStatus, 404);
    assert.equal(result.status, 'unknown_match');
    assert.equal(state.rewards.size, 0);
});

test('an invalid report is a 422 and writes nothing', async () => {
    const { deps, state } = makeDeps({ match: MATCH });
    const result = await settleRound({
        matchId: MATCH.matchId,
        report: { ...SINGLE_REPORT, reason: 'nope' },
        deps
    });

    assert.equal(result.httpStatus, 422);
    assert.equal(state.rewards.size, 0);
});

test('a single-winner round credits the ledger, the players and the escrow', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.httpStatus, 200);
    assert.equal(result.status, STATUS.SETTLED_ONCHAIN);

    // Ledger: the stream rows are real earnings paid out of the box while it was
    // carried, so the lootbox row is only what is left after them.
    assert.equal(state.rewards.size, 4);
    const alice = state.rewards.get(rewardIdFor(MATCH.matchId, 'alice'));
    const aliceStream = state.rewards.get(rewardIdFor(MATCH.matchId, 'alice', 'stream'));
    const bob = state.rewards.get(rewardIdFor(MATCH.matchId, 'bob', 'lootbox'));
    const bobStream = state.rewards.get(rewardIdFor(MATCH.matchId, 'bob', 'stream'));
    assert.equal(alice.amountMon, 7.2);
    assert.equal(alice.amount, '7.2000 MON');
    assert.equal(alice.txHash, '0xtx');
    assert.equal(alice.pending, false);
    assert.equal(aliceStream.amountMon, 0.5);
    assert.equal(aliceStream.category, 'earned');
    assert.equal(bobStream.amountMon, 0.25);
    assert.equal(bob.amountMon, 1.05);
    assert.equal(bob.category, 'lootbox');

    // Leaderboard totals: the winner counts a win, both count MON won and XP.
    assert.deepEqual(state.users.get('alice'), { won: 1, wonMon: 7.7, xp: 400 });
    assert.deepEqual(state.users.get('bob'), { won: 0, wonMon: 1.3, xp: 100 });

    // Escrow: one call, winner first, unique participants.
    assert.equal(state.chainCalls.length, 1);
    assert.equal(state.chainCalls[0].winnerWallet, addressOf('alice'));
    assert.equal(state.chainCalls[0].participants.length, 2);
    assert.equal(new Set(state.chainCalls[0].participants).size, 2);
    assert.equal(state.chainCalls[0].lootHolderWallet, addressOf('bob'));

    // Match record
    assert.equal(state.match.status, 'settled');
    assert.equal(state.match.settleTxHash, '0xtx');
    assert.equal(state.match.settlement.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.match.settlement.credited, true);
    assert.equal(state.match.settlement.totalMon, 9);
    assert.equal(state.match.settlement.winsCredited, 1);
});

test('a split round pays each winner its share through settleMatchSplit', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const result = await settleRound({ matchId: MATCH.matchId, report: SPLIT_REPORT, deps });

    assert.equal(result.httpStatus, 200);
    assert.equal(result.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.chainCalls.length, 0, 'the single-winner entry point is not used');

    assert.equal(state.splitChainCalls.length, 1);
    const call = state.splitChainCalls[0];
    assert.deepEqual(call.winners, [addressOf('alice'), addressOf('bob')]);
    assert.deepEqual(call.sharesBps, [2000, 8000]);
    assert.equal(call.sharesBps.reduce((a, b) => a + b, 0), 10000);
    assert.equal(call.participants.length, 2);
    assert.equal(call.lootHolderWallet, addressOf('bob'));

    assert.equal(state.rewards.size, 5);
    const alice = state.rewards.get(rewardIdFor(MATCH.matchId, 'alice'));
    const bobPrize = state.rewards.get(rewardIdFor(MATCH.matchId, 'bob'));
    const bobLoot = state.rewards.get(rewardIdFor(MATCH.matchId, 'bob', 'lootbox'));
    assert.equal(alice.amountMon, 1.44);
    assert.equal(bobPrize.amountMon, 5.76);
    assert.equal(bobLoot.amountMon, 1.05);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'bob', 'stream')).amountMon, 0.5);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice', 'stream')).amountMon, 0.25);
    assert.equal(alice.txHash, '0xtx-split');
    assert.equal(alice.pending, false);

    // The holder is the round's winner even with the smaller share.
    assert.equal(state.users.get('alice').won, 1);
    assert.equal(state.users.get('bob').won, 0);
    assert.equal(state.users.get('bob').wonMon, 7.31);

    assert.equal(state.match.settlement.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.match.settlement.txHash, '0xtx-split');
});

test('a split against an escrow without settleMatchSplit stays pending', async () => {
    const { deps, state } = makeDeps({
        match: MATCH,
        onchain: ONCHAIN,
        chainSplit: { success: false, unsupported: true, error: 'not a function' }
    });
    const result = await settleRound({ matchId: MATCH.matchId, report: SPLIT_REPORT, deps });

    assert.equal(result.status, STATUS.SPLIT_AWAITING_PAYOUT);
    assert.equal(state.rewards.size, 5);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).pending, true);
    assert.equal(state.match.settlement.txHash, null);
    assert.equal(state.users.get('alice').won, 1);
});

test('a failed split payout keeps the ledger and is marked pending', async () => {
    const { deps, state } = makeDeps({
        match: MATCH,
        onchain: ONCHAIN,
        chainSplit: { success: false, error: 'execution reverted' }
    });
    const result = await settleRound({ matchId: MATCH.matchId, report: SPLIT_REPORT, deps });

    assert.equal(result.status, STATUS.ONCHAIN_FAILED);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).pending, true);
    assert.equal(state.match.settlement.error, 'execution reverted');
});

test('a failed escrow call still writes the ledger', async () => {
    const { deps, state } = makeDeps({
        match: MATCH,
        onchain: ONCHAIN,
        chain: { success: false, error: 'execution reverted' }
    });
    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.status, STATUS.ONCHAIN_FAILED);
    assert.equal(state.rewards.size, 4);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).pending, true);
    assert.equal(state.match.settlement.error, 'execution reverted');
    assert.equal(state.users.get('alice').won, 1);
});

test('a match with no escrow is settled off-chain only', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: null });
    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.status, STATUS.OFFCHAIN_ONLY);
    assert.equal(state.chainCalls.length, 0);
    assert.equal(state.rewards.size, 4);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).amountMon, 7.2);
});

test('a round without shares settles with no payout', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const report = {
        ...SINGLE_REPORT,
        winner: null,
        split: { isSplit: false, shares: [] },
        players: [],
        lootboxHolder: null
    };
    const result = await settleRound({ matchId: MATCH.matchId, report, deps });

    assert.equal(result.status, STATUS.NO_PAYOUT);
    assert.equal(state.rewards.size, 0);
    assert.equal(state.match.settlement.credited, true);
});

test('a retried report is a no-op, so nobody is paid twice', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });

    const first = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });
    assert.equal(first.status, STATUS.SETTLED_ONCHAIN);

    const second = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });
    assert.equal(second.httpStatus, 200);
    assert.equal(second.status, 'already_settled');

    assert.equal(state.rewards.size, 4, 'the retry must not add reward rows');
    assert.equal(state.chainCalls.length, 1, 'the retry must not pay the escrow twice');
    assert.deepEqual(state.users.get('alice'), { won: 1, wonMon: 7.7, xp: 400 });
});

test('a cancelled match is never paid', async () => {
    const { deps, state } = makeDeps({
        match: { ...MATCH, status: 'cancelled' },
        onchain: null
    });
    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.status, 'already_settled');
    assert.equal(state.rewards.size, 0);
    assert.equal(state.chainCalls.length, 0);
});

test('an escrow that is already settled is not paid again', async () => {
    const { deps, state } = makeDeps({
        match: MATCH,
        onchain: { ...ONCHAIN, settled: true }
    });
    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.status, 'already_settled');
    assert.equal(state.chainCalls.length, 0);
    assert.equal(state.rewards.size, 0);
});

test('a winner without a wallet keeps the ledger and reports the chain failure', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    deps.getPlayerWallet = async (name) => (name === 'alice' ? null : addressOf(name));

    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.status, STATUS.ONCHAIN_FAILED);
    assert.equal(state.chainCalls.length, 0);
    assert.equal(state.rewards.size, 3);
    assert.match(state.match.settlement.error, /no wallet for the winner/);
});

test('an unreadable escrow keeps the ledger, stays uncredited and asks for a retry', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    deps.getOnchainMatch = async () => {
        throw new Error('rpc unavailable');
    };

    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    // A read failure must not be mistaken for "this match was never escrowed".
    assert.equal(result.httpStatus, 503);
    assert.equal(result.status, STATUS.CHAIN_UNAVAILABLE);
    assert.equal(state.chainCalls.length, 0, 'the escrow must not be touched blind');

    // The players are still owed the money, so the ledger is written...
    assert.equal(state.rewards.size, 4);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).amountMon, 7.2);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).pending, true);

    // ...but the match stays open for the retry, and wins are credited once.
    assert.equal(state.match.settlement.credited, false);
    assert.equal(state.match.status, 'settling');
    assert.equal(state.users.get('alice').won, 1);
});

test('the retry after an unreadable escrow finishes the chain leg without duplicating', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    let failing = true;
    deps.getOnchainMatch = async () => {
        if (failing) throw new Error('rpc unavailable');
        return ONCHAIN;
    };

    const first = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });
    assert.equal(first.httpStatus, 503);

    failing = false;
    const second = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(second.httpStatus, 200);
    assert.equal(second.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.rewards.size, 4, 'the retry must not add reward rows');    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).pending, false);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).txHash, '0xtx');
    assert.equal(state.chainCalls.length, 1, 'the escrow is paid exactly once');
    assert.deepEqual(state.users.get('alice'), { won: 1, wonMon: 7.7, xp: 400 });
    assert.equal(state.match.settlement.credited, true);
});

test('a zero-share sibling does not turn a single winner into a split', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const report = {
        ...SINGLE_REPORT,
        split: {
            isSplit: true,
            shares: [
                { playerId: 'p1', playerName: 'alice', seconds: 40, share: 1 },
                { playerId: 'p2', playerName: 'bob', seconds: 0, share: 0 }
            ]
        }
    };

    const result = await settleRound({ matchId: MATCH.matchId, report, deps });

    assert.equal(result.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.splitChainCalls.length, 0);
    assert.equal(state.chainCalls.length, 1);
    assert.equal(state.chainCalls[0].winnerName, 'alice');
    assert.equal(state.rewards.has(rewardIdFor(MATCH.matchId, 'bob')), false);
});

test('two winners on one wallet are merged before the escrow is called', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const shared = '0x1111111111111111111111111111111111111111';
    deps.getPlayerWallet = async (name) =>
        name === 'alice' || name === 'bob' ? shared : addressOf(name);

    const result = await settleRound({ matchId: MATCH.matchId, report: SPLIT_REPORT, deps });

    assert.equal(result.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.splitChainCalls.length, 1);
    const call = state.splitChainCalls[0];
    // The escrow rejects duplicate winners, so the two shares are folded into one.
    assert.deepEqual(call.winners, [shared]);
    assert.deepEqual(call.sharesBps, [10000]);
    assert.equal(call.participants.length, 1, 'the shared wallet is listed once');
    // Both players still get their own ledger row (two prizes, two streams and
    // the lootbox remainder).
    assert.equal(state.rewards.size, 5);
});

test('the participant list keeps every wallet once, whatever the case', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    deps.getPlayerWallet = async (name) =>
        name === 'alice'
            ? '0xAbCd000000000000000000000000000000001234'
            : '0xabcd000000000000000000000000000000001234';

    await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(state.chainCalls.length, 1);
    assert.equal(state.chainCalls[0].participants.length, 1);
});

test('the lootbox pool is credited to the winner when the holder has no wallet', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    // bob holds the box but cannot receive it; the escrow pays the pool to alice.
    deps.getPlayerWallet = async (name) => (name === 'bob' ? null : addressOf(name));

    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.chainCalls[0].lootHolderWallet, addressOf('alice'));
    assert.equal(state.rewards.has(rewardIdFor(MATCH.matchId, 'bob', 'lootbox')), false);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice', 'lootbox')).amountMon, 1.3);
    // And the winner's totals match what the chain paid.
    assert.deepEqual(state.users.get('alice'), { won: 1, wonMon: 9, xp: 400 });
});

// -- lootbox economy (Whitepaper 5.4) -------------------------------------

test('a box nobody picked up pays the winner, matching the escrow fallback', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const report = { ...SINGLE_REPORT, players: [], lootboxHolder: null };

    const result = await settleRound({ matchId: MATCH.matchId, report, deps });

    assert.equal(result.httpStatus, 200);
    const row = state.rewards.get(rewardIdFor(MATCH.matchId, 'alice', 'lootbox'));
    assert.equal(row.amountMon, 1.8);
    assert.equal(state.chainCalls[0].lootHolderWallet, addressOf('alice'));
});

test('every steal burns gas out of the box before the holder is paid', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const report = { ...SINGLE_REPORT, lootboxSteals: 2 };

    const result = await settleRound({ matchId: MATCH.matchId, report, deps });

    assert.equal(result.status, STATUS.SETTLED_ONCHAIN);
    assert.equal(state.stealCalls.length, 2, 'each steal is replayed on-chain');

    // 1.8 pool - 2 * 0.001 gas - 0.5 - 0.25 streamed = 1.048 for the holder.
    const box = state.match.settlement.box;
    assert.equal(box.burnedMon, 0.002);
    assert.equal(box.remainingMon, 1.048);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'bob', 'lootbox')).amountMon, 1.048);

    // The ledger still accounts for the whole pool: payouts + burns = 9 MON.
    const paid = state.match.settlement.payouts.reduce((sum, payout) => sum + payout.amountMon, 0);
    assert.equal(round6(paid + box.burnedMon), 9);
});

test('a failed stream writes nothing and the retry does not replay the steals', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const report = { ...SINGLE_REPORT, lootboxSteals: 1 };
    const healthyStream = deps.streamLootBox;
    deps.streamLootBox = async (request) => {
        state.streamCalls.push(request);
        return { success: false, error: 'rpc down' };
    };

    const first = await settleRound({ matchId: MATCH.matchId, report, deps });
    assert.equal(first.httpStatus, 503);
    assert.equal(state.rewards.size, 0, 'no ledger until the box is reconciled');
    assert.equal(state.match.settlement.credited, false);
    assert.equal(state.match.settlement.box.appliedSteals, 1, 'progress is kept');

    deps.streamLootBox = healthyStream;
    const second = await settleRound({ matchId: MATCH.matchId, report, deps });

    assert.equal(second.httpStatus, 200);
    assert.equal(state.stealCalls.length, 1, 'the steal is replayed once, not twice');
    assert.equal(state.match.settlement.box.appliedSteals, 1);
    assert.equal(state.match.settlement.box.streamed.length, 2, 'both holders paid once');
    assert.equal(state.rewards.size, 4);
});

test('the box can never stream more than it holds', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: ONCHAIN });
    const report = {
        ...SINGLE_REPORT,
        players: [
            { playerId: 'p1', playerName: 'alice', possessionSeconds: 40, xp: 400, mon: 1.5 },
            { playerId: 'p2', playerName: 'bob', possessionSeconds: 10, xp: 100, mon: 1.5 }
        ]
    };

    const result = await settleRound({ matchId: MATCH.matchId, report, deps });

    assert.equal(result.httpStatus, 200);
    const rows = state.match.settlement.box.streamed;
    assert.equal(round6(rows.reduce((sum, row) => sum + row.amountMon, 0)), 1.8);
    assert.equal(rows[0].amountMon, 1.5);
    assert.equal(rows[1].amountMon, 0.3);
    assert.equal(state.rewards.has(rewardIdFor(MATCH.matchId, 'bob', 'lootbox')), false);
    assert.equal(state.users.get('alice').wonMon, 8.7);
    assert.equal(state.users.get('bob').wonMon, 0.3);
});
