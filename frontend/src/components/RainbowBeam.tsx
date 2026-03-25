import React, { useEffect, useRef } from "react";

const RainbowBeam: React.FC = () => {
  const barRef = useRef<HTMLDivElement>(null);
  const posY = useRef<number>(-200);
  const beamHeight = 200;
  const speed = 2.5; // Slightly slower for a more premium, elegant feel

  useEffect(() => {
    let animationFrameId: number;

    const animate = () => {
      posY.current += speed;
      if (posY.current > window.innerHeight + beamHeight) {
        posY.current = -beamHeight;
      }

      if (barRef.current) {
        barRef.current.style.top = `${posY.current}px`;
      }

      animationFrameId = requestAnimationFrame(animate);
    };

    animationFrameId = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(animationFrameId);
    };
  }, []);

  return (
    <div className="rainbow-beam-container">
      <div ref={barRef} className="rainbow-bar" />
    </div>
  );
};

export default RainbowBeam;
