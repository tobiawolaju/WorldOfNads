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
      // Only targeting text-based elements now
      elementsRef.current = document.querySelectorAll(
        "h1, h2, h3, h4, h5, h6, p, a, button, .tab, .filter"
      );
    };

    updateElements();

    const animate = (time: number) => {
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
          
          if (rect.width === 0 || rect.height === 0) return;
          if (rect.bottom < -100 || rect.top > window.innerHeight + 100) return;

          const elCenter = rect.top + rect.height / 2;
          const distance = Math.abs(beamCenter - elCenter);

          if (distance < beamHeight / 2 + rect.height / 2) {
            el.classList.add("rainbow-active-text");
          } else {
            el.classList.remove("rainbow-active-text");
          }
        });
      }

      animationFrameId = requestAnimationFrame(animate);
    };

    animationFrameId = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(animationFrameId);
      const elements = document.querySelectorAll(".rainbow-active-text");
      elements.forEach((el) => el.classList.remove("rainbow-active-text"));
    };
  }, []);

  return (
    <div className="rainbow-beam-container">
      <div ref={barRef} className="rainbow-bar" />
    </div>
  );
};

export default RainbowBeam;
