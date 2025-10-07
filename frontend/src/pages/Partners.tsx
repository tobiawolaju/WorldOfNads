import React, { useState } from "react";
import "./Partners.css";

const Partners: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState("");

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

  // Filter partners based on search term
  const filteredPartners = partners.filter((partner) =>
    partner.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="partners-container">
      <div style={{ height: "60px" }}></div>

      <h1 className="partners-title">Our Partners</h1>
      <p className="partners-description">
        The 9999 projects built on Monad that makes WONs WONs
      </p>

      <div className="search-wrapper">
        <input
          type="text"
          placeholder="Search for a partner..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="partner-search"
        />
      </div>

      <div className="partners-grid">
        {filteredPartners.length > 0 ? (
          filteredPartners.map((partner, index) => (
            <div key={index} className="partner-card">
              <img
                src={partner.logo}
                alt={partner.name}
                className="partner-logo"
              />
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
          ))
        ) : (
          <p style={{ marginTop: "40px", color: "#777" }}>
            No matching partners found.
          </p>
        )}
      </div>
    </div>
  );
};

export default Partners;
