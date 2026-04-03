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
        "World of Nads (WONs) is a fast-paced multiplayer arena built around pure competition. You jump in, chase the objective, outplay other players, and try to win. It’s chaotic, skill-based, and designed to be genuinely fun from the first match.",
    },
    {
      question: "Is the game live?",
      answer:
        "Yes. World of Nads already has a playable browser build. You can jump into matches instantly with no downloads. It’s currently in active testing as we expand features and prepare for a wider public release.",
    },
    {
      question: "How does the game work?",
      answer:
        "Players enter a chaotic arena where a chicken spawns in the center. The goal is simple: be the one holding it when the timer ends. Holding it drains stamina, so you have to move, dodge, and outplay everyone else. It’s fast, unpredictable, and heavily skill-based.",
    },
    {
      question: "Why do people keep playing?",
      answer:
        "Because every match feels different. It’s quick, chaotic, and competitive. You’re constantly reacting, chasing, escaping, and making split-second decisions. Winning feels earned, and the tension never really drops.",
    },
    {
      question: "What happens when you win?",
      answer:
        "You win the match. In certain games, there’s an added reward waiting for the winner. No extra steps, no interruptions — it’s all part of the experience.",
    },
    {
      question: "Who sets up these matches?",
      answer:
        "Some matches are backed by sponsors who want to be part of the action. They set the stage, players bring the competition, and everything plays out in real time.",
    },
    {
      question: "Why do sponsors get involved?",
      answer:
        "Because it’s where real players are active. Instead of interrupting gameplay, they become part of it — showing up inside matches players already want to play and staying visible while the action is happening.",
    },
    {
      question: "Is the game free to play?",
      answer:
        "Yes. Anyone can start playing for free. You can jump in quickly and get into matches without any setup.",
    },
    {
      question: "Can the game be automated or exploited?",
      answer:
        "Not really. The game relies on real-time movement, reactions, and decision-making. You have to be present, aware, and skilled to win.",
    },
    {
      question: "Is World of Nads an investment?",
      answer:
        "No. It’s a game built around competition and enjoyment. The focus is on creating something people genuinely want to play and come back to.",
    },
    {
      question: "Who is this for?",
      answer:
        "Anyone who enjoys fast, competitive games. If you like quick matches, chaotic gameplay, and outplaying real opponents, you’ll feel right at home.",
    },
    {
      question: "Why can World of Nads grow beyond one game?",
      answer:
        "The core idea is simple: competitive matches that people enjoy playing and coming back to. As more players join, more matches run, and more sponsors take part. The experience scales naturally with activity, without changing how the game feels.",
    },
    {
      question: "How can I join early?",
      answer:
        "Follow @worldofnads on X and join the Discord to stay updated on playtests, tournaments, and early access.",
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
