import React, { useCallback, useEffect, useRef, useState } from "react";
import "./InstallPrompt.css";

// Chromium's install prompt event. It is not part of the standard TS DOM types.
interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

const DISMISS_KEY = "wons:install-dismissed";

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
    try {
      if (window.localStorage.getItem(DISMISS_KEY) === "1") return;
    } catch {
      // Storage unavailable (private mode): still offer it for this session.
    }

    const onIos = isIosDevice();
    setIos(onIos);

    const handleBeforeInstall = (event: Event) => {
      // Suppress the browser mini-infobar and show our own prompt instead.
      event.preventDefault();
      deferredPromptRef.current = event as BeforeInstallPromptEvent;
      setIos(false);
      setVisible(true);
    };

    const handleInstalled = () => {
      setVisible(false);
      try {
        window.localStorage.setItem(DISMISS_KEY, "1");
      } catch {
        /* ignore */
      }
    };

    window.addEventListener("beforeinstallprompt", handleBeforeInstall);
    window.addEventListener("appinstalled", handleInstalled);

    // Give iOS a moment before nudging, so it doesn't land on top of the first
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

  const dismiss = useCallback(() => {
    setVisible(false);
    try {
      window.localStorage.setItem(DISMISS_KEY, "1");
    } catch {
      /* ignore */
    }
  }, []);

  const handleInstall = useCallback(async () => {
    const deferred = deferredPromptRef.current;
    if (!deferred) return;
    try {
      await deferred.prompt();
      const choice = await deferred.userChoice;
      if (choice.outcome === "accepted") dismiss();
    } catch {
      /* ignore */
    }
    deferredPromptRef.current = null;
  }, [dismiss]);

  if (!visible) return null;

  return (
    <div className="install-prompt" role="dialog" aria-label="Install World of Nads">
      <div className="install-prompt__card">
        <img
          className="install-prompt__icon"
          src="/logo.png"
          alt=""
          width={48}
          height={48}
        />
        <div className="install-prompt__text">
          <span className="install-prompt__title">Install World of Nads</span>
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
              then <strong>Add to Home Screen</strong> to play full screen.
            </span>
          ) : (
            <span className="install-prompt__subtitle">
              Add it to your home screen to play full screen, like an app.
            </span>
          )}
        </div>
        {!ios && (
          <button type="button" className="install-prompt__cta" onClick={handleInstall}>
            Install
          </button>
        )}
        <button
          type="button"
          className="install-prompt__close"
          onClick={dismiss}
          aria-label="Not now"
        >
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path
              d="M12 4L4 12M4 4l8 8"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
            />
          </svg>
        </button>
      </div>
    </div>
  );
};

export default InstallPrompt;
