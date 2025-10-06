import React from "react";
import "./Partners.css";

const Partners: React.FC = () => {
  const partners = [
    {
      name: "Azuki",
      logo: "/logos/azuki.png",
      handle: "@Azuki",
      role: "Cultural Partner — bridging art, anime, and Web3 identity.",
    },
    {
      name: "Yuga Labs",
      logo: "/logos/yuga.png",
      handle: "@yugalabs",
      role: "Creative ally building immersive experiences in the metaverse.",
    },
    {
      name: "Ape Yacht Club",
      logo: "/logos/ape.png",
      handle: "@BoredApeYC",
      role: "Community pioneer — redefining digital ownership and culture.",
    },
    {
      name: "Blur",
      logo: "/logos/blur.png",
      handle: "@blur_io",
      role: "Marketplace infrastructure partner for NFT liquidity and data.",
    },
    {
      name: "Chainlink",
      logo: "/logos/chainlink.png",
      handle: "@chainlink",
      role: "Oracle partner — powering on-chain automation and data feeds.",
    },
    {
      name: "Polygon",
      logo: "/logos/polygon.png",
      handle: "@0xPolygon",
      role: "Scaling partner — enabling seamless, low-cost transactions.",
    },
    {
      name: "Base",
      logo: "/logos/base.png",
      handle: "@base",
      role: "Ecosystem ally — building the next generation of on-chain apps.",
    },
  ];

  return (
    <div className="partners-container">
      <div style={{ height: "60px" }}></div>

      <h1 className="partners-title">Our Partners</h1>
      <p className="partners-description">
        Collaborating with visionary teams shaping the decentralized future.
        Together, we’re building a more open, powerful, and connected on-chain world.
      </p>

      <div className="partners-grid">
        {partners.map((partner, index) => (
          <div key={index} className="partner-card">
            <img src={partner.logo} alt={partner.name} className="partner-logo" />
            <p className="partner-name">{partner.name}</p>
            <a
              href={`https://x.com/${partner.handle.replace("@", "")}`}
              target="_blank"
              rel="noopener noreferrer"
              className="partner-handle"
            >
              {partner.handle}
            </a>
            <p className="partner-role">{partner.role}</p>
          </div>
        ))}
      </div>
    </div>
  );
};

export default Partners;
