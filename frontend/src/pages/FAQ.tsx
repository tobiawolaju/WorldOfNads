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
        "World of Nads (WONs) is a competitive arena where players fight for recognition. 100 players enter. Only the best rise. Every match is about outplaying others and earning your place.",
    },
    {
      question: "Is the game live?",
      answer:
        "Yes. The arena is already active. You can jump into matches instantly in your browser. No downloads. No waiting.",
    },
    {
      question: "How does the game work?",
      answer:
        "Players enter the arena and fight for control of the objective. You’ll need to move, dodge, and outplay everyone else. It’s fast, chaotic, and purely skill-driven.",
    },
    {
      question: "What makes it different?",
      answer:
        "Every match matters. There are no bots, no shortcuts, and no artificial advantages. You win because you're better — not because you grinded longer.",
    },
    {
      question: "What happens when you win?",
      answer:
        "You move closer to the top. Some matches include rewards, but more importantly, wins build your position toward recognition.",
    },
    {
      question: "What does it mean to be a Nad?",
      answer:
        "Nads are the top players. Every month resets, and only the top 10 earn recognition as Nads. It’s a status earned through skill, not given.",
    },
    {
      question: "What if I missed early opportunities?",
      answer:
        "Then this is your way back. Some players fumbled early. Some missed their moment. The arena resets everything. You earn it here.",
    },
    {
      question: "Who creates the matches?",
      answer:
        "Some matches are backed by sponsors who want to be part of the competition. They shape the arena, but players decide the outcome.",
    },
    {
      question: "Why do sponsors get involved?",
      answer:
        "Because this is where real competition happens. Instead of interrupting gameplay, they become part of it — visible while players are fully engaged.",
    },
    {
      question: "Is the game free to play?",
      answer:
        "Yes. Anyone can enter the arena for free and start competing immediately.",
    },
    {
      question: "Can the game be automated or exploited?",
      answer:
        "No. Winning requires real-time decisions, movement, and awareness. You have to be present and skilled to rise.",
    },
    {
      question: "Is World of Nads an investment?",
      answer:
        "No. It’s a competitive game. The focus is on skill, recognition, and gameplay — not speculation.",
    },
    {
      question: "Who is this for?",
      answer:
        "Anyone who enjoys fast, competitive gameplay and wants to prove they’re better than the rest.",
    },
    {
      question: "Why do players keep coming back?",
      answer:
        "Because every match is different, and every win matters. You’re always chasing position, recognition, and the chance to become a Nad.",
    },
    {
      question: "How can I join early?",
      answer:
        "Join the waitlist and Discord to access early matches and compete before everyone else.",
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
