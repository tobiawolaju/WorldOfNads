import React, { useEffect, useState } from "react";
import "./Slide1.css";

const STACK_SETS = [
  ["/stacked/stacka1.png", "/stacked/stacka2.png", "/stacked/stacka3.png"],
  ["/stacked/stackb1.png", "/stacked/stackb2.png", "/stacked/stackb3.png"],
  ["/stacked/stackc1.png", "/stacked/stackc2.png", "/stacked/stackc3.png"]
];

const MOVE_IN_MS = 2000;
const MOVE_OUT_MS = 2000;
const MORPH_MS = 500;
const CENTER_HOLD_MS = 220;
const HOLD_MS = 320;

const Slide1: React.FC = () => {
  const [setIndex, setSetIndex] = useState(0);
  const [phase, setPhase] = useState<"rest" | "closing" | "opening">("rest");
  const [centerCurrent, setCenterCurrent] = useState(STACK_SETS[0][1]);
  const [centerNext, setCenterNext] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    let cycleTimer: ReturnType<typeof setTimeout> | null = null;
    let moveInTimer: ReturnType<typeof setTimeout> | null = null;
    let centerHoldTimer: ReturnType<typeof setTimeout> | null = null;
    let moveOutTimer: ReturnType<typeof setTimeout> | null = null;
    let morphTimer: ReturnType<typeof setTimeout> | null = null;

    const runCycle = () => {
      if (!active) {
        return;
      }

      setPhase("closing");

      moveInTimer = setTimeout(() => {
        if (!active) {
          return;
        }

        setSetIndex((prevIndex) => {
          const nextIndex = (prevIndex + 1) % STACK_SETS.length;
          const nextCenter = STACK_SETS[nextIndex][1];

          setCenterNext(nextCenter);

          morphTimer = setTimeout(() => {
            if (!active) {
              return;
            }

            setCenterCurrent(nextCenter);
            setCenterNext(null);
          }, MORPH_MS);

          return nextIndex;
        });

        centerHoldTimer = setTimeout(() => {
          if (!active) {
            return;
          }

          setPhase("opening");

          moveOutTimer = setTimeout(() => {
            if (!active) {
              return;
            }

            setPhase("rest");
            cycleTimer = setTimeout(runCycle, HOLD_MS);
          }, MOVE_OUT_MS);
        }, CENTER_HOLD_MS);
      }, MOVE_IN_MS);
    };

    cycleTimer = setTimeout(runCycle, HOLD_MS);

    return () => {
      active = false;
      if (cycleTimer) {
        clearTimeout(cycleTimer);
      }
      if (moveInTimer) {
        clearTimeout(moveInTimer);
      }
      if (centerHoldTimer) {
        clearTimeout(centerHoldTimer);
      }
      if (moveOutTimer) {
        clearTimeout(moveOutTimer);
      }
      if (morphTimer) {
        clearTimeout(morphTimer);
      }
    };
  }, []);

  const currentSet = STACK_SETS[setIndex];

  return (
    <section className="slide1" aria-label="Animated stacked cards">
      <div className="slide1-placeholder">
        <div className="slide1-stage">
        <img
          src={currentSet[0]}
          alt="Stack image 1"
          className={`slide1-card slide1-card-top slide1-phase-${phase}`}
          loading="lazy"
        />

        <div className="slide1-card slide1-card-center" aria-live="off">
          <img src={centerCurrent} alt="Stack image 2" className="slide1-center-current" />
          {centerNext && (
            <img src={centerNext} alt="Stack image 2 next" className="slide1-center-next" />
          )}
        </div>

        <img
          src={currentSet[2]}
          alt="Stack image 3"
          className={`slide1-card slide1-card-bottom slide1-phase-${phase}`}
          loading="lazy"
        />
        </div>
      </div>
    </section>
  );
};

export default Slide1;
