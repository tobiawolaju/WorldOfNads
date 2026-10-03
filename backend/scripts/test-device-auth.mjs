/**
 * Exercises the post-approval half of the device-login flow (exchange ->
 * session -> refresh -> /auth/me -> logout) by seeding an approved device_login
 * directly, plus an offline check of Privy access-token verification using a
 * locally signed token (no network).
 *
 *   node scripts/test-device-auth.mjs
 */

import * as dotenv from 'dotenv';
dotenv.config();

const { createDeviceLogin } = await import('../authStore.js');
const auth = await import('../authService.js');

const { digestWithPepper, sha256 } = auth.authInternals;

const deviceId = 'test-device-' + Date.now();
const deviceLoginId = `dl_${'a'.repeat(32)}`;
const secret = 'b'.repeat(64);
const code = 'TEST1';
let failures = 0;

function check(label, condition, detail = '') {
  const status = condition ? 'PASS' : 'FAIL';
  if (!condition) failures += 1;
  console.log(`[${status}] ${label}${detail ? ' -> ' + detail : ''}`);
}

const step = (label) => process.stderr.write(`... ${label}\n`);

step('seeding approved device_login');
// Seed an APPROVED ticket as if the web approval page had just run.
await createDeviceLogin({
  device_login_id: deviceLoginId,
  code_hash: digestWithPepper(code),
  secret_hash: sha256(secret),
  status: 'approved',
  created_at: Date.now() - 1000,
  expires_at: Date.now() + 120_000,
  approved_at: Date.now(),
  used_at: null,
  platform: 'android',
  device_id: deviceId,
  device_label: 'Test Device',
  request_ip_hash: null,
  user_id: 'won_testuser123',
  privy_user_id: 'did:privy:test',
  username: 'testuser',
  wallet_address: '0x0000000000000000000000000000000000000001',
  profile_picture_url: 'https://img.example/pfp.png'
});

step('1. exchange');
// 1. Exchange mints a session.
const exchanged = await auth.exchangeDeviceLogin({
  deviceLoginId, secret, platform: 'android', deviceId, ip: '10.0.0.1'
});
check('exchange succeeds', exchanged.ok, JSON.stringify(exchanged.payload || exchanged.error));
const access1 = exchanged.payload?.access_token;
const refresh1 = exchanged.payload?.refresh_token;
check('returns both tokens', Boolean(access1 && refresh1));
check('returns won user id', exchanged.payload?.user?.id === 'won_testuser123');
check('exchange carries profile picture', exchanged.payload?.user?.profile_picture_url === 'https://img.example/pfp.png');

// 2. Ticket is single-use.
const replay = await auth.exchangeDeviceLogin({ deviceLoginId, secret, deviceId, ip: '10.0.0.1' });
check('replay of exchange is rejected', !replay.ok, replay.error);

// 3. /auth/me accepts the access token and rejects a wrong one.
const me = await auth.getAuthenticatedSession({ authorizationHeader: `Bearer ${access1}` });
check('/auth/me accepts access token', me.ok && me.payload.user.id === 'won_testuser123');
check('/auth/me carries profile picture', me.payload?.user?.profile_picture_url === 'https://img.example/pfp.png');
const meBad = await auth.getAuthenticatedSession({ authorizationHeader: 'Bearer deadbeef' });
check('/auth/me rejects bad token', !meBad.ok, meBad.error);

// 4. Refresh rotates both tokens.
const refreshed = await auth.refreshSession({ refreshToken: refresh1, deviceId });
check('refresh succeeds', refreshed.ok, JSON.stringify(refreshed.payload || refreshed.error));
const refresh2 = refreshed.payload?.refresh_token;
check('refresh rotates the refresh token', Boolean(refresh2) && refresh2 !== refresh1);
check('refresh rotates the access token', refreshed.payload?.access_token !== access1);

// 5. The superseded refresh token must not work (rotation, not just renewal).
const refreshReplay = await auth.refreshSession({ refreshToken: refresh1, deviceId });
check('old refresh token is dead after rotation', !refreshReplay.ok, refreshReplay.error);

