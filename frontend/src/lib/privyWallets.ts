/**
 * Wallet helpers for Privy accounts.
 *
 * Signing in with a wallet (SIWE / SIWS) is an *authentication* method: the
 * player proves who they are with MetaMask, Phantom, Coinbase Wallet, ... but
 * that address is never the in-game wallet. Only wallets Privy itself creates
 * for the account (embedded wallets, `walletClientType === "privy"`) are the
 * player's game wallet, so every read of "the player's wallet" goes through
 * the helpers below.
 */

export type PrivyWalletAccount = {
  type?: string;
  chainType?: string;
  walletClientType?: string;
  address?: string;
};

export type PrivyUserLike = {
  linkedAccounts?: PrivyWalletAccount[] | null;
};

/** `walletClientType` Privy uses for wallets it creates and custodies. */
const EMBEDDED_WALLET_CLIENT = "privy";

export function isEmbeddedWallet(account?: PrivyWalletAccount | null): boolean {
  return (
    account?.type === "wallet" &&
    account?.walletClientType === EMBEDDED_WALLET_CLIENT
  );
}

/** The account's Privy embedded wallet on `chainType`, or `null`. */
export function getEmbeddedWallet(
  user: PrivyUserLike | null | undefined,
  chainType: "ethereum" | "solana"
): PrivyWalletAccount | null {
  const account = user?.linkedAccounts?.find(
    (acc) => isEmbeddedWallet(acc) && acc.chainType === chainType
  );
  return account || null;
}

/**
 * Options for `login()` that open Privy's modal directly on the wallet flow
 * (Ethereum SIWE + Solana SIWS), so wallet sign-in does not depend on the
 * social methods being configured.
 *
 * Requires the "Wallet" login method to be enabled in the Privy dashboard.
 * Note the spelling differs from `appearance.walletChainType` in the provider
 * config: the modal option is `ethereum-or-solana`.
 */
export const WALLET_LOGIN_OPTIONS = {
  loginMethods: ["wallet"] as Array<"wallet">,
  walletChainType: "ethereum-or-solana" as "ethereum-or-solana",
};
