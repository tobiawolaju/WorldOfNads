import { useRef } from "react";
import { useNavigate } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import { FaDiscord } from "react-icons/fa";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import Rive from "@rive-app/react-canvas";
import "./Home.css";

gsap.registerPlugin(ScrollTrigger);

export default function Home() {
  const { ready, authenticated, login } = usePrivy();
  const navigate = useNavigate();
  const root = useRef<HTMLDivElement>(null);

  useGSAP(() => {
    gsap.from(".title", {
      opacity: 0,
      y: 60,
      duration: 1.6,
      ease: "power3.out",
    });

    gsap.from(".wons-card", {
      opacity: 0,
      y: 40,
      rotation: () => gsap.utils.random(-6, 6),
      stagger: 0.12,
      scrollTrigger: {
        trigger: ".wons-section",
        start: "top 80%",
      },
    });

    gsap.from(".stats-card", {
      opacity: 0,
      y: 30,
      stagger: 0.1,
      scrollTrigger: {
        trigger: ".stats-section",
        start: "top 85%",
      },
    });

    gsap.from(".event-card", {
      opacity: 0,
      y: 30,
      stagger: 0.15,
      scrollTrigger: {
        trigger: ".events-section",
        start: "top 85%",
      },
    });

    gsap.utils.toArray<HTMLElement>(".hover-btn").forEach(btn => {
      gsap.set(btn, { border: "0px solid rgba(255,255,255,.2)" });
      btn.addEventListener("mouseenter", () =>
        gsap.to(btn, { borderWidth: 6, duration: 0.25 })
      );
      btn.addEventListener("mouseleave", () =>
        gsap.to(btn, { borderWidth: 0, duration: 0.25 })
      );
    });
  }, { scope: root });

  const handlePlay = async () => {
    if (!authenticated) await login();
    navigate("/dashboard");
  };

  if (!ready) return null;

  return (
    <div ref={root}>
      <section className="hero-center">
        <h1 className="title">1.2k Nads</h1>
        <Rive src="test.riv" stateMachines="idle" />
      </section>

      <section className="wons-section">
        <div className="wons-grid">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="wons-card" />
          ))}
        </div>
      </section>

      <section className="stats-section">
        <div className="stats-grid">
          {[
            ["0", "Daily Players"],
            ["0", "Total Matches"],
            ["0", "Fucks given"],
            ["$0.00", "Given out"],
          ].map(([v, l]) => (
            <div key={l} className="stats-card">
              <span className="stats-value">{v}</span>
              <div>{l}</div>
            </div>
          ))}
        </div>
      </section>

      <section className="events-section">
        <div className="events-grid">
          {[
            ["Latest on WONs", "Core dev updates"],
            ["WON Batches", "Seasonal waves"],
            ["WON Creators", "2025 creator program"],
          ].map(([h, p]) => (
            <div key={h} className="event-card">
              <h3>{h}</h3>
              <p>{p}</p>
            </div>
          ))}
        </div>
      </section>

      <div className="footer-buttons">
        <a
          className="hover-btn"
          href="https://discord.gg/z4SUdrKayb"
          target="_blank"
          rel="noopener noreferrer"
        >
          <FaDiscord size={28} />
        </a>

        <button className="hover-btn" onClick={handlePlay}>
          {authenticated ? "Lobby" : "Login"}
        </button>
      </div>
    </div>
  );
}
