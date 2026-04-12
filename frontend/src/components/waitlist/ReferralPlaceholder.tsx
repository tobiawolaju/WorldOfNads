import React from "react";
import { FaDiscord } from "react-icons/fa";
import "./ReferralPlaceholder.css";

type ReferralPlaceholderProps = {
  showAsPopup?: boolean;
  onClose?: () => void;
  data?: {
    position: number;
    refCode: string;
    referralCount: number;
    referredBy?: string;
  };
};

const ReferralPlaceholder: React.FC<ReferralPlaceholderProps> = ({ showAsPopup = false, onClose, data }) => {
  const referralLink = data?.refCode
    ? `https://worldofnads.xyz/waitlist?ref=${data.refCode}`
    : "https://worldofnads.xyz/waitlist";

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(referralLink);
    } catch {
      console.log("[waitlist] clipboard unavailable");
    }
  };

  const displayPosition = data?.position ? data.position.toLocaleString() : "---";
  const displayCount = data?.referralCount || 0;

  return (
    <article className={`tweet-card waitlist-referral-card ${showAsPopup ? "waitlist-referral-popup" : "reveal"}`.trim()}>
      {showAsPopup ? (
        <button className="waitlist-popup-close" type="button" onClick={onClose} aria-label="Close waitlist popup">
          ×
        </button>
      ) : null}

      <div className="waitlist-ref-content">
        <h2 className="waitlist-ref-title">You’re #{displayPosition} in line</h2>
        <p className="waitlist-ref-subtitle">
          {displayCount > 0
            ? `You've referred ${displayCount} people. Share your link to climb higher!`
            : "Invite your friends to skip the queue and get early access."}
        </p>

        {data?.referredBy && (
          <p className="waitlist-referred-by" style={{ fontSize: "12px", opacity: 0.7, marginTop: "4px" }}>
            Referred by: {data.referredBy}
          </p>
        )}

        <div className="waitlist-ref-link-row">
          <input className="waitlist-input" value={referralLink} readOnly aria-label="Referral link" />
          <button className="button waitlist-copy-button" type="button" onClick={copyLink} style={{ background: "#907cff", color: "#fff" }}>
            Copy Link
          </button>
        </div>

        <div className="waitlist-ref-rewards">
          <h3>Growth Tiers</h3>
          <div className="tier-item">
            <span className="tier-rank">Top 100</span>
            <span className="tier-desc">Guaranteed Alpha Access</span>
          </div>
          <div className="tier-item">
            <span className="tier-rank">Top 10</span>
            <span className="tier-desc">Early Token Rewards / OG Role</span>
          </div>
        </div>

        <div className="waitlist-popup-discord-section" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginTop: '20px' }}>
          <a
            href="https://discord.gg/z4SUdrKayb"
            target="_blank"
            rel="noopener noreferrer"
            className="discord-btn-fixed"
            title="Join Discord"
            style={{ position: 'relative', margin: '0 auto 10px auto' }}
          >
            <FaDiscord size={28} />
          </a>
          <p className="waitlist-discord-note">Join our discord to stay in the loop</p>
        </div>
      </div>
    </article>
  );
};

export default ReferralPlaceholder;
