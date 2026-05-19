import React, { useState } from "react";
import "./Careers.css";
import Footer from "../components/Footer";

interface TeamMember {
    name: string;
    role: string;
    imageUrl: string;
    summary?: string[];
}

interface JobRole {
    title: string;
    category: string;
    pay: string;
    description: string[];
    responsibilities: string[];
    requirements: string[];
    bonus: string[];
}

const jobRoles: JobRole[] = [
    {
        title: "Co-Founder, Business & Fundraising",
        category: "Open Role",
        pay: "Pre-raise: Equity only (20–30%, 4yr vest / 1yr cliff) | Post-raise: $3,000–$6,000 / month + equity",
        description: [
            "The deal closer. You run the business so Tobi can run the product.",
            "Lead investor-facing operations and scale the business side of World of Nads."
        ],
        responsibilities: [
            "Lead all VC outreach, investor meetings, and fundraising rounds.",
            "Build and own the pitch deck and financial model.",
            "Handle legal structure, company formation, and compliance.",
            "Close BD deals with ecosystem sponsors, partners, and press.",
            "Represent the business side in meetings without Tobi present.",
            "Define go-to-market strategy alongside the Growth Lead."
        ],
        requirements: [
            "Has raised a funding round before or worked directly inside a VC/startup.",
            "Strong existing network in gaming, Web3, or mobile apps.",
            "Can sell the vision without needing hand-holding.",
            "US or Asia based preferred (network access for fundraising).",
            "Ages 21–35, independent thinker.",
            "Technically literate (does not need to code but must understand the product)."
        ],
        bonus: ["Priority role for immediate fundraising acceleration."]
    },
    {
        title: "Growth Lead, Web2 Marketing",
        category: "Open Role",
        pay: "Pre-raise: $300–$600 / month + 0.5–1% equity | Post-raise: $2,000–$3,500 / month + equity",
        description: [
            "Make Web2 gamers obsessed with World of Nads.",
            "Own player acquisition and social growth loops for launch momentum."
        ],
        responsibilities: [
            "Own social media across TikTok, Instagram, X, and YouTube Shorts.",
            "Run influencer seeding campaigns targeting mobile gaming audiences.",
            "Manage paid campaigns and track CAC.",
            "Handle press outreach and game launch announcements.",
            "Drive app store optimization when APK/desktop ships.",
            "Report weekly growth metrics: DAU, retention, and spend."
        ],
        requirements: [
            "Proven track record in mobile gaming growth (not just Web3).",
            "Portfolio with real DAU/download outcomes.",
            "Deep understanding of short-form video, viral loops, and creator marketing.",
            "Understands the Fortnite / PUBG Mobile / CoD Mobile audience.",
            "Ships independently without constant briefs.",
            "US or Asia based, ages 21–35."
        ],
        bonus: ["Strong plus if you've scaled mobile titles from zero to traction."]
    },
    {
        title: "Game Artist, 2D/3D",
        category: "Open Role",
        pay: "Pre-raise: $400–$800 / month + 0.5–1% equity | Post-raise: $2,500–$4,000 / month + equity",
        description: [
            "Make the game look so good people screenshot it and post it.",
            "Own core visual quality across gameplay and marketing assets."
        ],
        responsibilities: [
            "Design in-game characters, skins, and cosmetics.",
            "Own UI/UX across menus, store, HUD, and lobby screens.",
            "Create animations for movement, drop, and combat.",
            "Produce marketing visuals including banners and thumbnails.",
            "Export assets cleanly into Godot 4.",
            "Iterate fast and ship art weekly."
        ],
        requirements: [
            "Strong 2D portfolio with at least one shipped game or product.",
            "Can do basic 3D or stylized low-poly work.",
            "Experience with Godot or can learn quickly.",
            "Understands asset pipelines and texture atlases.",
            "Fast turnaround and high responsiveness.",
            "US or Asia based, ages 21–35."
        ],
        bonus: ["Portfolio pieces optimized for browser/mobile performance are a plus."]
    },
    {
        title: "Community Manager",
        category: "Open Role",
        pay: "Pre-raise: $200–$400 / month + 0.25–0.5% equity | Post-raise: $1,500–$2,500 / month + equity",
        description: [
            "Own the players, build the culture, and keep the hype alive.",
            "Drive daily community energy and turn players into ambassadors."
        ],
        responsibilities: [
            "Manage Discord and Telegram daily with moderation and engagement.",
            "Plan and run events, tournaments, and hype campaigns.",
            "Collect player feedback and relay it clearly to the dev team.",
            "Handle announcements, patch notes, and community Q&As.",
            "Identify and grow top community members as ambassadors.",
            "Work with Growth Lead on content and viral moments."
        ],
        requirements: [
            "Has managed a gaming or Web3 community with 1,000+ active members.",
            "Strong written English (fast, clear, never corporate).",
            "Available daily and responsive across time zones.",
            "Understands genuine community building, not spam.",
            "Genuine gamer who understands player priorities.",
            "US or Asia based, ages 21–35."
        ],
        bonus: ["Experience running tournament/community ops is a plus."]
    }
];

