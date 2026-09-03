import React, { useEffect, useRef } from "react";

interface ElementCache {
  top: number;
  height: number;
  el: Element;
}

const RainbowBeam: React.FC = () => {
  const barRef = useRef<HTMLDivElement>(null);
  const posY = useRef<number>(-200);
  const cachedPositions = useRef<ElementCache[]>([]);
  const lastScanTime = useRef<number>(0);
  const isVisibleRef = useRef(true);
  const animationFrameIdRef = useRef<number>(0);

  const beamHeight = 80;
  const speed = 3.5;

  useEffect(() => {
    const container = document.querySelector(".rainbow-beam-container");
    if (!container) return;

    const visibilityObserver = new IntersectionObserver(
      ([entry]) => {
        isVisibleRef.current = Boolean(entry?.isIntersecting);
      },
      { threshold: 0 }
    );
    visibilityObserver.observe(container);

    const updateElements = () => {
      const nodeList = document.querySelectorAll(
        "h1, h2, h3, h4, h5, h6, p, a, button, .tab, .filter"
      );
      const scrollY = window.scrollY;
      cachedPositions.current = Array.from(nodeList).map(el => {
        const rect = el.getBoundingClientRect();
        return {
          top: rect.top + scrollY,
          height: rect.height,
          el
        };
      }).filter(item => item.height > 0);
    };

    updateElements();

    let lastFrameTime = 0;
    const frameInterval = 1000 / 60;

    const animate = (time: number) => {
      animationFrameIdRef.current = requestAnimationFrame(animate);

      if (!isVisibleRef.current) return;

      const delta = time - lastFrameTime;
      if (delta < frameInterval) return;
      lastFrameTime = time - (delta % frameInterval);

      if (time - lastScanTime.current > 3000) {
        updateElements();
        lastScanTime.current = time;
      }

      posY.current += speed;
      if (posY.current > window.innerHeight + beamHeight) {
        posY.current = -beamHeight;
      }

      if (barRef.current) {
        barRef.current.style.transform = `translate(-50%, ${posY.current}px)`;
      }

      const beamCenter = posY.current + beamHeight / 2;
      const currentScrollY = window.scrollY;

      for (let i = 0; i < cachedPositions.current.length; i++) {
        const item = cachedPositions.current[i];
        const rectTop = item.top - currentScrollY;
        const rectBottom = rectTop + item.height;

        if (rectBottom < -100 || rectTop > window.innerHeight + 100) {
          item.el.classList.remove("rainbow-active-text");
          continue;
        }

        const elCenter = rectTop + item.height / 2;
        const distance = Math.abs(beamCenter - elCenter);

        if (distance < beamHeight / 2 + item.height / 2) {
          item.el.classList.add("rainbow-active-text");
        } else {
          item.el.classList.remove("rainbow-active-text");
        }
      }
    };

    animationFrameIdRef.current = requestAnimationFrame(animate);

    window.addEventListener("resize", updateElements);

    return () => {
      cancelAnimationFrame(animationFrameIdRef.current);
      visibilityObserver.disconnect();
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
