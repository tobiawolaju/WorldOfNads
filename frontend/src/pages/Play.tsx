import React, { useRef, useEffect } from "react";
import { usePrivy } from "@privy-io/react-auth";

function getUsernameFromPrivy(user: any): string {
  const twitter = user?.linkedAccounts?.find((acc: any) => acc.type === "twitter_oauth");
  const wallet = user?.linkedAccounts?.find((acc: any) => acc.type === "wallet");
  return twitter?.username || wallet?.address || "Anon";
}

const Play: React.FC = () => {
  const { user } = usePrivy();
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const username = getUsernameFromPrivy(user);
  const gameUrl = `/godot/index.html?username=${encodeURIComponent(username)}`;

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

  return (
    <div className="play-container">
      <iframe
        ref={iframeRef}
        src={gameUrl}
        title="World of Nads"
        style={{
          border: "none",
          width: "100%",
          height: "100vh",
          padding: "0px",
          margin: "0px",
        }}
      />
    </div>
  );
};

export default Play;
