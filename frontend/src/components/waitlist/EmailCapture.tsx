import React, { FormEvent, useEffect, useState } from "react";
import { createPortal } from "react-dom";
import ReferralPlaceholder from "./ReferralPlaceholder";

type EmailCaptureProps = {
  buttonLabel: string;
  helperText?: string;
  className?: string;
};

const GAS_URL = "https://script.google.com/macros/s/AKfycbx0Fg7id6ZG_lmPZ8bPPIgMhK2ZgVKkwYavrFhPsWdoKf5Vc5flJKAYOpOjy4X0d7KQ/exec";

const EmailCapture: React.FC<EmailCaptureProps> = ({ buttonLabel, helperText, className = "" }) => {
  const [email, setEmail] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [waitlistData, setWaitlistData] = useState<any>(null);
  const [showReferralPopup, setShowReferralPopup] = useState(false);

  useEffect(() => {
    // Check for referral code in URL
    const params = new URLSearchParams(window.location.search);
    const ref = params.get("ref");
    if (ref) {
      localStorage.setItem("nad_referred_by", ref);
    }
    if (!showReferralPopup) {
      document.body.style.overflow = "";
      return;
    }

    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = "";
    };
  }, [showReferralPopup]);

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!email.trim() || isLoading) return;

    setIsLoading(true);
    setError(null);

    const referredBy = localStorage.getItem("nad_referred_by") || "";

    try {
      // Use standard GET request to bypass CORS preflight (OPTIONS) limitations of GAS
      const url = `${GAS_URL}?email=${encodeURIComponent(email)}&referredBy=${encodeURIComponent(referredBy)}`;
      
      const response = await fetch(url, {
        method: "GET",
        mode: "cors", // Default, allows following redirects to googleusercontent.com
      });

      const data = await response.json();

      if (data.status === "error") {
        throw new Error(data.message);
      }

      setWaitlistData(data);
      setShowReferralPopup(true);
      setEmail("");
    } catch (err) {
      console.error("[waitlist] submission failed", err);
      setError("Something went wrong. Please try again.");
    } finally {
      setIsLoading(false);
    }
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
            disabled={isLoading}
            required
          />
          <button className="play-btn-fixed waitlist-submit" type="submit" disabled={isLoading}>
            {isLoading ? "Joining..." : buttonLabel}
          </button>
        </form>
        {error ? (
          <p className="waitlist-helper waitlist-error" style={{ color: "#ff6b6b" }}>{error}</p>
        ) : waitlistData ? (
          <p className="waitlist-helper waitlist-success">
            {waitlistData.status === "already_on_list" 
              ? "Welcome back! You're already on the list." 
              : "You’re in! Check your position below."}
          </p>
        ) : (
          helperText ? <p className="waitlist-helper">{helperText}</p> : null
        )}
      </div>

      {showReferralPopup ? createPortal(
        <div className="waitlist-popup-overlay" role="dialog" aria-modal="true" aria-label="Referral waitlist details">
          <ReferralPlaceholder 
            showAsPopup 
            onClose={closePopup} 
            data={waitlistData}
          />
        </div>,
        document.body
      ) : null}
    </>
  );

export default EmailCapture;
