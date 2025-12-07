import React, { useState, ChangeEvent } from "react";
import { ethers } from "ethers";
import "./DexSwap.css";

// Dummy rate for now:
// 1 WMON = 0.42 USDC
const DUMMY_RATE = 0.42;

const DexSwap: React.FC = () => {
  const [fromToken, setFromToken] = useState<string>("WMON");
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

    // simple dummy quote: multiply by dummy rate
    const out = Number(amount) * DUMMY_RATE;

    setTimeout(() => {
      setToAmount(out.toFixed(4));
      setLoading(false);
    }, 300); // fake network delay
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
        Instantly swap WMON for USDC — your bridge between the World of Nads and
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
          ? "Fetching rate..."
          : `1 ${fromToken} ≈ ${DUMMY_RATE} ${toToken}`}
      </p>
    </div>
  );
};

export default DexSwap;
