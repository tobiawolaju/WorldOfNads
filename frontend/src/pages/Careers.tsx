import React, { useState } from "react";
import "./Careers.css";
import Footer from "../components/Footer";

interface TeamMember {
    name: string;
    role: string;
    imageUrl: string;
    twitter?: string;
}

// ---- JOB ROLES WITH FULL DETAILS ---- //

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
        title: "Intern",
        category: "General Support",
        pay: "Negotiable",
        description: [
            "Learn the ropes of a fast-growing on-chain game studio.",
            "Assist with testing, community, and basic production tasks.",
            "Perfect for students or those looking to break into Web3 gaming."
        ],
        responsibilities: [
            "Support daily operations and community engagement.",
            "Assist in manual QA testing of new game builds.",
            "Help with social media content and documentation."
        ],
        requirements: [
            "Fast learner with a passion for gaming/Web3.",
            "Strong communication and organizational skills.",
            "Independent thinker who gets things done."
        ],
        bonus: [
            "Experience with Godot or basic coding.",
            "Active in the Monad or general crypto ecosystem."
        ]
    },
    {
        title: "Security Researcher / Anti-Cheat",
        category: "Engineering",
        pay: "Contract-based",
        description: [
            "Protect the integrity of competitive browser-based arenas.",
            "Research and patch exploits in WebAssembly and on-chain logic.",
            "Build robust anti-cheat systems for high-stakes matches."
        ],
        responsibilities: [
            "Perform security audits on game client and smart contracts.",
            "Develop real-time detection for bots and memory tampering.",
            "Investigate reports of unfair play and exploit attempts."
        ],
        requirements: [
            "Deep understanding of browser security and WebAssembly.",
            "Experience with memory forensics or game security.",
            "Proficient in networking and exploit analysis."
        ],
        bonus: [
            "Experience securing high-stakes on-chain systems.",
            "Background in competitive gaming anti-cheat."
        ]
    },
    {
        title: "Game Developer (Godot)",
        category: "Engineering",
        pay: "Contract-based",
        description: [
            "Ship fast, smooth, and responsive gameplay features in Godot.",
            "Polish the browser-first experience for thousands of players.",
            "Work directly on the core arena mechanics."
        ],
        responsibilities: [
            "Implement gameplay systems and interactive UI in Godot.",
            "Optimize performance for WebAssembly browser builds.",
            "Integrate game logic with backend and on-chain systems."
        ],
        requirements: [
            "Strong experience with Godot (GDScript/C#).",
            "Understanding of performance optimization for web.",
            "Portfolio of shipped game features or prototypes."
        ],
        bonus: [
            "Knowledge of shading and VFX in Godot.",
            "Familiarity with Web3 wallet integrations."
        ]
    },
    {
        title: "Artist (3D / 2D)",
        category: "Art",
        pay: "Contract-based",
        description: [
            "Define the visual identity of World of Nads arenas.",
            "Create stylized assets, characters, and environment pieces.",
            "Work closely with devs to ensure seamless asset integration."
        ],
        responsibilities: [
            "Produce stylized characters, props, and environment assets.",
            "Optimize assets for browser performance (WebAssembly).",
            "Assist with basic animation and visual polish."
        ],
        requirements: [
            "Strong art fundamentals and stylized portfolio.",
            "Experience with Blender or similar 3D tools.",
            "Understanding of asset compression for web builds."
        ],
        bonus: [
            "Experience with Godot animations or shaders.",
            "Worked on competitive or stylized games before."
        ]
    },
    {
        title: "Web3 Developer / Smart Contracts",
        category: "Engineering",
        pay: "Contract-based",
        description: [
            "Build and deploy the on-chain infrastructure for the WONs.",
            "Implement high-stakes reward systems and progression.",
            "Ensure secure, gas-efficient contracts on Monad."
        ],
        responsibilities: [
            "Develop Solidity smart contracts for gameplay and rewards.",
            "Integrate on-chain systems with the game client.",
            "Write comprehensive tests and ensure contract safety."
        ],
        requirements: [
            "Deep experience with Solidity and EVM environments.",
            "Understanding of gas optimization techniques.",
            "Ability to ship and iterate fast on testnet."
        ],
        bonus: [
            "Experience with Monad or high-throughput chains.",
            "Knowledge of account abstraction."
        ]
    },
    {
        title: "Digital Marketer / Growth",
        category: "Marketing",
        pay: "Contract-based",
        description: [
            "Drive aggressive user acquisition and brand awareness.",
            "Shape the narrative of World of Nads across social channels.",
            "Master the art of hype and retention funnels."
        ],
        responsibilities: [
            "Lead marketing campaigns and user growth experiments.",
            "Create high-engagement social content (X, TikTok, etc.).",
            "Analyze growth data and optimize player acquisition."
        ],
        requirements: [
            "Proven track record in digital marketing or growth loops.",
            "Deep understanding of gaming and Web3 culture.",
            "Data-driven mindset with a focus on shipping fast."
        ],
        bonus: [
            "Experience with video editing or viral content creation.",
            "Contact list of creators and collaborators."
        ]
    },
    {
        title: "Community Manager",
        category: "Community",
        pay: "Contract-based",
        description: [
            "Nurture the core culture of the WONs player base.",
            "Manage daily engagement on X and Discord.",
            "Run hype events and onboarding cycles."
        ],
        responsibilities: [
            "Lead community events, tournaments, and challenges.",
            "Respond to community feedback and foster local culture.",
            "Work with the growth team on onboarding new players."
        ],
        requirements: [
            "Exceptional communication and vibes management.",
            "Experience running gaming or Web3 communities.",
            "Deep understanding of hype cycles and meme culture."
        ],
        bonus: [
            "Has a personal following on X or Discord.",
            "Experience with creator/KOL community management."
        ]
    },
    {
        title: "Partnership Manager",
        category: "Growth",
        pay: "Contract-based",
        description: [
            "Secure and coordinate partnerships with brands and creators.",
            "Manage the pipeline for sponsor-backed arena matches.",
            "Identify strategic growth opportunities."
        ],
        responsibilities: [
            "Identify and pitch potential sponsors and collaborators.",
            "Negotiate and manage partnership deliverables.",
            "Maintain long-term relationships with core partners."
        ],
        requirements: [
            "Strong communication and negotiation skills.",
            "Experience in business development or partnerships.",
            "Deeply networked in the gaming or Web3 ecosystem."
        ],
        bonus: [
            "Existing contact list of creators and brands.",
            "Experience managing sponsorship pipelines."
        ]
    }
];


