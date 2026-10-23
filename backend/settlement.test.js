// Tests for the round settlement flow. No Firebase, no ethers, no network:
// every side effect is a mock, which is the point of `settlement.js` taking its
// dependencies as arguments.
//
// Run with: node --test backend/settlement.test.js

import test from 'node:test';
import assert from 'node:assert/strict';

import {
    buildPayouts,
    parsePrizeMon,
    rewardIdFor,
    round6,
    settleRound,
    validateReport,
    STATUS
} from './settlement.js';

const addressOf = (name) =>
    `0x${Buffer.from(name).toString('hex').padEnd(40, '0').slice(0, 40)}`;

function makeDeps({ match, onchain = null, chain = null, chainSplit = null } = {}) {
    const state = {
        match: match ? { ...match } : null,
        onchain,
        rewards: new Map(),
        users: new Map(),
        credited: new Set(),
        chainCalls: [],
        splitChainCalls: [],
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
            if (state.credited.has(key)) return { credited: false, reason: 'already_credited' };
            state.credited.add(key);
            const current = state.users.get(name) || { won: 0, wonMon: 0, xp: 0 };
            state.users.set(name, {
                won: current.won + credit.win,
                wonMon: round6(current.wonMon + credit.wonMon),
                xp: current.xp + credit.xp
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

test('a single winner takes the whole winner pool and the lootbox holder the pool', () => {
    const { payouts, totalMon, winnerPoolMon, lootBoxPoolMon } = buildPayouts({
        match: MATCH,
        report: SINGLE_REPORT,
        onchain: ONCHAIN
    });

    assert.equal(winnerPoolMon, 7.2);
    assert.equal(lootBoxPoolMon, 1.8);
    assert.equal(payouts.length, 2);
    assert.deepEqual(
        payouts.map((p) => [p.kind, p.playerName, p.amountMon]),
        [
            ['prize', 'alice', 7.2],
            ['lootbox', 'bob', 1.8]
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
    assert.equal(payouts[1].amountMon, 0.9);
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

    // Ledger
    assert.equal(state.rewards.size, 2);
    const alice = state.rewards.get(rewardIdFor(MATCH.matchId, 'alice'));
    const bob = state.rewards.get(rewardIdFor(MATCH.matchId, 'bob', 'lootbox'));
    assert.equal(alice.amountMon, 7.2);
    assert.equal(alice.amount, '7.2000 MON');
    assert.equal(alice.txHash, '0xtx');
    assert.equal(alice.pending, false);
    assert.equal(bob.amountMon, 1.8);
    assert.equal(bob.category, 'lootbox');

    // Leaderboard totals: the winner counts a win, both count MON won and XP.
    assert.deepEqual(state.users.get('alice'), { won: 1, wonMon: 7.2, xp: 400 });
    assert.deepEqual(state.users.get('bob'), { won: 0, wonMon: 1.8, xp: 100 });

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

    assert.equal(state.rewards.size, 3);
    const alice = state.rewards.get(rewardIdFor(MATCH.matchId, 'alice'));
    const bobPrize = state.rewards.get(rewardIdFor(MATCH.matchId, 'bob'));
    const bobLoot = state.rewards.get(rewardIdFor(MATCH.matchId, 'bob', 'lootbox'));
    assert.equal(alice.amountMon, 1.44);
    assert.equal(bobPrize.amountMon, 5.76);
    assert.equal(bobLoot.amountMon, 1.8);
    assert.equal(alice.txHash, '0xtx-split');
    assert.equal(alice.pending, false);

    // The holder is the round's winner even with the smaller share.
    assert.equal(state.users.get('alice').won, 1);
    assert.equal(state.users.get('bob').won, 0);
    assert.equal(state.users.get('bob').wonMon, 7.56);

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
    assert.equal(state.rewards.size, 3);
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
    assert.equal(state.rewards.size, 2);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).pending, true);
    assert.equal(state.match.settlement.error, 'execution reverted');
    assert.equal(state.users.get('alice').won, 1);
});

test('a match with no escrow is settled off-chain only', async () => {
    const { deps, state } = makeDeps({ match: MATCH, onchain: null });
    const result = await settleRound({ matchId: MATCH.matchId, report: SINGLE_REPORT, deps });

    assert.equal(result.status, STATUS.OFFCHAIN_ONLY);
    assert.equal(state.chainCalls.length, 0);
    assert.equal(state.rewards.size, 2);
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

    assert.equal(state.rewards.size, 2, 'the retry must not add reward rows');
    assert.equal(state.chainCalls.length, 1, 'the retry must not pay the escrow twice');
    assert.deepEqual(state.users.get('alice'), { won: 1, wonMon: 7.2, xp: 400 });
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
    assert.equal(state.rewards.size, 2);
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
    assert.equal(state.rewards.size, 2);
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
    assert.equal(state.rewards.size, 2, 'the retry must not add reward rows');
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).pending, false);
    assert.equal(state.rewards.get(rewardIdFor(MATCH.matchId, 'alice')).txHash, '0xtx');
    assert.equal(state.chainCalls.length, 1, 'the escrow is paid exactly once');
    assert.deepEqual(state.users.get('alice'), { won: 1, wonMon: 7.2, xp: 400 });
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
