import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import {
  approveDevice,
  accountLabel,
  describeError,
  formatPlatform,
  lookupDevice,
  type ApproveResult,
  type DeviceLookup
} from "../lib/deviceAuth";
import "./DeviceAuth.css";

/**
 * /auth?code=KJI-FYE
 *
 * Device authorization page for native (Android / iOS / desktop) clients.
 *
 * States, in the order a player meets them:
 *   loading   -> validating the code with the backend
 *   invalid   -> bad / expired / already-used code
 *   signin    -> code is valid, but Privy says nobody is signed in yet
 *   approve   -> valid code + signed in, waiting for an explicit decision
 *   approved  -> done; tell the player to go back to the game
 */
const DeviceAuth: React.FC = () => {
  const [searchParams] = useSearchParams();
  const code = (searchParams.get("code") || "").trim();

  const { ready, authenticated, user, login, getAccessToken } = usePrivy();

  const [device, setDevice] = useState<DeviceLookup | null>(null);
  const [status, setStatus] = useState<"loading" | "invalid" | "signin" | "approve" | "approving" | "approved">(
    "loading"
  );
  const [errorCode, setErrorCode] = useState("");
  const [result, setResult] = useState<ApproveResult | null>(null);
  const [secondsLeft, setSecondsLeft] = useState(0);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // --- Validate the code with the backend -----------------------------------
  // Runs on the code alone, before any Privy state, because the point of this
  // page is to tell the player what is asking before they sign in.
  useEffect(() => {
    if (!code) {
      setStatus("invalid");
      setErrorCode("invalid_code");
      return;
    }

    const controller = new AbortController();
    setStatus("loading");

    lookupDevice(code, controller.signal)
      .then((found) => {
        if (!mountedRef.current) return;
        setDevice(found);
        setSecondsLeft(found.expires_in_seconds);
        setStatus(found.status === "approved" ? "approve" : "signin");
      })
      .catch((error: Error) => {
        if (!mountedRef.current || controller.signal.aborted) return;
        setStatus("invalid");
        setErrorCode(error.message);
      });

    return () => controller.abort();
  }, [code]);

  // --- Countdown -------------------------------------------------------------
  // Drives the "code expired" prompt so the player is told to regenerate
  // rather than staring at a code that silently stopped working.
  useEffect(() => {
    if (status === "loading" || status === "invalid" || status === "approved") return;
    const timer = window.setInterval(() => {
      setSecondsLeft((current) => {
        if (current <= 1) {
          window.clearInterval(timer);
          if (mountedRef.current) {
            setStatus("invalid");
            setErrorCode("device_login_expired");
          }
          return 0;
        }
        return current - 1;
      });
    }, 1000);
    return () => window.clearInterval(timer);
  }, [status]);

  // --- Move to approval once Privy reports a session -------------------------
  useEffect(() => {
    if (!ready || status !== "signin") return;
    if (authenticated && user) setStatus("approve");
  }, [ready, authenticated, user, status]);

  const account = useMemo(() => accountLabel(user), [user]);

  const onApprove = useCallback(async () => {
    if (!device) return;
    setStatus("approving");
    setErrorCode("");

    try {
      // getAccessToken() also refreshes the Privy token when it is close to
      // expiry, so the backend never sees a stale one.
      const privyAccessToken = await getAccessToken();
      if (!privyAccessToken) throw new Error("missing_privy_access_token");

      const approved = await approveDevice(privyAccessToken, device.device_login_id);
      if (!mountedRef.current) return;
      setResult(approved);
      setStatus("approved");
    } catch (error) {
      if (!mountedRef.current) return;
      const code_ = error instanceof Error ? error.message : "approve_failed";
      setErrorCode(code_);
      // A rejected token is recoverable in place; anything else sends the player
      // back to the sign-in step to retry cleanly.
      setStatus(code_ === "invalid_privy_access_token" ? "signin" : "approve");
    }
  }, [device, getAccessToken]);

  const expired = secondsLeft <= 0 && status !== "loading" && status !== "approved";

  return (
    <div className="device-auth">
      <div className="device-auth__card">
        <header className="device-auth__header">
          <img src="/logo.jpg" alt="" className="device-auth__logo" aria-hidden="true" />
          <h1 className="device-auth__title">Log in to World of Nads</h1>
          <p className="device-auth__subtitle">Connect your game to your account</p>
        </header>

        {status === "loading" && (
          <div className="device-auth__body">
            <div className="device-auth__spinner" aria-hidden="true" />
            <p>Checking your code…</p>
          </div>
        )}

        {status === "invalid" && (
          <div className="device-auth__body">
            <h2 className="device-auth__heading">This code is not valid</h2>
            <p className="device-auth__message">{describeError(errorCode || "invalid_code")}</p>
            <p className="device-auth__hint">
              In the game, tap <strong>New code</strong> to generate a fresh one.
            </p>
          </div>
        )}

        {status === "signin" && (
          <div className="device-auth__body">
            <h2 className="device-auth__heading">
              {device ? formatPlatform(device.platform) : "Device"} wants to connect
            </h2>
            {device?.code_display && <p className="device-auth__code">{device.code_display}</p>}
            {device?.device_label && <p className="device-auth__device">{device.device_label}</p>}
            <p className="device-auth__message">
              Sign in to World of Nads to approve this device.
            </p>
            <button type="button" className="device-auth__button" onClick={() => login()}>
              Sign in
            </button>
            {errorCode && <p className="device-auth__error">{describeError(errorCode)}</p>}
          </div>
        )}

        {status !== "loading" && status !== "invalid" && status !== "signin" && (
          <div className="device-auth__body">
            <h2 className="device-auth__heading">
              {device ? formatPlatform(device.platform) : "Device"} wants to connect
            </h2>
            {device?.code_display && <p className="device-auth__code">{device.code_display}</p>}
            {device?.device_label && <p className="device-auth__device">{device.device_label}</p>}

            {status === "approved" ? (
              <>
                <div className="device-auth__success" role="status">
                  <span className="device-auth__success-mark" aria-hidden="true">
                    ✓
                  </span>
                  <p>
                    {result?.user?.username ? `${result.user.username} is now connected.` : "Device connected."}
                  </p>
                </div>
                <p className="device-auth__message">You can close this page and return to the game.</p>
              </>
            ) : (
              <>
                <div className="device-auth__account">
                  <p className="device-auth__account-label">You are logged in as</p>
                  <p className="device-auth__account-name">{account || "Player"}</p>
                </div>

                <p className="device-auth__message">
                  Approve only if you started this login yourself. The game will sign in as{" "}
                  <strong>{account || "this account"}</strong>.
                </p>

                <button
                  type="button"
                  className="device-auth__button device-auth__button--approve"
                  onClick={onApprove}
                  disabled={status === "approving" || expired}
                >
                  {status === "approving" ? "Approving…" : "Approve login"}
                </button>
                <button
                  type="button"
                  className="device-auth__button device-auth__button--ghost"
                  onClick={() => login()}
                >
                  Use a different account
                </button>

                {errorCode && <p className="device-auth__error">{describeError(errorCode)}</p>}
              </>
            )}

            {!expired && status !== "approved" && (
              <p className="device-auth__expiry">
                Code expires in <strong>{secondsLeft}s</strong>
              </p>
            )}
          </div>
        )}

        <footer className="device-auth__footer">
          <p>
            This page authorizes a game client. It never asks for your wallet seed phrase or private key.
          </p>
        </footer>
      </div>
    </div>
  );
};

export default DeviceAuth;