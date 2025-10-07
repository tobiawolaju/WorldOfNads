import React, { useState } from "react";
import "./FAQ.css";

interface FAQItem {
  question: string;
  answer: string;
}

const FAQ: React.FC = () => {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  const faqs: FAQItem[] = [
    {
      question: "What is this project about?",
      answer:
        "It’s a next-generation robotics and AI ecosystem built to make powerful technology accessible to everyone — open, affordable, and human-centered.",
    },
    {
      question: "How can I participate or contribute?",
      answer:
        "You can join our open community discussions, contribute code, or collaborate through partner programs once applications reopen.",
    },
    {
      question: "Is there a token or on-chain component?",
      answer:
        "Yes. The system is powered by on-chain governance, reward distribution, and data exchange mechanisms — more details will be shared soon.",
    },
    {
      question: "When will recruitment open?",
      answer:
        "We’re currently building core infrastructure and not hiring yet, but you can stay updated through our newsletter and socials.",
    },
    {
      question: "How do I contact the team?",
      answer:
        "You can reach out through our official Twitter or email once public contact channels are available.",
    },
  ];

  const toggleFAQ = (index: number) => {
    setActiveIndex(activeIndex === index ? null : index);
  };

  return (
    <div className="faq-container">
      <div style={{ height: "60px" }}></div>
      <h1 className="faq-header">FA Questions</h1>

      <div className="faq-list">
        {faqs.map((item, index) => (
          <div
            key={index}
            className={`faq-item ${activeIndex === index ? "active" : ""}`}
            onClick={() => toggleFAQ(index)}
          >
            <div className="faq-question">
              <span>{item.question}</span>
              <span className="faq-icon">{activeIndex === index ? "–" : "+"}</span>
            </div>
            <div className="faq-answer">{item.answer}</div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default FAQ;
