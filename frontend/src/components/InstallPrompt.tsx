import React, { useCallback, useEffect, useRef, useState } from "react";
import "./InstallPrompt.css";

// Chromium's install prompt event. It is not part of the standard TS DOM types.
interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

// True once the site is already running as an installed app.
const isStandalone = (): boolean =>
  window.matchMedia("(display-mode: standalone)").matches ||
  window.matchMedia("(display-mode: fullscreen)").matches ||
  (window.navigator as unknown as { standalone?: boolean }).standalone === true;

// Phones and tablets only; desktop users install from the address bar.
const isMobileDevice = (): boolean =>
  window.matchMedia("(hover: none) and (pointer: coarse)").matches;

// iOS never fires `beforeinstallprompt`, so there we always fall back to manual
// "Add to Home Screen" instructions. This covers every iOS browser, all of
// which are WebKit under the hood.
const isIosDevice = (): boolean => {
  const ua = window.navigator.userAgent;
  return (
    /iPad|iPhone|iPod/.test(ua) ||
    (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
  );
};

export const InstallPrompt: React.FC = () => {
  const [visible, setVisible] = useState(false);
  const [ios, setIos] = useState(false);
  const deferredPromptRef = useRef<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    if (isStandalone() || !isMobileDevice()) return;

    const onIos = isIosDevice();
    setIos(onIos);

    const handleBeforeInstall = (event: Event) => {
      // Suppress the browser mini-infobar and show our own gate instead.
      event.preventDefault();
      deferredPromptRef.current = event as BeforeInstallPromptEvent;
      setIos(false);
      setVisible(true);
    };

    const handleInstalled = () => setVisible(false);

    window.addEventListener("beforeinstallprompt", handleBeforeInstall);
    window.addEventListener("appinstalled", handleInstalled);

    // Give iOS a moment before gating, so it doesn't land on top of the first
    // paint.
    let iosTimer: number | undefined;
    if (onIos) {
      iosTimer = window.setTimeout(() => setVisible(true), 2500);
    }

    return () => {
      window.removeEventListener("beforeinstallprompt", handleBeforeInstall);
      window.removeEventListener("appinstalled", handleInstalled);
      if (iosTimer !== undefined) window.clearTimeout(iosTimer);
    };
  }, []);

  const handleInstall = useCallback(async () => {
    const deferred = deferredPromptRef.current;
    if (!deferred) return;
    try {
      await deferred.prompt();
      const choice = await deferred.userChoice;
      if (choice.outcome === "accepted") setVisible(false);
    } catch {
      /* ignore */
    }
    deferredPromptRef.current = null;
  }, []);

  if (!visible) return null;

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
          <button type="button" className="install-prompt__cta" onClick={handleInstall}>
            Install
          </button>
        )}
      </div>
    </div>
  );
};

export default InstallPrompt;
