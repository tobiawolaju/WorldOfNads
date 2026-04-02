import React, { useEffect, useRef, useState } from "react";
import "./Slide1.css";

const SETS: [string, string, string][] = [
  ["#ff6b6b", "#ffe66d", "#4ecdc4"],
  ["#845ef7", "#5c7cfa", "#339af0"],
  ["#51cf66", "#94d82d", "#fcc419"]
];

const ParallaxStack: React.FC = () => {
  const [index, setIndex] = useState(0);
  const [stageClass, setStageClass] = useState("");

  const [colors, setColors] = useState({
    top: SETS[0][0],
    center: SETS[0][1],
    bottom: SETS[0][2]
  });

  const [nextCenter, setNextCenter] = useState(SETS[0][1]);
  const [isMorphing, setIsMorphing] = useState(false);

  useEffect(() => {
    const interval = setInterval(() => {
      cycle();
    }, 3000);

    return () => clearInterval(interval);
  }, [index]);

  const cycle = () => {
    setStageClass("closing");

    setTimeout(() => {
      const newIndex = (index + 1) % SETS.length;
      const [top, center, bottom] = SETS[newIndex];

      setIndex(newIndex);
      setNextCenter(center);
      setColors((prev) => ({
        ...prev,
        top,
        bottom
      }));

      setIsMorphing(true);

      setTimeout(() => {
        setColors({
          top,
          center,
          bottom
        });
        setIsMorphing(false);
      }, 400);

      setTimeout(() => {
        setStageClass("opening");

        setTimeout(() => {
          setStageClass("");
        }, 1200);
      }, 200);
    }, 1200);
  };

  return (
    <section className="slider">
      <div className="frame">
        <div className={`stage ${stageClass}`}>
          <div
            className="card top"
            style={{ background: colors.top }}
          />

          <div className="card center">
            <div
              className="center-current"
              style={{ background: colors.center }}
            />
            <div
              className={`center-next ${isMorphing ? "active" : ""}`}
              style={{ background: nextCenter }}
            />
          </div>

          <div
            className="card bottom"
            style={{ background: colors.bottom }}
          />
        </div>
      </div>
    </section>
  );
};

export default ParallaxStack;