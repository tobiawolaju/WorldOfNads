import React, { useRef, useEffect } from "react";

const Play: React.FC = () => {
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const username = "SIrNigga that is black"; // Example, could come from props or state

  useEffect(() => {
    // Wait for iframe to load, then send message
    const iframe = iframeRef.current;
    if (!iframe) return;

    const handleLoad = () => {
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
        src="/godot/index.html"
        title="World of Nads"
        style={{
          border: "none",
          width: "100%",
          height: "100vh",
          padding:"0px",
          margin:"0px"
        }}
      />
    </div>
  );
};

export default Play;