// 6. New access token works.
const me2 = await auth.getAuthenticatedSession({
  authorizationHeader: `Bearer ${refreshed.payload?.access_token}`
});
check('rotated access token works', me2.ok);

// 7. Logout revokes, then the refresh token is dead.
await auth.logoutSession({ refreshToken: refresh2 });
const afterLogout = await auth.refreshSession({ refreshToken: refresh2, deviceId });
check('logout revokes the session', !afterLogout.ok, afterLogout.error);
const meAfterLogout = await auth.getAuthenticatedSession({
  authorizationHeader: `Bearer ${refreshed.payload?.access_token}`
});
check('access token dead after logout', !meAfterLogout.ok, meAfterLogout.error);

// 8. Rate limiting on /auth/device/start.
const results = [];
for (let i = 0; i < 8; i += 1) {
  results.push(await auth.startDeviceLogin({ ip: '10.0.0.9', platform: 'desktop', deviceId: `d-${i}` }));
}
check('start is rate limited per ip', results.some((r) => r.status === 429));

// 9. Privy access-token verification. Regression guard for the exact production
//    outage: the SDK helper takes the raw token string and returns snake_case
//    claims. Passing `{ access_token }` (or reading `claims.userId`) makes jose
//    reject the input and surfaces the generic "Failed to verify authentication
//    token", which broke every web approval.
step('9. Privy access-token verification');
const { generateKeyPair, exportSPKI, SignJWT } = await import('jose');
const { publicKey, privateKey } = await generateKeyPair('ES256', { extractable: true });
process.env.PRIVY_APP_ID = 'cl_probe';
process.env.PRIVY_APP_SECRET = 'probe-secret';
process.env.PRIVY_JWT_VERIFICATION_KEY = await exportSPKI(publicKey);
const probeJwt = await new SignJWT({ sid: 'ses_probe' })
  .setProtectedHeader({ alg: 'ES256', typ: 'JWT' })
  .setIssuer('privy.io')
  .setAudience('cl_probe')
  .setSubject('did:privy:probe')
  .setIssuedAt()
  .setExpirationTime('1h')
  .sign(privateKey);
const verified = await auth.verifyPrivyAccessToken(probeJwt);
check('valid Privy token verifies', verified.ok, verified.error);
check('subject read from snake_case user_id', verified.ok && verified.claims.userId === 'did:privy:probe');
check('wrong app id is rejected', !(await auth.verifyPrivyAccessToken(
  await new SignJWT({ sid: 'ses_probe' })
    .setProtectedHeader({ alg: 'ES256', typ: 'JWT' })
    .setIssuer('privy.io')
    .setAudience('cl_other')
    .setSubject('did:privy:probe')
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(privateKey)
)).ok);

// 10. Privy user normalization. Regression guard: `users()._get()` returns the
//     User object directly with snake_case fields, so reading `?.user` or
//     camelCase made every lookup return null -> "could not verify your account".
step('10. Privy user normalization');
const normalized = auth.normalizePrivyUser({
  id: 'did:privy:probe',
  linked_accounts: [
    { type: 'google_oauth', name: 'Probe Player' },
    { type: 'wallet', chain_type: 'ethereum', address: '0xAbC' },
    { type: 'wallet', chain_type: 'solana', address: 'So1ana', profile_picture_url: 'https://img.example/x.png' }
  ]
});
check('extracts ethereum wallet', normalized.walletAddress === '0xAbC');
check('extracts solana wallet', normalized.solanaAddress === 'So1ana');
check('extracts profile picture', normalized.profilePictureUrl === 'https://img.example/x.png');
check('keeps linked accounts for username derivation', normalized.linkedAccounts.length === 3);
check('null user normalizes to null', auth.normalizePrivyUser(null) === null);

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);

// The Firebase client holds an open connection, so exit explicitly instead of
// waiting for the event loop to drain.
process.exit(failures === 0 ? 0 : 1);