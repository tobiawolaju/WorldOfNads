import React, { useEffect, useRef } from "react";
import { useCreateWallet, usePrivy } from "@privy-io/react-auth";
import { getEmbeddedWallet } from "../lib/privyWallets";

// Privy's `createOnLogin` only guarantees an embedded wallet for users that
// have none, so an account that signed in with MetaMask / Phantom (an
// auth-only login wallet) could otherwise end up with no in-game wallet at
// all. The in-game wallet is always the Privy embedded one, so make sure it
// exists: balances, minting and payouts all read that address.
export const EnsureGameWallet: React.FC = () => {
  const { ready, authenticated, user } = usePrivy();
  const { createWallet } = useCreateWallet();
  const attemptedFor = useRef<string | null>(null);

  useEffect(() => {
    if (!ready || !authenticated || !user) return;
    if (getEmbeddedWallet(user, "ethereum")) return;
    // One attempt per account: if it fails, the next login retries instead of
    // hammering Privy every time the user object changes.
    if (attemptedFor.current === user.id) return;
    attemptedFor.current = user.id;
    createWallet().catch((error) => {
      // Another tab can win the race, and an account that already has a wallet
      // rejects a second creation. Neither is worth surfacing to the player.
      console.warn("Could not create the in-game wallet:", error);
    });
  }, [ready, authenticated, user, createWallet]);

  return null;
};
