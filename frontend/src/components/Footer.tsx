import { FaDiscord } from "react-icons/fa";
import { FaXTwitter } from "react-icons/fa6";
import { NavLink } from "react-router-dom";
import "./footer.css";

const Footer = () => {
  return (
    <footer className="footer-container">
      {/* Left Section */}
      <div className="footer-left">
        <img
          src="logo.jpg"
          alt="site logo"
          className="footer-logo"
        />
        <p className="footer-text">And then I WON.</p>
      </div>

      {/* Navigation */}
      <div className="footer-nav">
        <NavLink to="/" className="footer-link">WONs</NavLink>
        <NavLink to="/pre-tge-arena" className="footer-link">Pre-TGE Arena</NavLink>
        <NavLink to="/roadmap" className="footer-link">Leaderboards</NavLink>
        <NavLink to="/crew" className="footer-link">Won Dex</NavLink>
        <NavLink to="/partners" className="footer-link">Partners</NavLink>
        <NavLink to="/community" className="footer-link">FAQ</NavLink>
        <NavLink to="/careers" className="footer-link">Careers</NavLink>
      </div>

      {/* Social Icons */}
      <div className="footer-icons">
        <a
          href="https://discord.gg/z4SUdrKayb"
          target="_blank"
          rel="noopener noreferrer"
          className="footer-icon"
        >
          <FaDiscord size={26} />
        </a>

        <a
          href="https://x.com/world_of_nads"
          target="_blank"
          rel="noopener noreferrer"
          className="footer-icon"
        >
          <FaXTwitter size={26} />
        </a>
      </div>
    </footer>
  );
};

export default Footer;
