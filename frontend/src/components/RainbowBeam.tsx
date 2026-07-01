import React, { useEffect, useRef } from "react";

interface ElementCache {
  top: number;
  height: number;
  el: Element;
}

const RainbowBeam: React.FC = () => {
  const barRef = useRef<HTMLDivElement>(null);
  const posY = useRef<number>(-200);
  const elementsRef = useRef<Element[]>([]);
  const cachedPositions = useRef<ElementCache[]>([]);
  const lastScanTime = useRef<number>(0);
  
  const beamHeight = 80;
  const speed = 3.5;

  useEffect(() => {
    let animationFrameId: number;

    const updateElements = () => {
      const nodeList = document.querySelectorAll(
        "h1, h2, h3, h4, h5, h6, p, a, button, .tab, .filter"
      );
      elementsRef.current = Array.from(nodeList);
      
      const scrollY = window.scrollY;
      cachedPositions.current = elementsRef.current.map(el => {
        const rect = el.getBoundingClientRect();
        return {
          top: rect.top + scrollY,
          height: rect.height,
          el
        };
      }).filter(item => item.height > 0);
    };

    updateElements();

    const animate = (time: number) => {
      // Recalibrate DOM element positions every 2 seconds to handle dynamic sizing
      if (time - lastScanTime.current > 2000) {
        updateElements();
        lastScanTime.current = time;
      }

      posY.current += speed;
      if (posY.current > window.innerHeight + beamHeight) {
        posY.current = -beamHeight;
      }

      if (barRef.current) {
        // GPU-accelerated transform avoiding inline "style.top" DOM recalculations
        barRef.current.style.transform = `translate(-50%, ${posY.current}px)`;
      }

      const beamCenter = posY.current + beamHeight / 2;
      const currentScrollY = window.scrollY;

      cachedPositions.current.forEach((item) => {
        const rectTop = item.top - currentScrollY;
        const rectBottom = rectTop + item.height;
        
        if (rectBottom < -100 || rectTop > window.innerHeight + 100) {
          item.el.classList.remove("rainbow-active-text");
          return;
        }

        const elCenter = rectTop + item.height / 2;
        const distance = Math.abs(beamCenter - elCenter);

        if (distance < beamHeight / 2 + item.height / 2) {
          item.el.classList.add("rainbow-active-text");
        } else {
          item.el.classList.remove("rainbow-active-text");
        }
      });

      animationFrameId = requestAnimationFrame(animate);
    };

    animationFrameId = requestAnimationFrame(animate);

    window.addEventListener("resize", updateElements);

    return () => {
      cancelAnimationFrame(animationFrameId);
      window.removeEventListener("resize", updateElements);
      cachedPositions.current.forEach(item => item.el.classList.remove("rainbow-active-text"));
    };
  }, []);

  return (
    <div className="rainbow-beam-container">
      <div ref={barRef} className="rainbow-bar" style={{ top: 0 }} />
    </div>
  );
};

export default RainbowBeam;
