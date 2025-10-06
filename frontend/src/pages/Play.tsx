import React, { useRef } from "react";

const Play: React.FC = () => {
  const iframeRef = useRef<HTMLIFrameElement | null>(null);

  return (
    <div className="play-container">
      <iframe
        ref={iframeRef}
        src="/godot/index.html"
        title="Godot Game"
        style={{
          border: "none",
          width: "100%",
          height: "100vh",
        }}
      />
    </div>
  );
};

export default Play;
