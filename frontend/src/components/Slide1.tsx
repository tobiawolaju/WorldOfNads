import React, { useEffect, useRef, useState } from "react";
import "./Slide1.css";

type Props = {
  interval?: number;
};

const SETS: [string, string, string][] = [
  ["/stacked/stacka1.png", "/stacked/stacka2.png", "/stacked/stacka3.png"],
  ["/stacked/stackb1.png", "/stacked/stackb2.png", "/stacked/stackb3.png"],
  ["/stacked/stackc1.png", "/stacked/stackc2.png", "/stacked/stackc3.png"]
];

const Slide1: React.FC<Props> = ({ interval = 3000 }) => {
  const [stageClass, setStageClass] = useState("");

  const [images, setImages] = useState({
    top: SETS[0][0],
    center: SETS[0][1],
    bottom: SETS[0][2]
  });

  const [nextCenter, setNextCenter] = useState(SETS[0][1]);
  const [isMorphing, setIsMorphing] = useState(false);
  const indexRef = useRef(0);
  const cycleRunningRef = useRef(false);
  const timeoutRefs = useRef<number[]>([]);

  const clearTimers = () => {
    timeoutRefs.current.forEach((timeoutId) => clearTimeout(timeoutId));
    timeoutRefs.current = [];
  };

  useEffect(() => {
    const cycle = () => {
      if (cycleRunningRef.current) return;
      cycleRunningRef.current = true;

      setStageClass("ps-closing");

      const closeTimeout = window.setTimeout(() => {
        const newIndex = (indexRef.current + 1) % SETS.length;
        const [top, center, bottom] = SETS[newIndex];

        indexRef.current = newIndex;
        setNextCenter(center);

        setImages((prev) => ({
          ...prev,
          top,
          bottom
        }));

        setIsMorphing(true);

        const morphTimeout = window.setTimeout(() => {
          setImages({ top, center, bottom });
          setIsMorphing(false);
        }, 400);

        timeoutRefs.current.push(morphTimeout);

        const openingTimeout = window.setTimeout(() => {
          setStageClass("ps-opening");

          const resetTimeout = window.setTimeout(() => {
            setStageClass("");
            cycleRunningRef.current = false;
          }, 1200);

          timeoutRefs.current.push(resetTimeout);
        }, 200);

        timeoutRefs.current.push(openingTimeout);
      }, 1200);

      timeoutRefs.current.push(closeTimeout);
    };

    const id = window.setInterval(cycle, interval);
    return () => {
      clearInterval(id);
      clearTimers();
      cycleRunningRef.current = false;
    };
  }, [interval]);

  return (
    <div className="ps-root">
      <div className="ps-frame">
        <div className={`ps-stage ${stageClass}`}>

          {/* TOP */}
          <div
            className="ps-card ps-top"
            style={{ backgroundImage: `url(${images.top})` }}
          />

          {/* CENTER */}
          <div className="ps-card ps-center">
            <div
              className="ps-center-current"
              style={{ backgroundImage: `url(${images.center})` }}
            />
            <div
              className={`ps-center-next ${isMorphing ? "ps-active" : ""}`}
              style={{ backgroundImage: `url(${nextCenter})` }}
            />
          </div>

          {/* BOTTOM */}
          <div
            className="ps-card ps-bottom"
            style={{ backgroundImage: `url(${images.bottom})` }}
          />

        </div>
      </div>
    </div>
  );
};

export default Slide1;
