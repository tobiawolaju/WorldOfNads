import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App.tsx";
import { initGoogleAnalytics } from "./lib/analyticsClient";

import { PrivyProvider } from "@privy-io/react-auth";
import { toSolanaWalletConnectors } from "@privy-io/react-auth/solana";

const monad = {
  id: 143,
  name: 'Monad',
  network: 'monad',
  nativeCurrency: {
    name: 'MON',
    symbol: 'MON',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ['https://rpc.monad.xyz'],
    },
    public: {
      http: ['https://rpc.monad.xyz'],
    },
  },
  blockExplorers: {
    default: {
      name: 'MonadExplorer',
      url: 'https://explorer.monad.xyz',
    },
  },
};

initGoogleAnalytics();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <PrivyProvider
      appId={import.meta.env.VITE_PRIVY_APP_ID!}
      config={{
        defaultChain: monad,
        supportedChains: [monad],
        embeddedWallets: {
          ethereum: {
            createOnLogin: "users-without-wallets",
          },
          solana: {
            createOnLogin: "users-without-wallets",
          },
        },
        appearance: { walletChainType: "ethereum-and-solana" },
        externalWallets: { solana: { connectors: toSolanaWalletConnectors() } },
      }}
    >
      <App />
    </PrivyProvider>
  </StrictMode>
);
