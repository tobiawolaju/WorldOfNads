import React from "react";
import { FaDiscord } from "react-icons/fa";
import "./ReferralPlaceholder.css";
import { showSuccessToast, showErrorToast } from "../ui/custom-toast";

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
      showSuccessToast("Referral link copied!");
    } catch {
      showErrorToast("Failed to copy referral link.");
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
          <button className="button waitlist-copy-button bg-inline-accent text-inline-cta" type="button" onClick={copyLink}>
            Copy Link
          </button>
        </div>

        <div className="waitlist-ref-rewards">
          <div className="tier-item">
            <span className="tier-desc">
              You have been added to the waitlist for World of Nads Early Access. We will notify you when it's your turn to drop in.
              <br /><br />
              Expected wait: shorter than spotting the chicken.
              <br />
              We'll email you at <span className="text-inline-yellow" style={{ fontWeight: "bold" }}>{data?.email || "your email address"}</span> when you're ready to deploy.
            </span>
          </div>
        </div>


        <div className="waitlist-popup-discord-section" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginTop: '20px' }}>

          <p className="waitlist-discord-note">
            Join our discord to stay in the loop{' '}
            <a
              title="Join Discord"
              className="text-inline-yellow"
              href="https://discord.gg/z4SUdrKayb"
              target="_blank"
              rel="noopener noreferrer"
            >
              Discord
            </a>
          </p>

        </div>
      </div>
    </article>
  );
};

export default ReferralPlaceholder;
