import React, { useEffect, useState } from "react";
import "./FullscreenToggle.css";

export const FullscreenToggle: React.FC = () => {
  const [enabled, setEnabled] = useState(false);
  const [active, setActive] = useState(false);

  useEffect(() => {
    const update = () => {
      setEnabled(Boolean(document.fullscreenEnabled || document.webkitFullscreenEnabled));
      setActive(Boolean(document.fullscreenElement || document.webkitFullscreenElement));
    };
    update();
    document.addEventListener("fullscreenchange", update);
    document.addEventListener("webkitfullscreenchange", update);
    return () => {
      document.removeEventListener("fullscreenchange", update);
      document.removeEventListener("webkitfullscreenchange", update);
    };
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
          // Fullscreen the app container instead of <html>: Chrome scales the
          // page to device-width when <html> goes fullscreen, which makes every
          // button/card ~2x bigger on mobile. #root keeps its layout width, so
          // the rendered content stays pixel-identical.
          const target = document.getElementById("root") || document.body || document.documentElement;
          void (target.requestFullscreen?.() ?? Promise.reject(new Error("no fullscreen")));
        }
      }}
    >
      <span aria-hidden="true">⛶</span>
    </button>
  );
};

export default FullscreenToggle;