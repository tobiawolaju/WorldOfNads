import { FaXTwitter } from "react-icons/fa6";
import { NavLink } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import "./footer.css";

const Footer = () => {
  const { authenticated, logout } = usePrivy();
  const navItems = [
    { to: "/", label: "WONs" },
    { to: "/nad-arena", label: "Nad Arena" },
    { to: "/leaderboard", label: "Leaderboards" },
    { to: "/hosts", label: "Hosts" },
    { to: "/milestone", label: "Milestone" },
    { to: "/community", label: "FAQ" },
    { to: "/careers", label: "Careers" },
  ];

  return (
    <footer className="footer-container">
      <div className="footer-left">
        <img src="/iarc12.webp" alt="IARC 12+ rating" className="footer-rating-image" />
      </div>

      <div className="footer-right">
        <div className="footer-section">
          <h3 className="footer-title">Social</h3>
          <a href="https://x.com/worldofnads" target="_blank" rel="noopener noreferrer" className="footer-social-link">
            <FaXTwitter size={18} />
            <span>WorldofNad</span>
          </a>
        </div>

        <div className="footer-section">
          <h3 className="footer-title">Navigation</h3>
          <nav className="footer-nav" aria-label="Footer navigation">
            {navItems.map((item) => (
              <NavLink key={item.to} to={item.to} className="footer-link">
                {item.label}
              </NavLink>
            ))}
          </nav>
        </div>

        {authenticated && (
          <div className="footer-section">
            <span 
              onClick={logout}
              style={{ color: "#ff4444", cursor: "pointer", fontWeight: "bold", userSelect: "none" }}
            >
              Log Out
            </span>
          </div>
        )}
      </div>
    </footer>
  );
};

export default Footer;
