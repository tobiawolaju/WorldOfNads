/**
 * Device authorization client for the /auth route.
 *
 * This is NOT the game's login page. It exists for one job: let a player who is
 * already logged into the web build explicitly authorise a native game client
 * that is displaying a short code.
 *
 * Privacy rules this file enforces:
 *   - It sends the code and nothing else. No identity is ever derived here.
 *   - The backend derives the account from the verified Privy access token, so
 *     there is no field on this page that could be tampered with to authorise a
 *     different account.
 *   - Having a Privy session is NOT consent. The user has to press the button.
 */

const DEFAULT_BACKEND_URL = "https://worldofnads.onrender.com";

export function getBackendUrl(): string {
  const configured = import.meta.env.VITE_ANALYTICS_API_URL;
  return (configured || DEFAULT_BACKEND_URL).replace(/\/+$/, "");
}

export interface DeviceLookup {
  device_login_id: string;
  code_display: string;
  platform: string;
  device_label: string;
  status: "pending" | "approved" | string;
  expires_at: string;
  expires_in_seconds: number;
  bound: boolean;
}

export interface ApproveResult {
  approved: boolean;
  device_login_id: string;
  platform?: string;
  user: {
    id: string;
    username: string;
    privy_user_id: string;
    wallet_address: string;
  };
}

async function readError(response: Response, fallback: string): Promise<string> {
  try {
    const data = await response.json();
    if (data?.error) return String(data.error);
  } catch {
    /* non-JSON error body */
  }
  return fallback;
}

/** Maps backend error codes onto copy a player can act on. */
export function describeError(code: string): string {
  switch (code) {
    case "invalid_code":
      return "That code is not valid. Check the code shown in the game and try again.";
    case "device_login_expired":
      return "This code has expired. Generate a new code in the game and scan it again.";
    case "device_login_already_used":
      return "This code has already been used. Start a new login in the game.";
    case "device_login_cancelled":
      return "This login was cancelled in the game. Start a new login to try again.";
    case "device_login_used":
      return "This device login has already been used. Start a new login in the game.";
    case "device_login_already_bound":
      return "This code was already approved by a different account.";
    case "invalid_privy_access_token":
      return "Your session expired. Please sign in again to continue.";
    case "missing_privy_access_token":
      return "Sign in to approve this device.";
    case "privy_not_configured":
      return "Device login is temporarily unavailable. Please try again later.";
    case "privy_user_lookup_failed":
      return "We could not verify your account with Privy. Please try again.";
    case "too_many_requests":
      return "Too many attempts. Wait a moment and try again.";
    case "network_error":
      return "Could not reach the World of Nads server. Check your connection.";
    default:
      return "Something went wrong. Please try again.";
  }
}

/**
 * Resolves the code shown by the native client into the requesting device.
 * Runs before sign-in, so it must never require or return user identity.
 */
export async function lookupDevice(code: string, signal?: AbortSignal): Promise<DeviceLookup> {
  const url = `${getBackendUrl()}/auth/device/lookup?code=${encodeURIComponent(code.trim())}`;
  let response: Response;
  try {
    response = await fetch(url, { signal, headers: { Accept: "application/json" } });
  } catch {
    throw new Error("network_error");
  }
  if (!response.ok) {
    throw new Error(await readError(response, `lookup_failed_${response.status}`));
  }
  return (await response.json()) as DeviceLookup;
}

/**
 * Asks the backend to bind the verified Privy identity to the pending device
 * login. `privyAccessToken` comes from `getAccessToken()`; nothing about the
 * intended account is passed in the body.
 */
export async function approveDevice(
  privyAccessToken: string,
  deviceLoginId: string,
  signal?: AbortSignal
): Promise<ApproveResult> {
  const url = `${getBackendUrl()}/auth/device/approve`;
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${privyAccessToken}`
      },
      body: JSON.stringify({ device_login_id: deviceLoginId })
    });
  } catch {
    throw new Error("network_error");
  }
  if (!response.ok) {
    throw new Error(await readError(response, `approve_failed_${response.status}`));
  }
  return (await response.json()) as ApproveResult;
}

export function formatPlatform(platform: string): string {
  switch (platform) {
    case "android":
      return "Android";
    case "ios":
      return "iOS";
    case "desktop":
      return "Desktop";
    default:
      return "Device";
  }
}

/** Human label for the account behind the active Privy session. */
export function accountLabel(user: any): string {
  if (!user) return "";
  if (user.username) return String(user.username);
  const accounts = Array.isArray(user.linkedAccounts) ? user.linkedAccounts : [];
  const social = accounts.find((a: any) => a?.username || a?.name);
  if (social) return String(social.username || social.name);
  const wallet = accounts.find((a: any) => a?.type === "wallet");
  if (wallet?.address) return String(wallet.address);
  return String(user.id || "");
}