const teamMembers: TeamMember[] = [
    {
        name: "Tobi Awolaju",
        role: "Technical Founder — Dev, Art, Growth & Security",
        imageUrl: "/pfps/pfp-tobi.png"
    },
    {
        name: "Codex (Tobi)",
        role: "Code Review & QA Intern",
        imageUrl: "/pfps/pfp-joshua.png"
    }
];

const Careers: React.FC = () => {
    // Stores the index of the currently open accordion. null means all closed.
    const [activeIndex, setActiveIndex] = useState<number | null>(null);

    const toggleSection = (i: number) => {
        setActiveIndex(activeIndex === i ? null : i);
    };

    const hiringRoles = [
        "Intern",
        "Security Researcher / Anti-Cheat",
        "Game Developer (Godot)",
        "Artist (3D / 2D)",
        "Web3 Developer / Smart Contracts",
        "Digital Marketer / Growth",
        "Community Manager",
        "Partnership Manager"
    ];

    return (
        <div className="careers-container">
            <div style={{ height: "60px" }} />
            <h1 className="careers-header">Work with the Nads</h1>

            <p className="careers-intro">
                World of Nads is shaping fast, competitive, browser-first on-chain arenas.
                <br />
                We move fast and hire independent thinkers, contractors, and specialists who ship.
            </p>

            {/* TEAM SECTION */}
            <div className="team-section">
                <h2 style={{ fontSize: "2.5rem", fontWeight: 800, marginBottom: "40px" }}>Meet the Team</h2>
                <div className="team-grid">
                    {teamMembers.map((m, i) => (
                        <div key={i} className="team-member-card">
                            <img src={m.imageUrl} alt={m.name} className="team-member-image" />
                            <h3 className="team-member-name">{m.name}</h3>
                            <p className="team-member-role">{m.role}</p>
                        </div>
                    ))}
                </div>
            </div>

            {/* ROLES ACCORDION */}
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
                        {/* HEADLINE: Visible when closed or open */}
                        <div className="careers-question">
                            <div style={{ textAlign: "left" }}>
                                <h3 style={{ margin: 0, fontSize: "1.3rem" }}>{role.title}</h3>
                                <span style={{ fontSize: "0.9rem", color: "#666", fontWeight: "normal" }}>
                                    {role.category}
                                </span>
                            </div>
                            <span className="careers-icon">
                                {activeIndex === index ? "–" : "+"}
                            </span>
                        </div>

                        {/* BODY: Collapsible Content */}
                        <div
                            className="careers-answer"
                            style={activeIndex === index ? { maxHeight: "2000px" } : {}}
                        >
                            <div className="job-card-content" style={{ paddingBottom: "20px" }}>
                                <p><strong>Description:</strong></p>
                                <ul>
                                    {role.description.map((d, i) => (
                                        <li key={i}>{d}</li>
                                    ))}
                                </ul>

                                <p style={{ marginTop: "15px" }}><strong>Responsibilities:</strong></p>
                                <ul>
                                    {role.responsibilities.map((r, i) => (
                                        <li key={i}>{r}</li>
                                    ))}
                                </ul>

                                <p style={{ marginTop: "15px" }}><strong>Requirements:</strong></p>
                                <ul>
                                    {role.requirements.map((r, i) => (
                                        <li key={i}>{r}</li>
                                    ))}
                                </ul>

                                <p style={{ marginTop: "15px" }}><strong>Bonus:</strong></p>
                                <ul>
                                    {role.bonus.map((b, i) => (
                                        <li key={i}>{b}</li>
                                    ))}
                                </ul>

                                {/* Apply Button Specific to this Role */}
                                <div style={{ marginTop: "30px", textAlign: "left" }}>
                                    {hiringRoles.includes(role.title) ? (
                                        <a
                                            href={`mailto:careers@worldofnads.xyz?subject=Application for ${role.title}`}
                                            className="apply-btn"
                                            style={{
                                                display: "inline-block",
                                                background: "#6a38ff",
                                                color: "white",
                                                padding: "10px 25px",
                                                borderRadius: "30px",
                                                textDecoration: "none",
                                                fontWeight: "bold",
                                                fontSize: "1rem"
                                            }}
                                            onClick={(e) => e.stopPropagation()}
                                        >
                                            Apply Now
                                        </a>
                                    ) : (
                                        <span className="not-hiring" style={{ color: "#888", fontStyle: "italic" }}>
                                            Not hiring at the moment
                                        </span>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            <div className="careers-cta-wrapper" style={{ marginTop: "80px", textAlign: "center" }}>
                <p style={{ marginBottom: "15px", color: "#555" }}>Don’t see your role? Send us a proposal anyway</p>

            </div>
            <Footer />
        </div>
    );
};

export default Careers;
