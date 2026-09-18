import React, { useEffect, useState } from "react";
import "./FullscreenToggle.css";

export const FullscreenToggle: React.FC = () => {
  const [enabled, setEnabled] = useState(false);
  const [active, setActive] = useState(false);

  useEffect(() => {
    const update = () => {
      setEnabled(Boolean(document.fullscreenEnabled));
      setActive(Boolean(document.fullscreenElement));
    };
    update();
    document.addEventListener("fullscreenchange", update);
    return () => document.removeEventListener("fullscreenchange", update);
  }, []);

  if (!enabled) return null;

  return (
    <button
      type="button"
      className="fullscreen-toggle"
      aria-label={active ? "Exit full screen" : "Click for fullscreen"}
      title={active ? "Exit full screen" : "Enter full screen"}
      onClick={() => {
        if (document.fullscreenElement) {
          void document.exitFullscreen();
        } else {
          void document.documentElement.requestFullscreen();
        }
      }}
    >
      <span aria-hidden="true">⛶</span>
    </button>
  );
};

export default FullscreenToggle;