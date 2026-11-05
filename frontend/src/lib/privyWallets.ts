/**
 * Wallet helpers for Privy accounts.
 *
 * Signing in with a wallet (SIWE / SIWS) is an *authentication* method: the
 * player proves who they are with MetaMask, Phantom, Coinbase Wallet, ... but
 * that address is never the in-game wallet. Only wallets Privy itself creates
 * for the account are the player's game wallet, so every read of "the player's
 * wallet" goes through the helpers below.
 *
 * Privy marks those wallets with `walletClientType === "privy"` and
 * `connectorType === "embedded"`. Both shapes are accepted here because the
 * linked account (`user.linkedAccounts`) and the connected wallet
 * (`useWallets().wallets`) are not identical:
 *
 *   linked account:  { type: "wallet", chainType: "ethereum", ... }
 *   connected wallet:{ type: "ethereum", chainId: "eip155:10143", ... }
 *
 * Note the connected wallet has **no** `chainType` — reading `wallet.chainType`
 * there silently matches nothing, which is why the chain helpers below accept
 * either field.
 */

export type PrivyWalletAccount = {
  type?: string;
  chainType?: string;
  chainId?: string;
  walletClientType?: string;
  connectorType?: string;
  walletIndex?: number;
  address?: string;
};

export type PrivyUserLike = {
  linkedAccounts?: PrivyWalletAccount[] | null;
};

export type WalletChainType = "ethereum" | "solana";

/** `walletClientType` values Privy uses for wallets it creates and custodies. */
const EMBEDDED_WALLET_CLIENTS: readonly string[] = ["privy", "privy-v2"];

/** `connectorType` Privy uses for the same wallets. */
const EMBEDDED_CONNECTOR_TYPE = "embedded";

/**
 * True when the account is a Privy embedded wallet, given either the linked
 * account shape (`user.linkedAccounts`) or the connected wallet shape
 * (`useWallets().wallets`). Wallets used to sign in never match.
 */
export function isEmbeddedWalletClient(account?: PrivyWalletAccount | null): boolean {
  if (!account) return false;
  if (account.connectorType === EMBEDDED_CONNECTOR_TYPE) return true;
  return EMBEDDED_WALLET_CLIENTS.includes(String(account.walletClientType ?? ""));
}

/** True for a Privy embedded wallet in `user.linkedAccounts`. */
export function isEmbeddedWallet(account?: PrivyWalletAccount | null): boolean {
  return account?.type === "wallet" && isEmbeddedWalletClient(account);
}

/**
 * Chain of a wallet in either shape: linked accounts carry `chainType`, while
 * `useWallets()` wallets carry `type` (and a CAIP-2 `chainId`).
 */
export function getWalletChainType(wallet?: PrivyWalletAccount | null): WalletChainType | null {
  if (!wallet) return null;

  const chain = wallet.chainType ?? wallet.type;
  if (chain === "ethereum" || chain === "solana") return chain;

  // CAIP-2 identifiers, e.g. "eip155:10143" / "solana:mainnet".
  const caip2 = wallet.chainId ?? "";
  if (caip2.startsWith("eip155:")) return "ethereum";
  if (caip2.startsWith("solana:")) return "solana";

  return null;
}

/** The account's Privy embedded wallet on `chainType`, or `null`. */
export function getEmbeddedWallet(
  user: PrivyUserLike | null | undefined,
  chainType: WalletChainType
): PrivyWalletAccount | null {
  const accounts = user?.linkedAccounts;
  if (!accounts || accounts.length === 0) return null;

  // Accounts can hold several HD embedded wallets; the primary one (lowest
  // index) is the one Privy connects and the one the player sees.
  const matches = accounts
    .filter((account) => isEmbeddedWallet(account) && getWalletChainType(account) === chainType)
    .sort((a, b) => (a.walletIndex ?? 0) - (b.walletIndex ?? 0));

  return matches.length > 0 ? matches[0] : null;
}

/**
 * The connected embedded wallet from `useWallets()`, optionally narrowed to a
 * chain and/or address, or `null`. Prefer this over hand-rolled `.find(...)`
 * filters: it understands the connected-wallet shape and ignores login wallets.
 */
export function findConnectedEmbeddedWallet<T extends PrivyWalletAccount>(
  wallets: readonly T[] | null | undefined,
  options: { chainType?: WalletChainType; address?: string } = {}
): T | null {
  if (!wallets || wallets.length === 0) return null;

  const { chainType, address } = options;
  const wantedAddress = address ? address.toLowerCase() : "";

  const match = wallets.find((wallet) => {
    if (!isEmbeddedWalletClient(wallet)) return false;
    if (chainType && getWalletChainType(wallet) !== chainType) return false;
    if (wantedAddress && String(wallet.address ?? "").toLowerCase() !== wantedAddress) {
      return false;
    }
    return true;
  });

  return match ?? null;
}
