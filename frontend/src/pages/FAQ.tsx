import React, { useState } from "react";
import "./FAQ.css";
import Footer from "../components/Footer";

interface FAQItem {
  question: string;
  answer: string;
}

const FAQ: React.FC = () => {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  const faqs: FAQItem[] = [
    {
      question: "What is World of Nads?",
      answer:
        "World of Nads (WONs) is a fast-paced multiplayer arena game built for the browser and powered by the Monad blockchain. It blends the chaos of playground games like Tag with the intensity of battle-royale competition. The focus is simple: fun gameplay first, real rewards second.",
    },
    {
      question: "Is the game live?",
      answer:
        "Yes. World of Nads already has a playable browser build. Players can jump into matches instantly with no downloads required. The game is currently in active testing as we expand features and prepare for a larger public release.",
    },
    {
      question: "How does the game work?",
      answer:
        "Players drop into a chaotic arena where a chicken spawns in the center. The goal is simple: be the player holding the chicken when the timer reaches zero. Holding the chicken drains stamina, forcing players to move quickly, dodge opponents, and strategically pass it before time runs out.",
    },
    {
      question: "What rewards do players earn?",
      answer:
        "Matches and tournaments are funded using MON, the native token of the Monad network. Sponsors deposit prizes before the match starts, and when a match ends the winner automatically receives the reward on-chain. There are no manual claims and no hidden steps.",
    },
    {
      question: "Why is the game built on Monad?",
      answer:
        "Monad provides extremely fast transaction processing with low fees. This allows match results to settle instantly on-chain while keeping the gameplay experience smooth and responsive for players.",
    },
    {
      question: "Is the game free to play?",
      answer:
        "Yes. Anyone can start playing for free. Players can sign in using simple social login through Privy, which creates a wallet automatically behind the scenes. This removes the usual blockchain friction and lets players start playing within seconds.",
    },
    {
      question: "How do sponsored matches work?",
      answer:
        "Projects or communities can sponsor matches by funding a prize pool using MON. Players compete for the reward inside the arena. This creates a new way for projects to distribute incentives through gameplay instead of traditional airdrops.",
    },
    {
      question: "What prevents bots from farming rewards?",
      answer:
        "The game is skill-based and physics-driven. Winning requires movement, reaction time, and strategy inside a real-time arena. This makes it extremely difficult for automated scripts or bots to farm rewards.",
    },
    {
      question: "How can I join early?",
      answer:
        "Follow @worldofnads on X and join the community Discord to stay updated on playtests, tournaments, and early access opportunities."
    }
  ];

  const toggleFAQ = (index: number) => {
    setActiveIndex(activeIndex === index ? null : index);
  };

  return (
    <div className="faq-container">
      <div style={{ height: "60px" }}></div>

      <h1 className="faq-header">FAQ</h1>

      <p
        className="faq-subtext"
        style={{
          textAlign: "center",
          color: "#888",
          marginBottom: "30px"
        }}
      >
        Everything you need to know about the Arena.
      </p>

      <div className="faq-list">
        {faqs.map((item, index) => (
          <div
            key={index}
            className={`faq-item ${activeIndex === index ? "active" : ""}`}
            onClick={() => toggleFAQ(index)}
          >
            <div className="faq-question">
              <span>{item.question}</span>
              <span className="faq-icon">
                {activeIndex === index ? "–" : "+"}
              </span>
            </div>

            <div className="faq-answer">{item.answer}</div>
          </div>
        ))}
      </div>
      <Footer />
    </div>
  );
};

export default FAQ;
