// Native mint support: lets the Godot client trigger an on-chain mintSkin that
// WONsSkins can only accept from the player's own wallet (it mints to
// msg.sender and gates on msg.sender's XP).
//
// The key arrives once via POST /api/wallet/link — authenticated, over HTTPS —
// is encrypted at rest with WALLET_ENC_KEY, and is never returned to any
// client again. The server can sign as the linked wallet; that custody is the
// explicit trade for in-app mints (testnet scope).
import { createCipheriv, createDecipheriv, createHash, randomBytes } from "crypto";
import { ethers } from "ethers";
import { getSkin, getWalletKey, saveWalletKey } from "./firebaseClient.js";
import { mintSkinWithKey } from "./contractClient.js";

// One mint at a time per account: a double-tap or retry loop must not queue a
// second purchase while the first tx is still pending.
const MINT_COOLDOWN_MS = 15_000;
const mintLastAttempt = new Map();

function encryptionKey() {
    const secret = process.env.WALLET_ENC_KEY;
    if (!secret) return null;
    // Domain-separated so this key can never collide with the session HMAC key
    // even if the same secret is reused for both.
    return createHash("sha256").update(`wons:wallet-enc:v1:${secret}`).digest();
}

function encryptPrivateKey(key, plain) {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", key, iv);
    const ct = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
    return {
        iv: iv.toString("base64"),
        tag: cipher.getAuthTag().toString("base64"),
        ct: ct.toString("base64")
    };
}

function decryptPrivateKey(record) {
    const key = encryptionKey();
    if (!key || !record?.iv || !record?.tag || !record?.ct) return null;
    try {
        const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(record.iv, "base64"));
        decipher.setAuthTag(Buffer.from(record.tag, "base64"));
        return Buffer.concat([
            decipher.update(Buffer.from(record.ct, "base64")),
            decipher.final()
        ]).toString("utf8");
    } catch {
        return null;
    }
}

/**
 * Stores the player's signing key (encrypted) after proving it belongs to the
 * wallet this session logged in with. Relinking simply overwrites the blob.
 */
export async function linkWalletKey({ username, walletAddress, privateKey } = {}) {
    if (!username) return { ok: false, status: 401, error: "not_authenticated" };
    if (!walletAddress) return { ok: false, status: 400, error: "no_wallet_on_account" };
    if (!encryptionKey()) return { ok: false, status: 500, error: "wallet_enc_not_configured" };

    const raw = typeof privateKey === "string" ? privateKey.trim() : "";
    if (!raw) return { ok: false, status: 400, error: "private_key_required" };
    const normalized = raw.startsWith("0x") || raw.startsWith("0X") ? raw : `0x${raw}`;

    let address;
    try {
        address = new ethers.Wallet(normalized).address;
    } catch {
        return { ok: false, status: 400, error: "invalid_private_key" };
    }
    if (address.toLowerCase() !== String(walletAddress).toLowerCase()) {
        // Refuse keys that belong to somebody else: the mint endpoint would
        // otherwise let an account purchase skins onto an unrelated wallet.
        return { ok: false, status: 400, error: "key_wallet_mismatch" };
    }

    const { iv, tag, ct } = encryptPrivateKey(encryptionKey(), normalized);
    await saveWalletKey(username, {
        v: 1,
        iv,
        tag,
        ct,
        address,
        created_at: new Date().toISOString()
    });
    console.log(`[Wallet] linked signing key for ${username} (${address})`);
    return { ok: true, status: 200, payload: { address } };
}

/**
 * Purchases `amount` editions of an on-chain skin for the authenticated
 * account, signed with the linked key. The player's wallet pays the mint price
 * and gas, exactly like the web dashboard flow.
 */
export async function mintSkinForAccount({ username, walletAddress, skinId, amount } = {}) {
    if (!username) return { ok: false, status: 401, error: "not_authenticated" };
    if (!encryptionKey()) return { ok: false, status: 500, error: "wallet_enc_not_configured" };

    const record = await getWalletKey(username);
    if (!record || !record.v || !record.ct) {
        return { ok: false, status: 404, error: "wallet_not_linked" };
    }

    const now = Date.now();
    if (now - (mintLastAttempt.get(username) || 0) < MINT_COOLDOWN_MS) {
        return { ok: false, status: 429, error: "mint_cooldown" };
    }

    const privateKey = decryptPrivateKey(record);
    if (!privateKey) return { ok: false, status: 500, error: "wallet_decrypt_failed" };

    // The linked key must still belong to the session's wallet, even if the
    // profile address changed after linking.
    let derivedAddress;
    try {
        derivedAddress = new ethers.Wallet(privateKey).address;
    } catch {
        return { ok: false, status: 500, error: "wallet_decrypt_failed" };
    }
    if (walletAddress && derivedAddress.toLowerCase() !== String(walletAddress).toLowerCase()) {
        return { ok: false, status: 403, error: "key_wallet_mismatch" };
    }

    // The client sends the store item id; the Firebase skin doc decides whether
    // that item maps to an on-chain skin at all.
    const skin = await getSkin(String(skinId ?? "").trim());
    const onChainId = Number(skin?.onChainId ?? 0);
    if (!skin || !Number.isInteger(onChainId) || onChainId <= 0) {
        return { ok: false, status: 400, error: "not_on_chain" };
    }

    const qty = Math.max(1, Math.min(5, Math.floor(Number(amount) || 1)));

    mintLastAttempt.set(username, now);
    const result = await mintSkinWithKey(privateKey, onChainId, qty);
    if (!result.success) {
        const expected = ["skin_not_found", "supply_exhausted", "insufficient_xp", "mint_failed"];
        return {
            ok: false,
            status: expected.includes(result.error) ? 400 : 500,
            error: result.error,
            payload: { detail: result.detail || null }
        };
    }
    console.log(`[Wallet] minted skin ${onChainId} x${qty} for ${username}: ${result.txHash}`);
    return {
        ok: true,
        status: 200,
        payload: {
            tx_hash: result.txHash,
            block_number: result.blockNumber,
            on_chain_id: onChainId,
            amount: qty
        }
    };
}
