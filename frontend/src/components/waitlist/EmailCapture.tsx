import React, { FormEvent, useState } from "react";

type EmailCaptureProps = {
  buttonLabel: string;
  helperText?: string;
  className?: string;
};

const EmailCapture: React.FC<EmailCaptureProps> = ({ buttonLabel, helperText, className = "" }) => {
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!email.trim()) return;

    console.log("[waitlist] captured email", email);
    setSubmitted(true);
    setEmail("");
  };

  return (
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
  );
};

export default EmailCapture;
