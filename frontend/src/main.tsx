import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App.tsx";
import { initGoogleAnalytics } from "./lib/analyticsClient";
import { initInstallPrompt } from "./lib/installPrompt";
import { initDeviceProfile, requestPersistentStorage } from "./lib/deviceProfile";

import { PrivyProvider } from "@privy-io/react-auth";
import { toSolanaWalletConnectors } from "@privy-io/react-auth/solana";

import { useEffect, useState } from "react";

const blockBrowserZoom = () => {
  const handleWheel = (event: WheelEvent) => {
    if (event.ctrlKey || event.metaKey) {
      event.preventDefault();
    }
  };

  const handleKeyDown = (event: KeyboardEvent) => {
    if (!event.ctrlKey && !event.metaKey) {
      return;
    }

    const blockedKeys = ["+", "-", "=", "0"];
    if (blockedKeys.includes(event.key)) {
      event.preventDefault();
    }
  };

  window.addEventListener("wheel", handleWheel, { passive: false });
  window.addEventListener("keydown", handleKeyDown);
};

const monadTestnet = {
  id: 10143,
  name: 'Monad Testnet',
  network: 'monad-testnet',
  nativeCurrency: {
    name: 'MON',
    symbol: 'MON',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ['https://testnet-rpc.monad.xyz'],
    },
    public: {
      http: ['https://testnet-rpc.monad.xyz'],
    },
  },
  blockExplorers: {
    default: {
      name: 'MonadTestnetExplorer',
      url: 'https://testnet.monadexplorer.com',
    },
  },
};

// Google Analytics injects a third-party script, so it is not on the critical
// path: wait for the first idle slot instead of competing with the app bundle.
// `safeGtag` drops events until init has run, and the backend trackers are
// independent of it, so nothing is lost except GA events in that first moment.
const whenIdle = (fn: () => void) => {
  const idle = (window as any).requestIdleCallback as
    | ((cb: () => void, opts?: { timeout: number }) => number)
    | undefined;
  if (idle) idle(fn, { timeout: 3000 });
  else window.setTimeout(fn, 1500);
};

whenIdle(initGoogleAnalytics);
blockBrowserZoom();
initInstallPrompt();

// Reads deviceMemory / hardwareConcurrency / DPR once and stamps the tier on
// <html data-perf="..."> so the 3D scene and CSS can size themselves to the
// device. Must run before the first render, hence the top-level call.
initDeviceProfile();

// Ask the browser to keep our caches. Chromium grants this silently for an
// installed PWA; without it, Android evicts the service-worker caches (and the
// artwork in them) whenever storage gets tight, which is exactly the tablet /
// phone case we care about. Re-asked after install because the grant is tied to
// the installed app, not to the browser tab that requested it.
requestPersistentStorage().catch(() => {});
window.addEventListener("appinstalled", () => {
  requestPersistentStorage().catch(() => {});
});

// Register the service worker that makes the site installable and keeps the
// app shell, build output and artwork on disk.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/sw.js", { updateViaCache: "none" })
      .catch(() => {
        // Installing from the browser menu still works if this fails.
      });
  });
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <PrivyProviderWrapper />
  </StrictMode>
);

function PrivyProviderWrapper() {
  const [theme, setTheme] = useState<"light" | "dark">(() => {
    if (typeof window === "undefined") return "light";
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  });

  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = (e: MediaQueryListEvent) => setTheme(e.matches ? "dark" : "light");
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  return (
    <PrivyProvider
      appId={import.meta.env.VITE_PRIVY_APP_ID!}
      config={{
        defaultChain: monadTestnet,
        supportedChains: [monadTestnet],
        embeddedWallets: {
          ethereum: {
            createOnLogin: "users-without-wallets",
          },
          solana: {
            createOnLogin: "users-without-wallets",
          },
        },
        appearance: { walletChainType: "ethereum-and-solana", theme },
        externalWallets: { solana: { connectors: toSolanaWalletConnectors() } },
      }}
    >
      <App />
    </PrivyProvider>
  );
}
