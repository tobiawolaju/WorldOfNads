import React, { useState } from "react";
import "./Partners.css";
import Footer from "../components/Footer";

type Host = {
  name: string;
  logo: string;
  handle: string;
  bio: string;
  matchesHosted: string;
  totalPaidOut: string;
  playersReached: string;
  joined: string;
  liveMatches: number;
  siteUrl: string;
};

const Partners: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState("");
  const hasHosts = true;

  const partners: Host[] = [
    {
      name: "Chog.fun",
      logo: "https://pbs.twimg.com/profile_images/2066836431557832705/eGhU_mNe_400x400.jpg",
      handle: "@chogfun",
      bio: "Build with Chog. Launch with Chog. Chog World Order.",
      matchesHosted: "0",
      totalPaidOut: "$0",
      playersReached: "0",
      joined: "2026",
      liveMatches: 0,
      siteUrl: "https://chog.fun/",
    },
    {
      name: "World of Nads",
      logo: "https://pbs.twimg.com/profile_images/2098026275784785926/ZrpbNv7J_400x400.jpg",
      handle: "@WorldOfNads",
      bio: "Capture the chicken Royal game set in the world of NADs! In early development.",
      matchesHosted: "0",
      totalPaidOut: "$0",
      playersReached: "0",
      joined: "2026",
      liveMatches: 0,
      siteUrl: "https://worldofnads.xyz",
    },
  ];

  // Filter hosts based on search term
  const filteredPartners = partners.filter((partner) =>
    `${partner.name} ${partner.handle}`.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="partners-container">
      <div style={{ height: "60px" }}></div>

      <h1 className="partners-title">Hosts</h1>
      <p className="partners-description">
        The ones driving the competition.
      </p>

      <div className="search-wrapper">
        <input
          type="text"
          placeholder="Search for a host..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="partner-search"
        />
      </div>

      <div className="partners-timeline">
        {hasHosts ? (
          filteredPartners.length > 0 ? (
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
                    <p>{partner.bio}</p>
                    <div className="host-stats">
                      <p><strong>Matches Hosted:</strong> {partner.matchesHosted}</p>
                      <p><strong>Total Paid Out:</strong> {partner.totalPaidOut}</p>
                      <p><strong>Players Reached:</strong> {partner.playersReached}</p>
                      <p><strong>Joined:</strong> {partner.joined}</p>
                    </div>
                    <div className="host-actions">
                      <a href={partner.siteUrl} target="_blank" rel="noopener noreferrer" className="host-action-link">Visit Site</a>
                      <a href="#" className="host-action-link">View Live Matches ({partner.liveMatches})</a>
                    </div>
                  </div>
                </div>
              </div>
            ))
          ) : (
            <p className="text-inline-gray" style={{ marginTop: "40px" }}>
              No matching hosts found.
            </p>
          )
        ) : (
          <div className="no-hosts">
            No hosts at the moment.
            <br />
            Want to host? Reach out via <a href="https://x.com/worldofnads" target="_blank" rel="noopener noreferrer">X/DM</a> to join.
          </div>
        )}
      </div>
      <Footer />
    </div>
  );
};

export default Partners;
