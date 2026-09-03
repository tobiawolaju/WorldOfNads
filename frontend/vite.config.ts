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
        manualChunks(id) {
          if (id.includes("node_modules/three/") || id.includes("node_modules/@react-three")) {
            return "three-vendor";
          }
          if (id.includes("node_modules/@privy-io") || id.includes("node_modules/@privy-")) {
            return "privy-vendor";
          }
          if (id.includes("node_modules/ethers/") || id.includes("node_modules/viem/")) {
            return "ethers-vendor";
          }
          if (id.includes("node_modules/@solana/") || id.includes("node_modules/bs58/")) {
            return "solana-vendor";
          }
          if (id.includes("node_modules/recharts") || id.includes("node_modules/chart.js") || id.includes("node_modules/d3-")) {
            return "charts-vendor";
          }
          if (id.includes("node_modules/gsap/")) {
            return "gsap-vendor";
          }
          return undefined;
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
