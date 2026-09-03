import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { nodePolyfills } from "vite-plugin-node-polyfills";

export default defineConfig({
  plugins: [
    react(), 
    tailwindcss(),
    nodePolyfills({
      globals: {
        Buffer: true,
        global: true,
        process: true,
      },
    }),
  ],
  build: {
    outDir: "build",
    rollupOptions: {
      output: {
        manualChunks: {
          "three-vendor": ["three", "@react-three/fiber", "@react-three/drei"],
          "privy-vendor": ["@privy-io/react-auth"],
          "ethers-vendor": ["ethers", "viem"],
          "solana-vendor": ["@solana/web3.js", "@solana/wallet-adapter-react", "@solana/kit"],
          "ui-vendor": ["react-router-dom", "react-toastify", "recharts", "chart.js", "gsap"],
        },
      },
    },
  },
  server: {
    hmr: {
      overlay: false,
    },
  },
});
