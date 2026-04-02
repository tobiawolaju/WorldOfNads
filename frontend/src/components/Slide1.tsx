import React, { useEffect, useRef, useState } from "react";
import "./Slide1.css";

const STACK_SETS = [
  ["/stacked/stacka1.png", "/stacked/stacka2.png", "/stacked/stacka3.png"],
  ["/stacked/stackb1.png", "/stacked/stackb2.png", "/stacked/stackb3.png"],
  ["/stacked/stackc1.png", "/stacked/stackc2.png", "/stacked/stackc3.png"]
];

const CLOSE_MS = 2000;
const OPEN_MS = 2000;
const MORPH_MS = 400;
const BEHIND_HOLD_MS = 200;
const LOOP_MS = CLOSE_MS + BEHIND_HOLD_MS + OPEN_MS + 800;

const Slide1: React.FC = () => {
  const [setIndex, setSetIndex] = useState(0);
  const [stageClass, setStageClass] = useState("");
  const [centerCurrent, setCenterCurrent] = useState(STACK_SETS[0][1]);
  const [centerNext, setCenterNext] = useState<string | null>(null);
  const setIndexRef = useRef(0);

  useEffect(() => {
    let active = true;
    let interval: ReturnType<typeof setInterval> | null = null;
    let closeTimer: ReturnType<typeof setTimeout> | null = null;
    let behindTimer: ReturnType<typeof setTimeout> | null = null;
    let openTimer: ReturnType<typeof setTimeout> | null = null;
    let morphTimer: ReturnType<typeof setTimeout> | null = null;

    const runCycle = () => {
      if (!active) {
        return;
      }

      setStageClass("closing");

      closeTimer = setTimeout(() => {
        if (!active) {
          return;
        }

        const nextIndex = (setIndexRef.current + 1) % STACK_SETS.length;
        const nextCenter = STACK_SETS[nextIndex][1];

        setIndexRef.current = nextIndex;
        setSetIndex(nextIndex);
        setCenterNext(nextCenter);

        morphTimer = setTimeout(() => {
          if (!active) {
            return;
          }

          setCenterCurrent(nextCenter);
          setCenterNext(null);
        }, MORPH_MS);

        behindTimer = setTimeout(() => {
          if (!active) {
            return;
          }

          setStageClass("opening");

          openTimer = setTimeout(() => {
            if (!active) {
              return;
            }

            setStageClass("");
          }, OPEN_MS);
        }, BEHIND_HOLD_MS);
      }, CLOSE_MS);
    };

    runCycle();
    interval = setInterval(runCycle, LOOP_MS);

    return () => {
      active = false;
      if (interval) {
        clearInterval(interval);
      }
      if (closeTimer) {
        clearTimeout(closeTimer);
      }
      if (behindTimer) {
        clearTimeout(behindTimer);
      }
      if (openTimer) {
        clearTimeout(openTimer);
      }
      if (morphTimer) {
        clearTimeout(morphTimer);
      }
    };
  }, []);

  const currentSet = STACK_SETS[setIndex];

  return (
    <section className="slide1" aria-label="Animated stacked cards">
      <div className="slide1-slider">
        <div className="slide1-frame">
          <div className={`slide1-stage ${stageClass}`}>
        <img
          src={currentSet[0]}
          alt="Stack image 1"
          className="slide1-card slide1-top"
          loading="lazy"
        />

        <div className="slide1-card slide1-center" aria-live="off">
          <img src={centerCurrent} alt="Stack image 2" className="slide1-center-current" />
          {centerNext && (
            <img src={centerNext} alt="Stack image 2 next" className="slide1-center-next slide1-active" />
          )}
        </div>

        <img
          src={currentSet[2]}
          alt="Stack image 3"
          className="slide1-card slide1-bottom"
          loading="lazy"
        />
          </div>
        </div>
      </div>
    </section>
  );
};

export default Slide1;
