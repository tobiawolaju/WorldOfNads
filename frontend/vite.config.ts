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
          if (!id.includes("node_modules")) return undefined;
          // React has to be claimed BEFORE the three rule below. @react-three/fiber
          // imports react-dom, so Rollup used to park react-dom inside
          // three-vendor - which put that whole chunk (three.js + drei, ~300 KB
          // brotli) into the entry's static graph. The landing page then
          // downloaded the 3D stack for a page that has no 3D at all.
          if (/[\\/]node_modules[\\/](react|react-dom|scheduler)[\\/]/.test(id)) {
            return "react-vendor";
          }
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
