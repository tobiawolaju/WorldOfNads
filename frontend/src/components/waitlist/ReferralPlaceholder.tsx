import React from "react";

const ReferralPlaceholder: React.FC = () => {
  const referralLink = "https://worldofnads.com/waitlist?ref=PLAYER4231";

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(referralLink);
      console.log("[waitlist] referral copied");
    } catch {
      console.log("[waitlist] clipboard unavailable");
    }
  };

  return (
    <article className="tweet-card waitlist-referral-card reveal">
      <p className="waitlist-ref-title">You’re #4,231 in line</p>
      <p className="waitlist-ref-subtitle">Invite friends to move up</p>
      <div className="waitlist-ref-link-row">
        <input className="waitlist-input" value={referralLink} readOnly aria-label="Referral link" />
        <button className="button waitlist-copy-button" type="button" onClick={copyLink}>
          Copy
        </button>
      </div>
      <div className="waitlist-ref-rewards">
        <p>Top 100 → guaranteed beta</p>
        <p>Top 10 → early rewards</p>
      </div>
    </article>
  );
};

export default ReferralPlaceholder;
