import React, { useEffect, useState } from "react";
import "./Slide1.css";

type Props = {
  interval?: number;
};

const SETS: [string, string, string][] = [
  ["#f9e0ffff", "#f8c5ffff", "#f9e0ffff"],
  ["#dff1ffff", "#ced8ffff", "#dff1ffff"],
  ["#ffdbffff", "#e8ffc6ff", "#ffdbffff"]
];

const Slide1: React.FC<Props> = ({ interval = 3000 }) => {
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
    const id = setInterval(cycle, interval);
    return () => clearInterval(id);
  }, [index, interval]);

  const cycle = () => {
    setStageClass("ps-closing");

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
        setColors({ top, center, bottom });
        setIsMorphing(false);
      }, 400);

      setTimeout(() => {
        setStageClass("ps-opening");

        setTimeout(() => {
          setStageClass("");
        }, 1200);
      }, 200);
    }, 1200);
  };

  return (
    <div className="ps-root">
      <div className="ps-frame">
        <div className={`ps-stage ${stageClass}`}>
          <div
            className="ps-card ps-top"
            style={{ background: colors.top }}
          />

          <div className="ps-card ps-center">
            <div
              className="ps-center-current"
              style={{ background: colors.center }}
            />
            <div
              className={`ps-center-next ${isMorphing ? "ps-active" : ""
                }`}
              style={{ background: nextCenter }}
            />
          </div>

          <div
            className="ps-card ps-bottom"
            style={{ background: colors.bottom }}
          />
        </div>
      </div>
    </div>
  );
};

export default Slide1;