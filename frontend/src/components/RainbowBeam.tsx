import React, { useEffect, useRef } from "react";

const RainbowBeam: React.FC = () => {
  const barRef = useRef<HTMLDivElement>(null);
  const posY = useRef<number>(-200);
  const elementsRef = useRef<NodeListOf<Element> | null>(null);
  const lastScanTime = useRef<number>(0);
  
  const beamHeight = 80;
  const speed = 3.5;

  useEffect(() => {
    let animationFrameId: number;

    const updateElements = () => {
      elementsRef.current = document.querySelectorAll(
        "h1, h2, h3, h4, h5, h6, p, a, button, img, .card, .match-card, .tab, .filter, .button, .wons-card, .stats-card, .event-card, .match-details, .reward-item"
      );
    };

    updateElements();

    const animate = (time: number) => {
      // Re-scan DOM every 2 seconds to catch new elements
      if (time - lastScanTime.current > 2000) {
        updateElements();
        lastScanTime.current = time;
      }

      posY.current += speed;
      if (posY.current > window.innerHeight + beamHeight) {
        posY.current = -beamHeight;
      }

      if (barRef.current) {
        barRef.current.style.top = `${posY.current}px`;
      }

      const beamCenter = posY.current + beamHeight / 2;

      if (elementsRef.current) {
        elementsRef.current.forEach((el) => {
          const rect = el.getBoundingClientRect();
          
          // Optimization: Skip if the element's bounding rect is not currently valid or far from viewport
          if (rect.width === 0 || rect.height === 0) return;
          if (rect.bottom < -100 || rect.top > window.innerHeight + 100) return;

          const elCenter = rect.top + rect.height / 2;
          const distance = Math.abs(beamCenter - elCenter);

          // Inclusion threshold based on beam height and element size
          if (distance < beamHeight / 2 + rect.height / 2) {
            if (el.tagName === "IMG") {
              el.classList.add("rainbow-active-img");
            } else if (
              el.tagName === "DIV" ||
              el.tagName === "SECTION" ||
              el.classList.contains("card") ||
              el.classList.contains("match-card") ||
              el.classList.contains("wons-card") ||
              el.classList.contains("stats-card") ||
              el.classList.contains("event-card")
            ) {
              el.classList.add("rainbow-active-div");
            } else {
              el.classList.add("rainbow-active-text");
            }
          } else {
            el.classList.remove("rainbow-active-img", "rainbow-active-div", "rainbow-active-text");
          }
        });
      }

      animationFrameId = requestAnimationFrame(animate);
    };

    animationFrameId = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(animationFrameId);
      const elements = document.querySelectorAll(
        ".rainbow-active-img, .rainbow-active-div, .rainbow-active-text"
      );
      elements.forEach((el) =>
        el.classList.remove("rainbow-active-img", "rainbow-active-div", "rainbow-active-text")
      );
    };
  }, []);

  return (
    <div className="rainbow-beam-container">
      <div ref={barRef} className="rainbow-bar" />
    </div>
  );
};

export default RainbowBeam;
