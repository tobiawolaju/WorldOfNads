import { useEffect, useState } from "react";
import "./Slide1.css";

const STACK_SETS = [
  ["/stacked/stacka1.png", "/stacked/stacka2.png", "/stacked/stacka3.png"],
  ["/stacked/stackb1.png", "/stacked/stackb2.png", "/stacked/stackb3.png"],
  ["/stacked/stackc1.png", "/stacked/stackc2.png", "/stacked/stackc3.png"]
];

export default function Slide1() {
  const [index, setIndex] = useState(0);
  const [stage, setStage] = useState<"closing" | "opening" | "">("");
  const [centerCurrent, setCenterCurrent] = useState(STACK_SETS[0][1]);
  const [centerNext, setCenterNext] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    const run = () => {
      if (!mounted) return;

      setStage("closing");

      setTimeout(() => {
        if (!mounted) return;

        const nextIndex = (index + 1) % STACK_SETS.length;
        const nextCenter = STACK_SETS[nextIndex][1];

        setIndex(nextIndex);
        setCenterNext(nextCenter);

        // morph center
        setTimeout(() => {
          if (!mounted) return;
          setCenterCurrent(nextCenter);
          setCenterNext(null);
        }, 400);

        // open back
        setTimeout(() => {
          if (!mounted) return;

          setStage("opening");

          setTimeout(() => {
            if (!mounted) return;
            setStage("");
          }, 1200);

        }, 200);

      }, 1200);
    };

    const interval = setInterval(run, 3000);
    run(); // start immediately

    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, [index]);

  const current = STACK_SETS[index];

  return (
    <section className="slide1">
      <div className="slide1-slider">
        <div className="slide1-frame">
          <div className={`slide1-stage ${stage}`}>

            <img src={current[0]} className="slide1-card slide1-top" />

            <div className="slide1-card slide1-center">
              <img src={centerCurrent} className="slide1-center-current" />
              {centerNext && (
                <img
                  src={centerNext}
                  className="slide1-center-next slide1-active"
                />
              )}
            </div>

            <img src={current[2]} className="slide1-card slide1-bottom" />

          </div>
        </div>
      </div>
    </section>
  );
}