import React, { FormEvent, useEffect, useState } from "react";
import ReferralPlaceholder from "./ReferralPlaceholder";

type EmailCaptureProps = {
  buttonLabel: string;
  helperText?: string;
  className?: string;
};

const EmailCapture: React.FC<EmailCaptureProps> = ({ buttonLabel, helperText, className = "" }) => {
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [showReferralPopup, setShowReferralPopup] = useState(false);

  useEffect(() => {
    if (!showReferralPopup) {
      document.body.style.overflow = "";
      return;
    }

    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = "";
    };
  }, [showReferralPopup]);

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!email.trim()) return;

    console.log("[waitlist] captured email", email);
    setSubmitted(true);
    setShowReferralPopup(true);
    setEmail("");
  };

  const closePopup = () => {
    setShowReferralPopup(false);
  };

  return (
    <>
      <div className={`waitlist-capture ${className}`.trim()}>
        <form className="waitlist-capture-form" onSubmit={handleSubmit}>
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="Enter your email"
            className="waitlist-input"
            required
          />
          <button className="play-btn-fixed waitlist-submit" type="submit">
            {buttonLabel}
          </button>
        </form>
        {submitted ? (
          <p className="waitlist-helper waitlist-success">You’re in. Watch your inbox for match invites.</p>
        ) : (
          helperText ? <p className="waitlist-helper">{helperText}</p> : null
        )}
      </div>

      {showReferralPopup ? (
        <div className="waitlist-popup-overlay" role="dialog" aria-modal="true" aria-label="Referral waitlist details">
          <ReferralPlaceholder showAsPopup onClose={closePopup} />
        </div>
      ) : null}
    </>
  );
};

export default EmailCapture;
