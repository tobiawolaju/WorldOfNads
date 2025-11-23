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
        "World of Nads (WONs) is where the chaos of 'Tag' meets the stakes of a Battle Royale. It is a high-fidelity, browser-based competitive arena game powered by Monad. We prioritize 'Fun First'—shifting from the boring 'Play-to-Earn' model to a sustainable 'Play-and-Own' ecosystem.",
    },
    {
      question: "Is the game live?",
      answer:
        "Yes. Unlike many Web3 projects that are just a concept, WONs is a live, playable reality. We are currently in Closed Beta with 200+ active testers and a fully functional browser build. No downloads required.",
    },
    {
      question: "How do I play?",
      answer:
        "You drop into a lobby with up to 20 players for a high-octane 'Chicken Chase.' A chicken spawns in the arena. The objective is simple: be the one holding the chicken when the timer hits 0:00. However, holding the chicken drains your stamina, forcing strategic passes (Hot Potato style) while the map borders shrink.",
    },
    {
      question: "What are the rewards and Tokenomics?",
      answer:
        "We use a sustainable dual-asset economy. Prizes for tournaments are paid in stable assets (USDC/USDT) so winners get guaranteed value. The $WON token is an earned utility token used strictly for cosmetics (Skins, Battle Passes, VFX). There are NO Pay-to-Win mechanics.",
    },
    {
      question: "How does Monad integration work?",
      answer:
        "We use Monad as an invisible backend for speed and trust. The standout feature is 'Instant Payouts.' There is no 'Claim Rewards' button—the moment a match ends, the blockchain settles the result and funds hit the winner's wallet immediately.",
    },
    {
      question: "How can projects partner with WONs?",
      answer:
        "WONs acts as a 'User Acquisition Engine' for the Monad ecosystem. Instead of airdropping tokens to bots, projects can sponsor 'Wager Lobbies' or Tournaments. To win the allocation, users must play the game. Since bots can't win at Nads, partners are guaranteed engagement from real humans.",
    },
    {
      question: "Is it Free-to-Play?",
      answer:
        "Yes. The core game is accessible to everyone. We utilize Privy for seamless onboarding, allowing you to log in with social accounts in under 15 seconds—no wallet seed phrases required to start playing.",
    },
    {
      question: "What prevents bots from farming rewards?",
      answer:
        "Skill. Our gameplay is physics-based and twitch-reflex dependent. Unlike simple 'click-to-earn' DeFi games, WONs requires active movement, strategy, and reaction time, making it impossible for standard scripts to farm rewards.",
    },
    {
      question: "How can I join the Beta?",
      answer:
        "Follow @worldofnads on X (Twitter) and join our Discord. We are gradually expanding our Closed Beta group. We also have reserved whitelist slots for specific partner communities and VC partners.",
    },
  ];

  const toggleFAQ = (index: number) => {
    setActiveIndex(activeIndex === index ? null : index);
  };

  return (
    <div className="faq-container">
      <div style={{ height: '60px' }}></div>
      <h1 className="faq-header">FAQ</h1>
      <p className="faq-subtext" style={{ textAlign: "center", color: "#888", marginBottom: "30px" }}>
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