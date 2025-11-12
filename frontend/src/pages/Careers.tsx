import React, { useState } from "react";
import "./Careers.css";

// Placeholder data for team members
interface TeamMember {
    name: string;
    role: string;
    imageUrl: string; // Placeholder for image path
}

const teamMembers: TeamMember[] = [
    { name: "Tobi", role: "Founder & Lead Engineer", imageUrl: "/pfps/pfp1.png"}, // Replace with actual images
    { name: "Joshua", role: "Frontend Engineer", imageUrl: "/pfps/pfp2.png"},
    { name: "Spark", role: "Concept Artist",imageUrl: "/pfps/pfp3.png"},
    { name: "Lone", role: "Partnerships Manager", imageUrl: "/pfps/pfp4.png"},
    { name: "Wisdom", role: "Community Strategy", imageUrl: "/pfps/pfp5.png"},
    { name: "Cotonou", role: "Community Growth", imageUrl: "/pfps/pfp1.png"},
];

const Careers: React.FC = () => {
    // State to manage which section is currently open.
    const [activeIndex, setActiveIndex] = useState<number | null>(0); // Start with Culture open

    const toggleSection = (index: number) => {
        setActiveIndex(activeIndex === index ? null : index);
    };

    return (
        <div className="careers-container">
            <div style={{ height: "60px" }}></div>

            <h1 className="careers-header">Work with the Nads</h1>

            <p className="careers-intro">
                World of Nads is building the next generation of fast, browser-first, **on-chain battle arenas**.
                We move with the speed of Monad, stay adaptive, and only hire **elite, independent contributors**. If you're hungry,
                focused on slope (potential for rapid improvement), and ready to ship, we want to hear from you.
            </p>

            {/* --- NEW SECTION: Current Team Members --- */}
            <div className="careers-section team-section">
                <h2>Meet the Team Shaping the Nads</h2>
                <div className="team-grid">
                    {teamMembers.map((member, index) => (
                        <div key={index} className="team-member-card">
                            <img src={member.imageUrl} alt={member.name} className="team-member-image" />
                            <h3 className="team-member-name">{member.name}</h3>
                            <p className="team-member-role">{member.role}</p>
                        </div>
                    ))}
                </div>
            </div>
            {/* --- END NEW SECTION --- */}

            <div className="careers-list">
                {/* ----------------- SECTION 0: Our Culture ----------------- */}
                <div 
                    className={`careers-item ${activeIndex === 0 ? "active" : ""}`}
                    onClick={() => toggleSection(0)}
                >
                    <div className="careers-question">
                        <h2>Our Culture: Ship Fast. Stay Hungry.</h2>
                        <span className="careers-icon">{activeIndex === 0 ? "–" : "+"}</span>
                    </div>
                    <div className="careers-answer">
                        <ul>
                            <li>**Slope Over Skill:** We prioritize potential to improve rapidly (slope) and consistency.</li>
                            <li>Extreme ownership — you ship the product, you own the outcome.</li>
                            <li>Adaptability — we evolve weekly; low ego is required.</li>
                            <li>Solution-Oriented — problems are just tasks without a label. Find the fix.</li>
                            <li>Small team, huge output — championship mindset only.</li>
                        </ul>
                    </div>
                </div>

                {/* ----------------- SECTION 1: Open Roles ----------------- */}
                <div 
                    className={`careers-item ${activeIndex === 1 ? "active" : ""}`}
                    onClick={() => toggleSection(1)}
                >
                    <div className="careers-question">
                        <h2>Open Roles: Focus on Core Execution</h2>
                        <span className="careers-icon">{activeIndex === 1 ? "–" : "+"}</span>
                    </div>
                    <div className="careers-answer">
                        <ul className="roles-grid">
                            {/* Engineering Focus */}
                            <li>**Frontend Engineer (React/Vite)** - UI/UX execution for a fast, competitive environment.</li>
                            <li>**Game Engineer (Three.js / Babylon.js)** - Essential for the core 'Chicken Chase' mechanics and real-time browser logic.</li>
                            <li>**Smart Contract Engineer (Solidity)** - Focus on reward payouts, campaign logic, and Monad integration.</li>
                            {/* Art & Creative Focus - Critical Gaps */}
                            <li>**3D Character Artist & Animator** - Building the 'Nads' characters, skins, and viral animation pipeline. **(High Priority)**</li>
                            <li>**Concept Artist / Illustrator** - Visual direction and game asset concepts.</li>
                            {/* Operations Focus - Strategic Hires */}
                            <li>**Product Manager** - Driving the retention loop (XP, Battle Pass, partner integration).</li>
                            <li>**Partnerships & Growth Manager** - Securing external crypto project collaborations for user acquisition.</li>
                        </ul>
                    </div>
                </div>

                {/* ----------------- SECTION 2: How We Hire ----------------- */}
                <div 
                    className={`careers-item ${activeIndex === 2 ? "active" : ""}`}
                    onClick={() => toggleSection(2)}
                >
                    <div className="careers-question">
                        <h2>How We Hire: Prove Your Slope</h2>
                        <span className="careers-icon">{activeIndex === 2 ? "–" : "+"}</span>
                    </div>
                    <div className="careers-answer">
                        <ul>
                            <li>**Short Application:** Show us verifiable work that proves your specialty.</li>
                            <li>**Real Assessment Test:** A short, practical, and highly demanding assignment. (Your 7-Day Trial).</li>
                            <li>**7-Day Working Trial:** Paid, performance-based, and highly collaborative.</li>
                            <li>**Full-Time Offer:** Only bar-raisers who excel in the trial period join.</li>
                        </ul>
                    </div>
                </div>
                
                {/* ----------------- SECTION 3: Remote Policy ----------------- */}
                 <div 
                    className={`careers-item ${activeIndex === 3 ? "active" : ""}`}
                    onClick={() => toggleSection(3)}
                >
                    <div className="careers-question">
                        <h2>Work Where You Ship Best</h2>
                        <span className="careers-icon">{activeIndex === 3 ? "–" : "+"}</span>
                    </div>
                    <div className="careers-answer">
                        <p className="remote-policy">
                            Work isn't somewhere you go; it's something you **do**. As a browser-based, globally-focused startup, 
                            we embrace **remote-first** work. We value output and consistency above physical location.
                        </p>
                        <ul>
                            <li>**Global Remote:** We hire the best talent globally, provided your time zone allows effective syncs.</li>
                            <li>**Output Over Hours:** We don't track seat time; we track completed features and deliverables.</li>
                            <li>**Dedicated Setup:** We ensure you have the equipment and tools needed for elite execution, wherever you are.</li>
                            <li>**Asynchronous Default:** Communication is concise, asynchronous, with minimal, high-value meetings.</li>
                        </ul>
                    </div>
                </div>

            </div> {/* End careers-list */}

            <div className="careers-cta-wrapper">
                <a
                    href="mailto:careers@worldofnads.xyz"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="careers-cta"
                >
                   Join the Team
                </a>
            </div>
        </div>
    );
};

export default Careers;