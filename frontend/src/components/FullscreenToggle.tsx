import React, { useEffect, useRef, useState } from "react";
import "./FullscreenToggle.css";

const getFullscreenElement = (): Element | null =>
  (document as any).fullscreenElement || (document as any).webkitFullscreenElement || null;

export const FullscreenToggle: React.FC = () => {
  const [enabled, setEnabled] = useState(false);
  const [active, setActive] = useState(false);
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null);
  const btnRef = useRef<HTMLButtonElement>(null);
  const dragRef = useRef<{
    startX: number;
    startY: number;
    origX: number;
    origY: number;
  } | null>(null);
  const movedRef = useRef(false);

  useEffect(() => {
    const update = () => {
      setEnabled(
        Boolean(
          (document as any).fullscreenEnabled ||
            (document as any).webkitFullscreenEnabled
        )
      );
      setActive(Boolean(getFullscreenElement()));
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

  const startDrag = (e: React.PointerEvent<HTMLButtonElement>) => {
    const btn = btnRef.current;
    if (e.button !== 0 && e.pointerType === "mouse") return;
    if (!btn) return;
    const rect = btn.getBoundingClientRect();
    dragRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      origX: rect.left,
      origY: rect.top,
    };
    movedRef.current = false;
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const moveDrag = (e: React.PointerEvent<HTMLButtonElement>) => {
    const drag = dragRef.current;
    if (!drag) return;
    const dx = e.clientX - drag.startX;
    const dy = e.clientY - drag.startY;
    if (!movedRef.current && Math.hypot(dx, dy) > 6) {
      movedRef.current = true;
    }
    if (!movedRef.current) return;
    const size = btnRef.current
      ? btnRef.current.getBoundingClientRect()
      : { width: 48, height: 48 };
    const maxX = Math.max(0, window.innerWidth - size.width);
    const maxY = Math.max(0, window.innerHeight - size.height);
    setPos({
      x: Math.min(Math.max(0, drag.origX + dx), maxX),
      y: Math.min(Math.max(0, drag.origY + dy), maxY),
    });
  };

  const endDrag = () => {
    dragRef.current = null;
  };

  const handleClick = () => {
    if (movedRef.current) {
      movedRef.current = false;
      return;
    }
    const current = getFullscreenElement();
    const exit = (document as any).exitFullscreen || (document as any).webkitExitFullscreen;
    if (current && exit) {
      exit.call(document);
      return;
    }
    // Fullscreen the app container (#root) instead of <html>: Chrome scales
    // the page to device-width when <html> goes fullscreen, which makes every
    // button/card ~2x bigger on mobile. #root keeps its layout width, so the
    // rendered content stays pixel-identical.
    const target = document.getElementById("root") || document.body || document.documentElement;
    const request = (target as any).requestFullscreen || (target as any).webkitRequestFullscreen;
    if (request) {
      const ret = request.call(target);
      if (ret && typeof ret.catch === "function") {
        ret.catch(() => {});
      }
    }
  };

  return (
    <button
      ref={btnRef}
      type="button"
      className={`fullscreen-toggle ${active ? "active" : ""}`}
      aria-label={active ? "Exit full screen" : "Click for fullscreen"}
      title={active ? "Exit full screen" : "Enter full screen"}
      style={pos ? { left: pos.x, top: pos.y } : undefined}
      onPointerDown={startDrag}
      onPointerMove={moveDrag}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onClick={handleClick}
    >
      {active ? (
        <svg viewBox="0 0 24 24" fill="#000" aria-hidden="true">
          <path d="M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z" />
        </svg>
      ) : (
        <svg viewBox="0 0 24 24" fill="#000" aria-hidden="true">
          <path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z" />
        </svg>
      )}
    </button>
  );
};

export default FullscreenToggle;