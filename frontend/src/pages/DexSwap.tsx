import React, { useState, ChangeEvent } from "react";
import { ethers } from "ethers";
import {
  useAccount,
  useConnect,
  useDisconnect,
  useBalance,
  useWalletClient,
} from "wagmi";
import { InjectedConnector } from "wagmi/connectors/injected";
import { Token } from "@uniswap/sdk-core";

// ------------------- CONSTANTS ----------------------
const RPC_URL = "https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY";

const provider = new ethers.JsonRpcProvider(RPC_URL);

// Uniswap V3 Quoter Contract
const QUOTER_ADDRESS = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";
const QUOTER_ABI = [
  {
    inputs: [
      { internalType: "address", name: "tokenIn", type: "address" },
      { internalType: "address", name: "tokenOut", type: "address" },
      { internalType: "uint24", name: "fee", type: "uint24" },
      { internalType: "uint256", name: "amountIn", type: "uint256" },
      { internalType: "uint160", name: "sqrtPriceLimitX96", type: "uint160" },
    ],
    name: "quoteExactInputSingle",
    outputs: [{ internalType: "uint256", name: "amountOut", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
];

// Example tokens (replace with real mainnet)
const WMON = new Token(
  1,
  "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A",
  18,
  "WMON",
  "World of Nads"
);

const USDC = new Token(
  1,
  "0x754704Bc059F8C67012fEd69BC8A327a5aafb603",
  6,
  "USDC",
  "USD Coin"
);

// Pool fee (0.3% = 3000)
const POOL_FEE = 3000;

// --------------------------------------------------------

const DexSwap: React.FC = () => {
  const [fromAmount, setFromAmount] = useState("");
  const [toAmount, setToAmount] = useState("");
  const [loading, setLoading] = useState(false);

  // Wallet hooks (wagmi)
  const { address, isConnected } = useAccount();
  const { connect } = useConnect({ connector: new InjectedConnector() });
  const { disconnect } = useDisconnect();
  const { data: walletClient } = useWalletClient();

  const fetchQuote = async (value: string) => {
    if (!value || isNaN(Number(value))) {
      setToAmount("");
      return;
    }

    try {
      setLoading(true);

      const quoter = new ethers.Contract(
        QUOTER_ADDRESS,
        QUOTER_ABI,
        provider
      );

      const amountIn = ethers.parseUnits(value, WMON.decimals);
      const quoted = await quoter.quoteExactInputSingle(
        WMON.address,
        USDC.address,
        POOL_FEE,
        amountIn,
        0
      );

      const formatted = ethers.formatUnits(quoted, USDC.decimals);
      setToAmount(Number(formatted).toFixed(6));
    } catch (err) {
      console.error("QUOTE FAILED:", err);
      setToAmount("");
    } finally {
      setLoading(false);
    }
  };

  const handleAmountChange = (e: ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setFromAmount(value);
    fetchQuote(value);
  };

  const handleSwap = async () => {
    if (!walletClient) return alert("Connect wallet first");

    alert(
      `Swap not implemented yet, but you would send:\n${fromAmount} WMON → ${toAmount} USDC`
    );
  };

  return (
    <div style={{ width: 400, margin: "30px auto", fontFamily: "Arial" }}>
      <h2>Dex Swap</h2>
      <p>WMON → USDC (Uniswap V3 Quoter)</p>

      <div style={{ marginBottom: 20 }}>
        <label>Amount (WMON)</label>
        <input
          style={{ width: "100%", padding: 8 }}
          type="number"
          placeholder="0.0"
          value={fromAmount}
          onChange={handleAmountChange}
        />
      </div>

      <div style={{ marginBottom: 20 }}>
        <label>Receive (USDC)</label>
        <input
          style={{ width: "100%", padding: 8 }}
          type="text"
          readOnly
          value={loading ? "..." : toAmount}
        />
      </div>

      {!isConnected ? (
        <button
          style={{ width: "100%", padding: 10 }}
          onClick={() => connect()}
        >
          Connect Wallet
        </button>
      ) : (
        <button
          style={{ width: "100%", padding: 10 }}
          onClick={handleSwap}
        >
          Swap
        </button>
      )}

      {isConnected && (
        <button
          onClick={() => disconnect()}
          style={{
            marginTop: 8,
            width: "100%",
            padding: 10,
            background: "#444",
            color: "white",
          }}
        >
          Disconnect ({address?.slice(0, 6)}…)
        </button>
      )}

      <p style={{ marginTop: 15, fontSize: 13 }}>
        {loading
          ? "Fetching live quote..."
          : toAmount
            ? `1 WMON ≈ ${toAmount} USDC`
            : "Enter amount"}
      </p>
    </div>
  );
};

export default DexSwap;
