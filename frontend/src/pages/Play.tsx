import React, { useCallback, useEffect, useRef, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";

function getUsernameFromPrivy(user: any): string {
  if (!user?.linkedAccounts) return "Anon";
  const providers = [
    { type: "twitter_oauth", field: "username" },
    { type: "farcaster", field: "username" },
    { type: "google_oauth", field: "name" },
    { type: "twitch_oauth", field: "username" },
    { type: "tiktok_oauth", field: "username" },
    { type: "spotify_oauth", field: "name" }
  ];
  for (const provider of providers) {
    const acc = user.linkedAccounts.find((a: any) => a.type === provider.type);
    if (acc) {
      const val = acc[provider.field];
      if (val) return val;
    }
  }
  const wallet = user?.linkedAccounts?.find((acc: any) => acc.type === "wallet");
  return wallet?.address || "Anon";
}

const Play: React.FC = () => {
  const { user } = usePrivy();
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [canFullscreen, setCanFullscreen] = useState(false);
  const username = getUsernameFromPrivy(user);
  const gameUrl = `/godot/index.html?username=${encodeURIComponent(username)}`;

  const requestFullscreen = useCallback(async () => {
    const container = containerRef.current;
    if (!container) return;

    try {
      if (document.fullscreenElement) return;
      if (container.requestFullscreen) {
        await container.requestFullscreen({ navigationUI: "hide" });
      }
    } catch (error) {
      console.warn("Fullscreen request failed:", error);
    }
  }, []);

  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe) return;

    const handleLoad = () => {
      // Send the message once the iframe HTML is loaded
      // The HTML/Godot logic will handle the buffering
      iframe.contentWindow?.postMessage(
        { type: "set_username", value: username },
        "*",
      );
    };

    iframe.addEventListener("load", handleLoad);
    return () => iframe.removeEventListener("load", handleLoad);
  }, [username]);

  useEffect(() => {
    setCanFullscreen(Boolean(document.fullscreenEnabled));

    const handleFullscreenChange = () => {
      setIsFullscreen(Boolean(document.fullscreenElement));
    };

    document.addEventListener("fullscreenchange", handleFullscreenChange);
    return () => document.removeEventListener("fullscreenchange", handleFullscreenChange);
  }, []);

  useEffect(() => {
    const container = containerRef.current;
    if (!container || !canFullscreen) return;

    const handleFirstTap = () => {
      requestFullscreen();
      container.removeEventListener("pointerdown", handleFirstTap);
      container.removeEventListener("touchstart", handleFirstTap);
    };

    container.addEventListener("pointerdown", handleFirstTap, { passive: true });
    container.addEventListener("touchstart", handleFirstTap, { passive: true });

    return () => {
      container.removeEventListener("pointerdown", handleFirstTap);
      container.removeEventListener("touchstart", handleFirstTap);
    };
  }, [canFullscreen, requestFullscreen]);

  return (
    <div
      ref={containerRef}
      className="play-container"
      style={{
        position: "fixed",
        inset: 0,
        width: "100vw",
        height: "100dvh",
        background: "#000",
        overflow: "hidden",
      }}
    >
      {canFullscreen && !isFullscreen && (
        <button
          type="button"
          onClick={requestFullscreen}
          aria-label="Enter full screen"
          style={{
            position: "absolute",
            top: "1rem",
            right: "1rem",
            zIndex: 20,
            width: "3rem",
            height: "3rem",
            borderRadius: "999px",
            border: "4px solid transparent",
            background: "transparent",
            color: "#fff",
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "pointer",
          }}
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            width="20"
            height="20"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M8 3H3v5" />
            <path d="M16 3h5v5" />
            <path d="M21 16v5h-5" />
            <path d="M8 21H3v-5" />
          </svg>
        </button>
      )}
      <iframe
        ref={iframeRef}
        src={gameUrl}
        title="World of Nads"
        style={{
          border: "none",
          width: "100%",
          height: "100%",
          padding: "0px",
          margin: "0px",
        }}
      />
    </div>
  );
};

export default Play;
