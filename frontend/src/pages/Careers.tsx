import React, { useState } from "react";
import "./Careers.css";

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
        title: "Godot Game Artist",
        category: "Art",
        pay: "$18–$30/hr",
        description: [
            "Create stylized characters, props, and environment assets.",
            "Work closely with animators and gameplay engineers.",
            "Establish a unique and memorable visual identity for World of Nads."
        ],
        responsibilities: [
            "Produce concept art, production art, and polished game assets.",
            "Optimize assets for WebAssembly browser performance.",
            "Collaborate with animator and game devs on fast iterations."
        ],
        requirements: [
            "Strong art fundamentals (shape, color, silhouette).",
            "Experience with Godot, Blender, or similar tools.",
            "Portfolio showing stylized game-ready assets."
        ],
        bonus: [
            "Experience with shaders or VFX.",
            "Worked on competitive arena-style games before.",
            "Knowledge of asset compression for browser-based builds."
        ]
    },
    {
        title: "Animator",
        category: "Art",
        pay: "$20–$32/hr",
        description: [
            "Create expressive gameplay animations for characters and abilities.",
            "Ensure smooth transitions and responsive feel.",
            "Work directly inside Godot, Rive, or Spine workflows."
        ],
        responsibilities: [
            "Animate characters, weapons, abilities and effects.",
            "Implement animations inside Godot animation tree.",
            "Work with the designer on timing and hit feedback."
        ],
        requirements: [
            "Strong understanding of motion and timing.",
            "Experience animating for games (not just film).",
            "Ability to work within tight, fast gameplay loops."
        ],
        bonus: [
            "Experience with Rive state machines.",
            "Knowledge of procedural animation.",
            "Understanding of squash/stretch in stylized worlds."
        ]
    },
    {
        title: "UI/UX Designer",
        category: "Design",
        pay: "$18–$28/hr",
        description: [
            "Design clean, competitive-game style UI for gameplay and menus.",
            "Own user flows for onboarding, matchmaking, and marketplace.",
            "Work with engineers for pixel-perfect React/Godot UI."
        ],
        responsibilities: [
            "Design wireframes, UI systems, and final assets.",
            "Perform user testing to refine experience flow.",
            "Ensure UI works seamlessly on web, mobile, and browser canvas."
        ],
        requirements: [
            "Portfolio with UI/UX for games or apps.",
            "Experience prototyping animations and flows.",
            "Strong grasp of visual hierarchy and typography."
        ],
        bonus: [
            "Experience designing for WebAssembly games.",
            "Knowledge of gamification systems.",
            "Familiarity with creator marketplaces."
        ]
    },
    {
        title: "Smart Contract Engineer",
        category: "Engineering",
        pay: "$30–$55/hr",
        description: [
            "Build and deploy gas-optimized contracts on Monad.",
            "Implement on-chain rewards and progression systems.",
            "Work with CTO on rapid testnet deployment cycles."
        ],
        responsibilities: [
            "Develop Solidity smart contracts for gameplay rewards.",
            "Write fuzz tests and ensure audit-grade safety.",
            "Integrate contracts with the browser client."
        ],
        requirements: [
            "Deep experience writing Solidity.",
            "Understanding of gas optimization techniques.",
            "Ability to build fast and iterate with product team."
        ],
        bonus: [
            "Experience with Monad.",
            "Shipped a game or Web3 product before.",
            "Knowledge of account abstraction."
        ]
    },
    {
        title: "Community Manager",
        category: "Community",
        pay: "$12–$20/hr",
        description: [
            "Shape the community culture and daily vibe.",
            "Engage with players and creators on X and Discord.",
            "Support onboarding and run hype events."
        ],
        responsibilities: [
            "Host events, challenges, and tournaments.",
            "Respond and talk to the community daily.",
            "Work with moderators and growth team."
        ],
        requirements: [
            "Strong communication skills.",
            "Good understanding of meme culture.",
            "Experience running an online community."
        ],
        bonus: [
            "Experience with gaming communities.",
            "Has a personal following on X/TikTok.",
            "Understands Web3 incentives."
        ]
    },
    {
        title: "Moderators",
        category: "Community",
        pay: "$8–$15/hr",
        description: [
            "Keep chats clean and troll-resistant.",
            "Handle reports and maintain safe spaces.",
            "Support players and escalate real issues."
        ],
        responsibilities: [
            "Moderate Discord/X chats.",
            "Enforce rules and remove harmful content.",
            "Flag issues for community lead."
        ],
        requirements: [
            "Active online presence.",
            "Good judgment and calm conflict resolution.",
            "Works well in fast communities."
        ],
        bonus: [
            "Experience moderating large communities.",
            "Gaming experience.",
            "Simple bot-management skills."
        ]
    },
    {
        title: "Social Media Manager",
        category: "Marketing",
        pay: "$15–$25/hr",
        description: [
            "Drive hype across X, TikTok, and Instagram.",
            "Post daily content that fits gaming culture.",
            "Grow the online presence aggressively."
        ],
        responsibilities: [
            "Create posting calendars.",
            "Work with video editors and designers.",
            "Track engagement and optimize content."
        ],
        requirements: [
            "Experience running brand pages.",
            "Strong sense of timing and trends.",
            "Good with memes and short-form storytelling."
        ],
        bonus: [
            "Worked with gaming creators.",
            "Video editing or basic design skills.",
            "Track record of viral posts."
        ]
    },
    {
        title: "Video Editor",
        category: "Content",
        pay: "$15–$30/hr",
        description: [
            "Edit gameplay highlights and memes.",
            "Create fast-paced shorts for X and TikTok.",
            "Work with social and community teams."
        ],
        responsibilities: [
            "Edit weekly gameplay clips.",
            "Create hype trailers for updates.",
            "Maintain consistent style and pacing."
        ],
        requirements: [
            "Good understanding of gaming pacing.",
            "Experience editing short-form content.",
            "Own equipment and editing tools."
        ],
        bonus: [
            "Motion graphics skills.",
            "Experience with OBS/game capture.",
            "Knows TikTok editing style deeply."
        ]
    },
    {
        title: "Growth Lead",
        category: "Growth",
        pay: "$22–$40/hr",
        description: [
            "Lead user acquisition and retention loops.",
            "Build growth funnels and partnerships.",
            "Work directly with leadership on scaling."
        ],
        responsibilities: [
            "Build campaigns that bring players in.",
            "Run experiments and measure growth KPIs.",
            "Manage creator partnerships."
        ],
        requirements: [
            "Experience in growth marketing.",
            "Data-driven mindset.",
            "Understanding of gaming audiences."
        ],
        bonus: [
            "Web3 or esports experience.",
            "Track record of growing userbases.",
            "Strong analytical tooling knowledge."
        ]
    },
    {
        title: "Anti-Cheat Engineer",
        category: "Engineering",
        pay: "$28–$45/hr",
        description: [
            "Build and maintain anti-cheat systems.",
            "Detect suspicious activity in real-time.",
            "Work closely with gameplay engineers."
        ],
        responsibilities: [
            "Build anti-tamper systems for browser builds.",
            "Create detection logic for unfair patterns.",
            "Investigate reports of unusual behavior."
        ],
        requirements: [
            "Experience in security or anti-cheat.",
            "Strong understanding of networking.",
            "Ability to patch exploits quickly."
        ],
        bonus: [
            "Experience securing WebAssembly games.",
            "Knowledge of bot detection.",
            "Security research background."
        ]
    },
    {
        title: "Partnership Manager",
        category: "Growth",
        pay: "$18–$35/hr",
        description: [
            "Secure partnerships with creators and brands.",
            "Manage communication and collab pipelines.",
            "Coordinate co-marketing opportunities."
        ],
        responsibilities: [
            "Identify potential collaborators.",
            "Pitch and negotiate partnership deals.",
            "Maintain long-term partner relationships."
        ],
        requirements: [
            "Strong communication and negotiation.",
            "Experience in BD or partnerships.",
            "Understanding of gaming culture."
        ],
        bonus: [
            "Web3 network.",
            "Experience working with KOLs.",
            "Has industry contacts."
        ]
    },
    {
        title: "QA Testers",
        category: "Quality Assurance",
        pay: "$10–$18/hr",
        description: [
            "Stress-test all gameplay and features.",
            "Document reproducible bugs.",
            "Ensure smooth browser performance."
        ],
        responsibilities: [
            "Test new builds daily.",
            "Write clear bug reports.",
            "Test across devices and browsers."
        ],
        requirements: [
            "Attention to detail.",
            "Experience testing games.",
            "Basic technical understanding."
        ],
        bonus: [
            "Experience testing Godot games.",
            "WebAssembly performance knowledge.",
            "Competitive gamer."
        ]
    },
    {
        title: "Operations & Project Lead",
        category: "Operations",
        pay: "$18–$35/hr",
        description: [
            "Oversee team workflows and maintain structure.",
            "Coordinate contractors, timelines, and deliverables.",
            "Ensure smooth operations across the entire studio."
        ],
        responsibilities: [
            "Manage sprints and cross-team communication.",
            "Handle contractor onboarding and payouts.",
            "Track milestone progress and deadlines."
        ],
        requirements: [
            "Strong organizational skills.",
            "Experience in project or operations roles.",
            "Comfortable managing multiple teams."
        ],
        bonus: [
            "Experience at a game studio.",
            "Familiar with agile workflows.",
            "Basic technical knowledge."
        ]
    },
    {
        title: "Technical Producer",
        category: "Production",
        pay: "$22–$40/hr",
        description: [
            "Bridge the gap between engineering and design.",
            "Oversee feature production from start to finish.",
            "Ensure teams ship on time with the right quality."
        ],
        responsibilities: [
            "Lead feature planning and execution.",
            "Break down tasks and manage pipelines.",
            "Coordinate gameplay and art delivery."
        ],
        requirements: [
            "Experience as a producer or similar role.",
            "Strong communication skills.",
            "Ability to manage technical discussions."
        ],
        bonus: [
            "Experience with Godot or Unity.",
            "Engineering background.",
            "Worked on live games."
        ]
    },
    {
        title: "Community & Publishing Lead",
        category: "Community",
        pay: "$15–$28/hr",
        description: [
            "Lead all community communications and publishing efforts.",
            "Manage creator cycles, update notes, and hype events.",
            "Coordinate across teams to ensure smooth publishing."
        ],
        responsibilities: [
            "Publish updates, devlogs, and patch notes.",
            "Oversee Discord, X, TikTok operations.",
            "Run creator campaigns and tournaments."
        ],
        requirements: [
            "Experience managing online communities.",
            "Strong writing and communication.",
            "Understanding of gaming and content cycles."
        ],
        bonus: [
            "Worked on game launches.",
            "Social media management experience.",
            "Web3 or esports background."
        ]
    }
];

