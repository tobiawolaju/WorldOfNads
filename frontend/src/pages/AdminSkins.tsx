import React, { useEffect, useState } from "react";
import { ethers } from "ethers";
import "./AdminSkins.css";
import { showSuccessToast, showErrorToast } from "../components/ui/custom-toast";

const RPC_URL = "https://testnet-rpc.monad.xyz";
const API_BASE = import.meta.env.VITE_ANALYTICS_API_URL || "";

function buildUrl(path: string) {
  if (!API_BASE) return path;
  return `${API_BASE}${path}`;
}

const SKINS_ABI = [
  "function skins(uint256) view returns (uint256 maxSupply, uint256 minted, uint256 mintPrice, uint256 requiredXP, uint8 tier, bool exists)",
  "function nextSkinId() view returns (uint256)",
  "function uri(uint256) view returns (string)",
];

const TIERS = ["Common", "Rare", "Epic", "Legendary"] as const;

type SkinData = {
  id: number;
  maxSupply: number;
  minted: number;
  mintPrice: string;
  requiredXP: number;
  tier: number;
  exists: boolean;
  uri: string;
};

const AdminSkins: React.FC = () => {
  const [skins, setSkins] = useState<SkinData[]>([]);
  const [skinsLoading, setSkinsLoading] = useState(true);

  const [maxSupply, setMaxSupply] = useState("100");
  const [mintPrice, setMintPrice] = useState("0.1");
  const [requiredXP, setRequiredXP] = useState("0");
  const [tier, setTier] = useState(0);
  const [uri, setUri] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const loadSkins = async () => {
    try {
      const provider = new ethers.JsonRpcProvider(RPC_URL);
      const address = import.meta.env.VITE_SKINS_CONTRACT_ADDRESS as string | undefined;
      if (!address) return;
      const contract = new ethers.Contract(address, SKINS_ABI, provider);
      const nextId = Number(await contract.nextSkinId());
      const results: SkinData[] = [];
      for (let i = 1; i < nextId; i++) {
        const data = await contract.skins(i);
        const skinUri = await contract.uri(i);
        results.push({
          id: i,
          maxSupply: Number(data.maxSupply),
          minted: Number(data.minted),
          mintPrice: ethers.formatEther(data.mintPrice),
          requiredXP: Number(data.requiredXP),
          tier: Number(data.tier),
          exists: data.exists,
          uri: skinUri,
        });
      }
      setSkins(results);
    } catch (err) {
      console.error("Failed to load skins", err);
    } finally {
      setSkinsLoading(false);
    }
  };

  useEffect(() => {
    loadSkins();
  }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    setCreating(true);
    try {
      const accessCode = sessionStorage.getItem("admin_access_code") || "";
      if (!accessCode) throw new Error("Admin access code not found. Please re-login.");

      const response = await fetch(buildUrl("/admin/create-skin"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          code: accessCode,
          maxSupply: Number(maxSupply),
          mintPrice,
          requiredXP: Number(requiredXP),
          tier,
          uri,
        }),
      });

      const data = await response.json();
      if (!data.ok) throw new Error(data.error || "Failed to create skin");

      const msg = `Skin created! Transaction: ${(data.txHash || "").slice(0, 10)}...`;
      setSuccess(msg);
      showSuccessToast(msg);
      setMaxSupply("100");
      setMintPrice("0.1");
      setRequiredXP("0");
      setTier(0);
      setUri("");
      await loadSkins();
    } catch (err: any) {
      const msg = err?.reason || err?.message || "Failed to create skin";
      setError(msg);
      showErrorToast(msg);
    } finally {
      setCreating(false);
    }
  };

  return (
    <div className="admin-skins">
      <div className="admin-skins__header">
        <h1>Skin Management</h1>
        <p>Create new NFT skins and view existing ones.</p>
        {error ? <span className="admin-skins__error">{error}</span> : null}
        {success ? <span className="admin-skins__success">{success}</span> : null}
      </div>

      <div className="admin-skins__form-card">
        <h2>Create New Skin</h2>
        <form className="admin-skins__form" onSubmit={handleCreate}>
          <label>
            Max Supply
            <input type="number" min="1" value={maxSupply} onChange={(e) => setMaxSupply(e.target.value)} required />
          </label>
          <label>
            Mint Price (MON)
            <input type="number" min="0" step="0.001" value={mintPrice} onChange={(e) => setMintPrice(e.target.value)} required />
          </label>
          <label>
            Required XP
            <input type="number" min="0" value={requiredXP} onChange={(e) => setRequiredXP(e.target.value)} required />
          </label>
          <label>
            Tier
            <select value={tier} onChange={(e) => setTier(Number(e.target.value))}>
              {TIERS.map((t, i) => (
                <option key={i} value={i}>{t}</option>
              ))}
            </select>
          </label>
          <label>
            Metadata URI
            <input type="text" value={uri} onChange={(e) => setUri(e.target.value)} placeholder="https://..." />
          </label>
          <button type="submit" className="admin-skins__create-btn" disabled={creating}>
            {creating ? "Creating..." : "Create Skin"}
          </button>
        </form>
      </div>

      <div className="admin-skins__list">
        <h2>Existing Skins</h2>
        {skinsLoading ? (
          <p className="text-inline-muted">Loading skins...</p>
        ) : skins.length === 0 ? (
          <p className="text-inline-muted">No skins found.</p>
        ) : (
          <div className="admin-skins__table">
            <div className="admin-skins__row admin-skins__row--head">
              <span>ID</span>
              <span>Tier</span>
              <span>Supply</span>
              <span>Price</span>
              <span>XP Req</span>
              <span>URI</span>
            </div>
            {skins.map((s) => (
              <div className="admin-skins__row" key={s.id}>
                <span>{s.id}</span>
                <span className={`admin-skins__tier tier--${TIERS[s.tier].toLowerCase()}`}>{TIERS[s.tier]}</span>
                <span>{s.minted}/{s.maxSupply}</span>
                <span>{s.mintPrice} MON</span>
                <span>{s.requiredXP}</span>
                <span className="admin-skins__uri" title={s.uri}>{s.uri.slice(0, 30)}...</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default AdminSkins;
