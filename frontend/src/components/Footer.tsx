import { FaXTwitter } from "react-icons/fa6";
import {
  FaLinkedin,
  FaInstagram,
  FaYoutube,
  FaFacebook,
} from "react-icons/fa";
import { SiSubstack } from "react-icons/si";
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
        <p className="footer-text">
          World of Nads
          <br />
          contact@worldofnads</p>
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
        <a href="https://substack.com" target="_blank" rel="noopener noreferrer" className="footer-icon">
          <SiSubstack size={26} />
        </a>

        <a href="https://www.linkedin.com" target="_blank" rel="noopener noreferrer" className="footer-icon">
          <FaLinkedin size={26} />
        </a>

        <a href="https://www.instagram.com" target="_blank" rel="noopener noreferrer" className="footer-icon">
          <FaInstagram size={26} />
        </a>

        <a href="https://www.youtube.com" target="_blank" rel="noopener noreferrer" className="footer-icon">
          <FaYoutube size={26} />
        </a>

        <a href="https://www.facebook.com" target="_blank" rel="noopener noreferrer" className="footer-icon">
          <FaFacebook size={26} />
        </a>

        <a href="https://x.com/world_of_nads" target="_blank" rel="noopener noreferrer" className="footer-icon">
          <FaXTwitter size={26} />
        </a>
      </div>
    </footer>
  );
};

export default Footer;