const teamMembers: TeamMember[] = [
    { name: "Tobi Awolaju", role: "Foundering ", imageUrl: "/pfps/pfp-tobi.png" },
    { name: "Tobi-codex", role: "Game Dev", imageUrl: "/pfps/pfp-joshua.png" },
    { name: "Tobi-clawbot", role: "Growth & Partnerships", imageUrl: "/pfps/pfp-spark.png" },
    { name: "Tobi-gemini", role: "Security & SmartcontractsS", imageUrl: "/pfps/pfp-lone.png" },
    { name: "Tobi-n8n", role: "Community & Content Lead", imageUrl: "/pfps/pfp-wisdom.png" },
];

const Careers: React.FC = () => {
    // Stores the index of the currently open accordion. null means all closed.
    const [activeIndex, setActiveIndex] = useState<number | null>(null);

    const toggleSection = (i: number) => {
        setActiveIndex(activeIndex === i ? null : i);
    };

    return (
        <div className="careers-container">
            <div style={{ height: "60px" }} />
            <h1 className="careers-header">Work with the Nads</h1>

            <p className="careers-intro">
                World of Nads is shaping fast, competitive, browser-first on-chain arenas.
                We move fast and hire independent thinkers who ship.
            </p>

            {/* TEAM SECTION */}
            <div className="team-section">
                <h2>Meet the Team Shaping the WONs</h2>
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
            <h2 style={{ fontSize: "2.5rem", fontWeight: 800, marginBottom: "30px", marginTop: "60px" }}>
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
                                    {role.category} • {role.pay}
                                </span>
                            </div>
                            <span className="careers-icon">
                                {activeIndex === index ? "–" : "+"}
                            </span>
                        </div>

                        {/* BODY: Collapsible Content */}
                        {/* Inline style max-height adjusted because contents are long */}
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
                                    <button
                                        type="button"
                                        className="apply-btn"
                                        disabled
                                        style={{
                                            display: "inline-block",
                                            background: "#6a38ff",
                                            color: "white",
                                            padding: "10px 25px",
                                            borderRadius: "30px",
                                            textDecoration: "none",
                                            fontWeight: "bold",
                                            fontSize: "1rem",
                                            border: "none",
                                            cursor: "not-allowed",
                                            opacity: 0.6
                                        }}
                                        onClick={(e) => e.stopPropagation()} // Prevent closing accordion when clicking apply
                                    >
                                        Not hiring at the moment
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            <div className="careers-cta-wrapper">
                <p style={{ marginBottom: "15px", color: "#555" }}>Don't see your role?</p>
                <a
                    href="mailto:careers@worldofnads.xyz?subject=General Application"
                    className="careers-cta"
                >
                    Email Us Anyway
                </a>
            </div>
        </div>
    );
};

export default Careers;
