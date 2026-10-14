import React, { useSyncExternalStore } from "react";
import {
  isInstallGateOpen,
  isIosDevice,
  promptInstall,
  subscribeInstallState,
} from "../lib/installPrompt";
import "./InstallPrompt.css";

// Rendered globally, but only visible once `requireInstall()` has opened the
// gate (i.e. the user tapped Play without the app installed). It is transparent
// and covers the whole viewport, so the page stays visible underneath yet
// cannot be scrolled or tapped until the app is installed.
export const InstallPrompt: React.FC = () => {
  const open = useSyncExternalStore(subscribeInstallState, isInstallGateOpen, () => false);

  if (!open) return null;

  const ios = isIosDevice();

  return (
    <div
      className="install-prompt"
      role="dialog"
      aria-modal="true"
      aria-label="Install World of Nads"
    >
      <div className="install-prompt__card">
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
        {!ios && (
          <button
            type="button"
            className="install-prompt__cta"
            onClick={() => void promptInstall()}
          >
            Install
          </button>
        )}
      </div>
    </div>
  );
};

export default InstallPrompt;
