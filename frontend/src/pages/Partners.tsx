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
     Meet Our Offical Partners   </p>

      <div className="search-wrapper">
        <input
          type="text"
          placeholder="Search for a partner..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="partner-search"
        />
      </div>

  <div className="partners-timeline">
  {filteredPartners.length > 0 ? (
    filteredPartners.map((partner, index) => (
      <div
        key={index}
        className={`timeline-item ${index % 2 === 0 ? "left" : "right"}`}
      >
        <div className="timeline-content">
          <img src={partner.logo} alt={partner.name} className="t-logo" />

          <div className="t-info">
            <h2>{partner.name}</h2>
            <a
              href={`https://x.com/${partner.handle.replace("@", "")}`}
              target="_blank"
              rel="noopener noreferrer"
              className="t-handle"
            >
              {partner.handle}
            </a>
            <p>{partner.role}</p>
          </div>
        </div>
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
