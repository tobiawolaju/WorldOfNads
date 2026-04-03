import React, { useEffect, useState } from "react";
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
  const [index, setIndex] = useState(0);
  const [stageClass, setStageClass] = useState("");

  const [images, setImages] = useState({
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

      setImages((prev) => ({
        ...prev,
        top,
        bottom
      }));

      setIsMorphing(true);

      setTimeout(() => {
        setImages({ top, center, bottom });
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