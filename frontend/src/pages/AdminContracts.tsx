import React, { useEffect, useState } from "react";
import { ethers } from "ethers";
import "./AdminContracts.css";
import { showSuccessToast, showErrorToast } from "../components/ui/custom-toast";

const WITHDRAW_ABI = ["function withdraw() external"];
const RPC_URL = "https://testnet-rpc.monad.xyz";
const API_BASE = import.meta.env.VITE_ANALYTICS_API_URL || "";

function buildUrl(path: string) {
  if (!API_BASE) return path;
  return `${API_BASE}${path}`;
}

const CONTRACTS = [
  { label: "WONsXP", varName: "VITE_XP_TOKEN_ADDRESS" as const, desc: "Soulbound XP token" },
  { label: "WONsLootBox", varName: "VITE_LOOTBOX_ADDRESS" as const, desc: "Prize pool vault" },
  { label: "WONsMatchEngine", varName: "VITE_MATCH_ENGINE_ADDRESS" as const, desc: "Match settlement engine" },
  { label: "WONsSkins", varName: "VITE_SKINS_CONTRACT_ADDRESS" as const, desc: "NFT skin marketplace" },
];

const AdminContracts: React.FC = () => {
  const [balances, setBalances] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [withdrawing, setWithdrawing] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      try {
        const provider = new ethers.JsonRpcProvider(RPC_URL);
        const entries: Record<string, string> = {};
        for (const c of CONTRACTS) {
          const address = import.meta.env[c.varName] as string | undefined;
          if (address) {
            const bal = await provider.getBalance(address);
            entries[c.label] = ethers.formatEther(bal);
          }
        }
        setBalances(entries);
      } catch {
        setBalances({});
      } finally {
        setLoading(false);
      }
    };
    load();
    const interval = setInterval(load, 15000);
    return () => clearInterval(interval);
  }, []);

  const handleWithdraw = async (label: string, varName: string) => {
    setError(null);
    setSuccess(null);
    setWithdrawing(label);
    try {
      const address = import.meta.env[varName] as string | undefined;
      if (!address) throw new Error("Contract address not configured");

      const accessCode = sessionStorage.getItem("admin_access_code") || "";
      if (!accessCode) throw new Error("Admin access code not found. Please re-login.");

      const response = await fetch(buildUrl("/admin/contract-withdraw"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code: accessCode, contractAddress: address })
      });

      const data = await response.json();
      if (!data.ok) throw new Error(data.error || "Withdraw failed");

      const provider = new ethers.JsonRpcProvider(RPC_URL);
      const bal = await provider.getBalance(address);
      setBalances((prev) => ({ ...prev, [label]: ethers.formatEther(bal) }));
      const msg = `${label} — withdrawn successfully`;
      setSuccess(msg);
      showSuccessToast(msg);
    } catch (err: any) {
      const msg = err?.reason || err?.message || "Withdraw failed";
      setError(msg);
      showErrorToast(msg);
    } finally {
      setWithdrawing(null);
    }
  };

  return (
    <div className="admin-contracts">
      <div className="admin-contracts__header">
        <h1>Contract Management</h1>
        <p>View balances and withdraw accumulated MON from each contract.</p>
        {error ? <span className="admin-contracts__error">{error}</span> : null}
        {success ? <span className="admin-contracts__success">{success}</span> : null}
      </div>

      {loading ? (
        <p className="text-inline-muted">Loading balances...</p>
      ) : (
        <div className="admin-contracts__grid">
          {CONTRACTS.map((c) => {
            const address = import.meta.env[c.varName] as string | undefined;
            const bal = balances[c.label] ?? "—";
            const isWithdrawing = withdrawing === c.label;
            return (
              <div className="admin-contracts__item" key={c.label}>
                <div className="admin-contracts__item-header">
                  <span className="admin-contracts__label">{c.label}</span>
                  <span className="admin-contracts__desc">{c.desc}</span>
                </div>
                <span className="admin-contracts__address">
                  {address || "Not configured"}
                </span>
                <span className="admin-contracts__balance">{bal} MON</span>
                <button
                  className="admin-contracts__withdraw"
                  disabled={!address || isWithdrawing || Number(bal) <= 0}
                  onClick={() => handleWithdraw(c.label, c.varName)}
                >
                  {isWithdrawing ? "WITHDRAWING..." : "Withdraw"}
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default AdminContracts;
