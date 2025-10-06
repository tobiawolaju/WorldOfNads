import React, { useState, ChangeEvent } from "react";
import "./DexSwap.css";

const DexSwap: React.FC = () => {
  const [fromToken, setFromToken] = useState<string>("WON");
  const [toToken, setToToken] = useState<string>("USDC");
  const [fromAmount, setFromAmount] = useState<string>("");
  const [toAmount, setToAmount] = useState<string>("");

  // Dummy conversion rate
  const conversionRate: number = 2.32; // 1 WON = 2.32 USDC

  const handleSwapDirection = (): void => {
    setFromToken(toToken);
    setToToken(fromToken);
    setFromAmount("");
    setToAmount("");
  };

  const handleFromAmountChange = (e: ChangeEvent<HTMLInputElement>): void => {
    const value = e.target.value;
    setFromAmount(value);

    if (!value) {
      setToAmount("");
      return;
    }

    const numericValue = parseFloat(value);
    if (isNaN(numericValue)) {
      setToAmount("");
      return;
    }

    if (fromToken === "WON" && toToken === "USDC") {
      setToAmount((numericValue * conversionRate).toFixed(2));
    } else {
      setToAmount((numericValue / conversionRate).toFixed(2));
    }
  };

  const handleSwap = (): void => {
    const amountNum = parseFloat(fromAmount);
    if (!amountNum || amountNum <= 0) {
      alert("Enter a valid amount to swap");
      return;
    }

    alert(`Swapped ${fromAmount} ${fromToken} → ${toAmount} ${toToken}`);
  };

  return (
    <div className="swap-container">
      <div style={{ height: "60px" }}></div>

      <p className="swap-subtitle">
        Swap your WON tokens for USDC or vice versa
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
          <input type="number" value={toAmount} readOnly />
        </div>

        <button className="swap-btn" onClick={handleSwap}>
          Swap
        </button>
      </div>

      <p className="swap-note">
        Rate: 1 {fromToken} = {conversionRate} {toToken}
      </p>
    </div>
  );
};

export default DexSwap;
