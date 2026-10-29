// Shared install-prompt state for the PWA.
//
// The gate is NOT shown on page load. A screen calls `requireInstall()` when the
// user tries to play the game; if the site is running on a phone/tablet and the
// app is not installed yet, the gate opens and the caller aborts its action.

// Chromium's install prompt event. It is not part of the standard TS DOM types.
export interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed"; platform: string }>;
}

let deferredPrompt: BeforeInstallPromptEvent | null = null;
let installedThisSession = false;
let gateOpen = false;
const listeners = new Set<() => void>();

const emit = (): void => {
  listeners.forEach((listener) => listener());
};

export const subscribeInstallState = (listener: () => void): (() => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

// True once the site is already running as an installed app.
export const isStandalone = (): boolean => {
  if (typeof window === "undefined") return false;
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    window.matchMedia("(display-mode: fullscreen)").matches ||
    (window.navigator as unknown as { standalone?: boolean }).standalone === true
  );
};

// Phones and tablets only; desktop users install from the address bar.
export const isMobileDevice = (): boolean => {
  if (typeof window === "undefined") return false;
  const ua = window.navigator?.userAgent || "";
  const isMobileUa = /Android|iPhone|iPad|iPod|webOS|BlackBerry|IEMobile|Opera Mini/i.test(ua);
  return isMobileUa || window.matchMedia("(hover: none) and (pointer: coarse)").matches;
};

// iOS never fires `beforeinstallprompt`, so there we fall back to manual
// "Add to Home Screen" instructions. Every iOS browser is WebKit underneath.
export const isIosDevice = (): boolean => {
  if (typeof window === "undefined") return false;
  const ua = window.navigator.userAgent;
  return (
    /iPad|iPhone|iPod/.test(ua) ||
    (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
  );
};

export const isAppInstalled = (): boolean => installedThisSession || isStandalone();

// Whether we can trigger the native install prompt (Android / Chromium).
export const canPromptInstall = (): boolean => deferredPrompt !== null;

export const isInstallGateOpen = (): boolean => gateOpen;

export const openInstallGate = (): void => {
  gateOpen = true;
  emit();
};

export const closeInstallGate = (): void => {
  gateOpen = false;
  emit();
};

// Opens the gate when a play attempt happens on an un-installed mobile device.
// Returns true when the caller should abort its action.
export const requireInstall = (): boolean => {
  if (!isMobileDevice() || isAppInstalled()) return false;
  openInstallGate();
  return true;
};

// Register the global listeners once, as early as possible (see main.tsx), so a
// `beforeinstallprompt` fired on page load is still available when the user
// later taps Play.
export const initInstallPrompt = (): void => {
  if (typeof window === "undefined") return;

  window.addEventListener("beforeinstallprompt", (event) => {
    // Suppress the browser mini-infobar; we show our own gate instead.
    event.preventDefault();
    deferredPrompt = event as BeforeInstallPromptEvent;
    emit();
  });

  window.addEventListener("appinstalled", () => {
    installedThisSession = true;
    deferredPrompt = null;
    gateOpen = false;
    emit();
  });
};

export const promptInstall = async (): Promise<void> => {
  const prompt = deferredPrompt;
  if (!prompt) return;
  try {
    await prompt.prompt();
    const choice = await prompt.userChoice;
    if (choice && choice.outcome === "accepted") {
      installedThisSession = true;
      gateOpen = false;
    }
  } catch {
    /* ignore */
  }
  // A single event can only be prompted once; `appinstalled` closes the gate on
  // success.
  deferredPrompt = null;
  emit();
};
