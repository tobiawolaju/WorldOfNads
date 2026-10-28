import React, { useEffect, useSyncExternalStore } from "react";
import {
  closeInstallGate,
  isInstallGateOpen,
  isIosDevice,
  promptInstall,
  subscribeInstallState,
} from "../lib/installPrompt";
import "./InstallPrompt.css";

// Rendered globally, but only visible once `requireInstall()` has opened the
// gate (i.e. the user tapped Play/Drop In without the app installed).
// Users can cancel/dismiss the prompt to continue browsing the page.
export const InstallPrompt: React.FC = () => {
  const open = useSyncExternalStore(subscribeInstallState, isInstallGateOpen, () => false);

  useEffect(() => {
    if (!open) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        closeInstallGate();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [open]);

  if (!open) return null;

  const ios = isIosDevice();

  return (
    <div
      className="install-prompt"
      role="dialog"
      aria-modal="true"
      aria-label="Install World of Nads"
      onClick={(e) => {
        if (e.target === e.currentTarget) {
          closeInstallGate();
        }
      }}
    >
      <div className="install-prompt__card">
        <button
          type="button"
          className="install-prompt__close"
          onClick={closeInstallGate}
          aria-label="Cancel and close prompt"
        >
          <svg
            viewBox="0 0 24 24"
            width="16"
            height="16"
            stroke="currentColor"
            strokeWidth="2.5"
            fill="none"
            strokeLinecap="round"
          >
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>

        <span className="install-prompt__title">World of Nads</span>
        {ios ? (
          <span className="install-prompt__subtitle">
            Tap the Share icon
            <svg className="install-prompt__share" viewBox="0 0 24 24" aria-hidden="true">
              <path
                d="M12 3v12m0-12l-4 4m4-4l4 4M6 12v6a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-6"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            then <strong>Add to Home Screen</strong> to continue.
          </span>
        ) : (
          <span className="install-prompt__subtitle">
            Install the app to continue. It runs full screen.
          </span>
        )}

        <div className="install-prompt__actions">
          {!ios && (
            <button
              type="button"
              className="install-prompt__cta"
              onClick={() => void promptInstall()}
            >
              Install
            </button>
          )}
          <button
            type="button"
            className="install-prompt__cancel"
            onClick={closeInstallGate}
          >
            {ios ? "Dismiss" : "Cancel"}
          </button>
        </div>
      </div>
    </div>
  );
};

export default InstallPrompt;
