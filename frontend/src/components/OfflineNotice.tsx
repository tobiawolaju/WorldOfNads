import React, { useEffect, useState } from "react";
import "./OfflineNotice.css";

export const OfflineNotice: React.FC = () => {
  const [isOffline, setIsOffline] = useState(() => (typeof navigator !== "undefined" ? !navigator.onLine : false));
  const [showRestored, setShowRestored] = useState(false);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const handleOffline = () => {
      setShowRestored(false);
      setIsOffline(true);
    };

    const handleOnline = () => {
      setIsOffline(false);
      setShowRestored(true);
      const timer = setTimeout(() => {
        setShowRestored(false);
      }, 3000);
      return () => clearTimeout(timer);
    };

    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);

    return () => {
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener("online", handleOnline);
    };
  }, []);

  const handleManualCheck = async () => {
    setChecking(true);
    if (!navigator.onLine) {
      setTimeout(() => setChecking(false), 500);
      return;
    }

    try {
      const res = await fetch("/manifest.json?t=" + Date.now(), { method: "HEAD", cache: "no-store" });
      if (res.ok) {
        setIsOffline(false);
        setShowRestored(true);
        setTimeout(() => setShowRestored(false), 3000);
      }
    } catch {
      setIsOffline(true);
    } finally {
      setChecking(false);
    }
  };

  if (!isOffline && !showRestored) return null;

  return (
    <div
      className={`offline-notice-bar ${showRestored ? "is-restored" : ""}`}
      role="status"
      aria-live="polite"
    >
      <div className={`offline-dot ${showRestored ? "is-green" : ""}`} />
      <span className="offline-text">
        {showRestored
          ? "Signal Restored • Back in the arena"
          : "Signal Lost • Offline"}
      </span>
      {isOffline && (
        <button
          type="button"
          className="offline-btn"
          onClick={handleManualCheck}
          disabled={checking}
        >
          <span>{checking ? "CHECKING..." : "RETRY"}</span>
        </button>
      )}
    </div>
  );
};

export default OfflineNotice;