const teamMembers: TeamMember[] = [
    {
        name: "Tobi Awolaju",
        role: "CEO & Technical Founder",
        imageUrl: "/pfps/pfp-tobi.png",
        summary: [
            "Owns product vision, architecture, and engineering decisions.",
            "Ships game features, smart contracts, and infrastructure.",
            "Leads technical fundraising narrative and public representation."
        ]
    }
];

const Careers: React.FC = () => {
    const [activeIndex, setActiveIndex] = useState<number | null>(null);
    const toggleSection = (i: number) => setActiveIndex(activeIndex === i ? null : i);

    return (
        <div className="careers-container">
            <div style={{ height: "60px" }} />
            <h1 className="careers-header">Team Roles & Job Descriptions</h1>

            <p className="careers-intro">
                Browser-first Web3 Battle Royale on Monad.<br />
                Targeting US & Asia | Ages 21–35.
            </p>

            <div className="team-section">
                <h2 style={{ fontSize: "2.5rem", fontWeight: 800, marginBottom: "40px" }}>Meet the Team at WoNs</h2>
                <div className="team-grid">
                    {teamMembers.map((m, i) => (
                        <div key={i} className="team-member-card">
                            <img src={m.imageUrl} alt={m.name} className="team-member-image" />
                            <h3 className="team-member-name">{m.name}</h3>
                            <p className="team-member-role">{m.role}</p>
                            {m.summary && (
                                <ul style={{ textAlign: "left", marginTop: "10px" }}>
                                    {m.summary.map((point, idx) => (
                                        <li key={idx}>{point}</li>
                                    ))}
                                </ul>
                            )}
                        </div>
                    ))}
                </div>
            </div>

            <h2 style={{ fontSize: "2.5rem", fontWeight: 800, marginBottom: "30px", marginTop: "80px" }}>
                Open Roles
            </h2>

            <div className="careers-list">
                {jobRoles.map((role, index) => (
                    <div
                        key={index}
                        className={`careers-item ${activeIndex === index ? "active" : ""}`}
                        onClick={() => toggleSection(index)}
                    >
                        <div className="careers-question">
                            <div style={{ textAlign: "left" }}>
                                <h3 style={{ margin: 0, fontSize: "1.3rem" }}>{role.title}</h3>
                                <span style={{ fontSize: "0.9rem", color: "#666", fontWeight: "normal" }}>
                                    {role.category}
                                </span>
                            </div>
                            <span className="careers-icon">{activeIndex === index ? "–" : "+"}</span>
                        </div>

                        <div className="careers-answer" style={activeIndex === index ? { maxHeight: "2000px" } : {}}>
                            <div className="job-card-content" style={{ paddingBottom: "20px" }}>
                                <p><strong>Compensation:</strong> {role.pay}</p>
                                <p><strong>Description:</strong></p>
                                <ul>{role.description.map((d, i) => <li key={i}>{d}</li>)}</ul>
                                <p style={{ marginTop: "15px" }}><strong>Responsibilities:</strong></p>
                                <ul>{role.responsibilities.map((r, i) => <li key={i}>{r}</li>)}</ul>
                                <p style={{ marginTop: "15px" }}><strong>Requirements:</strong></p>
                                <ul>{role.requirements.map((r, i) => <li key={i}>{r}</li>)}</ul>
                                <p style={{ marginTop: "15px" }}><strong>Notes:</strong></p>
                                <ul>{role.bonus.map((b, i) => <li key={i}>{b}</li>)}</ul>

                                <div style={{ marginTop: "30px", textAlign: "left" }}>
                                    <a
                                        href={`mailto:careers@worldofnads.xyz?subject=Application for ${role.title}`}
                                        className="apply-btn"
                                        style={{ display: "inline-block", background: "#6a38ff", color: "white", padding: "10px 25px", borderRadius: "30px", textDecoration: "none", fontWeight: "bold", fontSize: "1rem" }}
                                        onClick={(e) => e.stopPropagation()}
                                    >
                                        Apply Now
                                    </a>
                                </div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            <div className="careers-cta-wrapper" style={{ marginTop: "80px", textAlign: "center" }} />
            <Footer />
        </div>
    );
};

export default Careers;
