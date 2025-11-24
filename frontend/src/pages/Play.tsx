import React, { useRef, useEffect } from "react";

const Play: React.FC = () => {
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const username = "thisplayer1";

  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe) return;

    const handleLoad = () => {
      // Send the message once the iframe HTML is loaded
      // The HTML/Godot logic will handle the buffering
      iframe.contentWindow?.postMessage(
        { type: "set_username", value: username },
        "*"
      );
    };

    iframe.addEventListener("load", handleLoad);
    return () => iframe.removeEventListener("load", handleLoad);
  }, []);

  return (
    <div className="play-container">
      <iframe
        ref={iframeRef}
        src="/godot/index.html" // Make sure this path is correct!
        title="World of Nads"
        style={{
          border: "none",
          width: "100%",
          height: "100vh",
          padding: "0px",
          margin: "0px"
        }}
      />
    </div>
  );
};

export default Play;