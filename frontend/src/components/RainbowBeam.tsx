import React, { useMemo } from "react";

const BEAM_SPEED_PX_PER_FRAME = 3.5;
const FRAMES_PER_SECOND = 60;
const BEAM_HEIGHT = 80;

const RainbowBeam: React.FC = () => {
  const duration = useMemo(() => {
    if (typeof window === "undefined") return 9;
    const travel = window.innerHeight + BEAM_HEIGHT * 2;
    const speed = BEAM_SPEED_PX_PER_FRAME * FRAMES_PER_SECOND;
    return Math.max(2, travel / speed);
  }, []);

  return (
    <div
      className="rainbow-beam-container"
      style={{ "--beam-duration": `${duration}s` } as React.CSSProperties}
    >
      <div className="rainbow-bar" />
    </div>
  );
};

export default RainbowBeam;