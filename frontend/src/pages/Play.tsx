import React, { useCallback, useEffect, useRef, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";

function getUsernameFromPrivy(user: any): string {
  const twitter = user?.linkedAccounts?.find((acc: any) => acc.type === "twitter_oauth");
  const wallet = user?.linkedAccounts?.find((acc: any) => acc.type === "wallet");
  return twitter?.username || wallet?.address || "Anon";
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
      style={{ width: "100vw", height: "100dvh", position: "relative", overflow: "hidden" }}
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
          <span
            className="material-symbols-rounded"
            aria-hidden="true"
            style={{
              fontSize: "1.5rem",
              lineHeight: 1,
              fontVariationSettings: "'FILL' 0, 'wght' 700, 'GRAD' 0, 'opsz' 48",
            }}
          >
            fullscreen
          </span>
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
