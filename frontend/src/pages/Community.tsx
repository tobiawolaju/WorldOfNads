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
      question: "What is World of Nads?",
      answer:
        "World of Nads (WONs) is a Web3 gamified engagement ecosystem built on the Monad blockchain. It connects crypto and NFT projects with their communities through fun, skill-based matches that reward active supporters with real on-chain prizes.",
    },
    {
      question: "How does the game work?",
      answer:
        "Players log in, create their character, and join matches on even-numbered days. In each match, you compete to grab and hold a chicken until the 5-minute timer hits zero. The chicken carries your potential reward — win the match, and you claim it.",
    },
    {
      question: "What kind of rewards can I win?",
      answer:
        "Partner projects offer exclusive rewards like free NFT mints, token airdrops, whitelist spots, or access passes. For example, a 9999 NFT collection might reserve 500 free mints for top players that win their matches.",
    },
    {
      question: "How can a project partner with WONs?",
      answer:
        "Projects can apply to become official WON partners and set up their own reward campaigns — defining how many users they want to reward and what they’ll give. This helps them grow engagement while rewarding genuine supporters.",
    },
    {
      question: "What is the WON token?",
      answer:
        "WON is the native stable token of the World of Nads ecosystem — a 1:1 stable asset similar to USDT. Players earn and use WON across matches, rewards, and in-game purchases, and it can be swapped directly for USDT anytime.",
    },
    {
      question: "How do players get started?",
      answer:
        "Simply connect your wallet, create your character, and choose your preferred even-day match. Once the countdown begins, you’ll be matched with other players — and if you hold onto that chicken till the end, the reward is yours.",
    },
    {
      question: "Is it free to play?",
      answer:
        "Yes. World of Nads is free to join and play. Some rewards may require completing partner-specific tasks or holding certain NFTs, but core matches are open to everyone.",
    },
    {
      question: "What chain powers World of Nads?",
      answer:
        "WONs runs on the Monad blockchain — built for high performance, ultra-low fees, and real-time on-chain gameplay at scale.",
    },
    {
      question: "How can I stay updated?",
      answer:
        "Follow @worldofnads on X (Twitter) and join the community to stay informed about upcoming matches, partner drops, and new reward campaigns.",
    },
  ];

  const toggleFAQ = (index: number) => {
    setActiveIndex(activeIndex === index ? null : index);
  };

  return (
    <div className="faq-container">
      <div style={{ height: '60px' }}></div>
      <h1 className="faq-header">FAQ</h1>

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
