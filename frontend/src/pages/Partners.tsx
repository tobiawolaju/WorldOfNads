import React, { useState } from "react";
import "./Partners.css";

const Partners: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState("");

  // Replaced real partners with Redacted placeholders
  const partners = [
    {
      name: "Redacted",
      logo: "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png",
      handle: "@?????",
      role: "Strategic Partner — Identity hidden until mainnet.",
    },
    {
      name: "Redacted",
      logo: "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png",
      handle: "@?????",
      role: "Infrastructure Ally — Details confidential.",
    },
    {
      name: "Redacted",
      logo: "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png",
      handle: "@?????",
      role: "Community Partner — To be announced.",
    },
    {
      name: "Redacted",
      logo: "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png",
      handle: "@?????",
      role: "Liquidity Provider — Locked.",
    },
    {
      name: "Redacted",
      logo: "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png",
      handle: "@?????",
      role: "Oracle Provider — Announcement pending.",
    },
    {
      name: "Redacted",
      logo: "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png",
      handle: "@?????",
      role: "Scaling Solution — Top Secret.",
    },
    {
      name: "Redacted",
      logo: "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png",
      handle: "@?????",
      role: "Ecosystem Giant — Coming soon.",
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
        The projects building silently with us. 
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
                  <span className="t-handle">{partner.handle}</span>
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