import React, { useState, ChangeEvent, useEffect } from "react";
import { ethers } from "ethers";
import { Token } from "@uniswap/sdk-core";
import { Quoter } from "@uniswap/v3-sdk"; // simplified import
import "./DexSwap.css";

// Example: mainnet provider
const provider = new ethers.JsonRpcProvider(
  "https://eth-mainnet.alchemyapi.io/v2/YOUR_ALCHEMY_KEY"
);

// Uniswap V3 Quoter contract
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

// Example tokens
const WON = new Token(1, "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A", 18, "WON", "World of Nads");
const USDC = new Token(
  1,
  "0x754704Bc059F8C67012fEd69BC8A327a5aafb603",
  6,
  "USDC",
  "USD Coin"
);

const DexSwap: React.FC = () => {
  const [fromToken, setFromToken] = useState<string>("WON");
  const [toToken, setToToken] = useState<string>("USDC");
  const [fromAmount, setFromAmount] = useState<string>("");
  const [toAmount, setToAmount] = useState<string>("");
  const [loading, setLoading] = useState<boolean>(false);

  const handleSwapDirection = () => {
    setFromToken(toToken);
    setToToken(fromToken);
    setFromAmount("");
    setToAmount("");
  };

  const fetchQuote = async (amount: string) => {
    if (!amount || isNaN(Number(amount))) {
      setToAmount("");
      return;
    }

    setLoading(true);
    try {
      const quoterContract = new ethers.Contract(
        QUOTER_ADDRESS,
        QUOTER_ABI,
        provider
      );

      const amountIn = ethers.parseUnits(amount, WON.decimals); // 18 decimals

      const amountOut = await quoterContract.quoteExactInputSingle(
        WON.address,
        USDC.address,
        3000, // pool fee 0.3%
        amountIn,
        0
      );

      const formatted = ethers.formatUnits(amountOut, USDC.decimals);
      setToAmount(Number(formatted).toFixed(4));
    } catch (err) {
      console.error(err);
      setToAmount("");
    }
    setLoading(false);
  };

  const handleFromAmountChange = (e: ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setFromAmount(value);
    fetchQuote(value);
  };

  const handleSelectWallet = () => {
    alert("Wallet selection modal would open here.");
  };

  const handleSwap = () => {
    alert(
      `Swap logic not implemented yet. You entered ${fromAmount} ${fromToken} → ${toAmount} ${toToken}`
    );
  };

  return (
    <div className="swap-container">
      <div style={{ height: "60px" }}></div>

      <p className="swap-subtitle">
        Instantly swap WON for USDC — your bridge between the World of Nads and
        the wider crypto world.
      </p>

      <div className="swap-card">
        <div className="swap-row">
          <label>{fromToken}</label>
          <input
            type="number"
            placeholder="0.0"
            value={fromAmount}
            onChange={handleFromAmountChange}
          />
        </div>

        <div className="swap-toggle" onClick={handleSwapDirection}>
          ⇅
        </div>

        <div className="swap-row">
          <label>{toToken}</label>
          <input type="number" value={loading ? "…" : toAmount} readOnly />
        </div>

        <button className="select-wallet-btn" onClick={handleSelectWallet}>
          Select Wallet
        </button>

        <button className="swap-btn" onClick={handleSwap}>
          Swap
        </button>
      </div>

      <p className="swap-note">
        {loading
          ? "Fetching live rate..."
          : `1 ${fromToken} ≈ ${toAmount || "–"} ${toToken}`}
      </p>
    </div>
  );
};

export default DexSwap;
