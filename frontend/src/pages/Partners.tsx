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
};

const Partners: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState("");

  const partners: Host[] = [
    {
      name: "KizzyBean",
      logo: "/partners/kizzy.webp",
      handle: "@kizzybean",
      bio: "Funding competitive matches across WONs.",
      matchesHosted: "1,240",
      totalPaidOut: "$3,800",
      playersReached: "9,200",
      joined: "Jan 2026",
      liveMatches: 12,
    },
    {
      name: "Mayan Circuit",
      logo: "/partners/mayan.webp",
      handle: "@mayancircuit",
      bio: "Running weekly spotlight brackets for rising players.",
      matchesHosted: "980",
      totalPaidOut: "$2,950",
      playersReached: "7,450",
      joined: "Feb 2026",
      liveMatches: 9,
    },
    {
      name: "Rug Arena",
      logo: "/partners/rugrumble.webp",
      handle: "@rugarena",
      bio: "Back-to-back community tournaments with instant payouts.",
      matchesHosted: "1,520",
      totalPaidOut: "$4,420",
      playersReached: "11,300",
      joined: "Dec 2025",
      liveMatches: 15,
    },
    {
      name: "Bean Exchange",
      logo: "/partners/beanexchange.webp",
      handle: "@beanexchange",
      bio: "Powering creator-hosted match days on WONs.",
      matchesHosted: "760",
      totalPaidOut: "$2,100",
      playersReached: "5,980",
      joined: "Mar 2026",
      liveMatches: 6,
    },
    {
      name: "Grimmys League",
      logo: "/partners/grimmys.webp",
      handle: "@grimmysleague",
      bio: "Hosting high-stakes finals with top leaderboard players.",
      matchesHosted: "640",
      totalPaidOut: "$1,880",
      playersReached: "4,720",
      joined: "Nov 2025",
      liveMatches: 5,
    },
    {
      name: "Perpl Plays",
      logo: "/partners/perpl.webp",
      handle: "@perplplays",
      bio: "Creator showmatches bringing new players into competition.",
      matchesHosted: "890",
      totalPaidOut: "$2,640",
      playersReached: "6,860",
      joined: "Jan 2026",
      liveMatches: 8,
    },
    {
      name: "Neverland Cups",
      logo: "/partners/neverland.webp",
      handle: "@neverlandcups",
      bio: "Building seasonal ladders and sponsor-backed prize pools.",
      matchesHosted: "1,130",
      totalPaidOut: "$3,200",
      playersReached: "8,540",
      joined: "Feb 2026",
      liveMatches: 11,
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
                  <p>{partner.bio}</p>
                  <div className="host-stats">
                    <p><strong>Matches Hosted:</strong> {partner.matchesHosted}</p>
                    <p><strong>Total Paid Out:</strong> {partner.totalPaidOut}</p>
                    <p><strong>Players Reached:</strong> {partner.playersReached}</p>
                    <p><strong>Joined:</strong> {partner.joined}</p>
                  </div>
                  <div className="host-actions">
                    <a href="#" className="host-action-link">View Merch</a>
                    <a href="#" className="host-action-link">View Live Matches ({partner.liveMatches})</a>
                  </div>
                </div>
              </div>
            </div>
          ))
        ) : (
          <p style={{ marginTop: "40px", color: "#777" }}>
            No matching hosts found.
          </p>
        )}
      </div>
      <Footer />
    </div>
  );
};

export default Partners;
