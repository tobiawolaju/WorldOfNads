import React, { useEffect, useState } from "react";
import AdminAnalytics from "./AdminAnalytics";
import AdminUsers from "./AdminUsers";
import AdminContracts from "./AdminContracts";
import AdminSkins from "./AdminSkins";
import "./AdminDashboard.css";

const API_BASE = import.meta.env.VITE_ANALYTICS_API_URL || "";
function buildUrl(path: string) {
  if (!API_BASE) return path;
  return `${API_BASE}${path}`;
}

type Tab = "analytics" | "users" | "contracts" | "skins";

const TABS: { key: Tab; label: string }[] = [
  { key: "analytics", label: "Analytics" },
  { key: "users", label: "Users" },
  { key: "contracts", label: "Contracts" },
  { key: "skins", label: "Skins" },
];

const AdminDashboard: React.FC = () => {
  const [activeTab, setActiveTab] = useState<Tab>("analytics");
  const [accessCode, setAccessCode] = useState("");
  const [accessGranted, setAccessGranted] = useState(false);
  const [accessError, setAccessError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const stored = sessionStorage.getItem("admin_dashboard_access");
    if (stored === "granted") {
      setAccessGranted(true);
    }
  }, []);

  const verifyAccess = async () => {
    setLoading(true);
    setAccessError("");
    try {
      const response = await fetch(buildUrl("/admin/verify-access"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code: accessCode })
      });
      if (!response.ok) throw new Error("Invalid code");
      sessionStorage.setItem("admin_dashboard_access", "granted");
      sessionStorage.setItem("admin_access_code", accessCode);
      setAccessGranted(true);
    } catch {
      setAccessError("Invalid access code.");
    } finally {
      setLoading(false);
    }
  };

  if (!accessGranted) {
    return (
      <div className="admin-dashboard">
        <div className="admin-dashboard__header">
          <h1>Admin Dashboard</h1>
          <p>Enter your access code to continue.</p>
        </div>
        <div className="analytics-auth__card" style={{ margin: "0 auto" }}>
          <h1>Admin Access</h1>
          <p>Enter your admin access code to manage World of Nads.</p>
          <input
            type="password"
            value={accessCode}
            onChange={(event) => setAccessCode(event.target.value)}
            placeholder="Access code"
          />
          <button onClick={verifyAccess} disabled={loading || !accessCode.trim()}>
            {loading ? "Checking..." : "Unlock"}
          </button>
          {accessError ? <span className="analytics-auth__error">{accessError}</span> : null}
        </div>
      </div>
    );
  }

  return (
    <div className="admin-dashboard">
      <div className="admin-dashboard__header">
        <h1>Admin Dashboard</h1>
        <p>Manage World of Nads — contracts, users, skins, and analytics.</p>
      </div>

      <div className="admin-dashboard__tabs">
        {TABS.map((tab) => (
          <div
            key={tab.key}
            className={`admin-dashboard__tab${activeTab === tab.key ? " active" : ""}`}
            onClick={() => setActiveTab(tab.key)}
          >
            <span>{tab.label}</span>
          </div>
        ))}
      </div>

      <div className="admin-dashboard__panel">
        {activeTab === "analytics" && <AdminAnalytics />}
        {activeTab === "users" && <AdminUsers />}
        {activeTab === "contracts" && <AdminContracts />}
        {activeTab === "skins" && <AdminSkins />}
      </div>
    </div>
  );
};

export default AdminDashboard;
