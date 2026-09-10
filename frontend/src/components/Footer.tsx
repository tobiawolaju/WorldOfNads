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
      <nav className="footer-nav" aria-label="Footer navigation">
        {navItems.map((item) => (
          <NavLink key={item.to} to={item.to} className="footer-link">
            {item.label}
          </NavLink>
        ))}
      </nav>

      <div className="footer-bottom">
        <a
          href="https://x.com/worldofnads"
          target="_blank"
          rel="noopener noreferrer"
          className="footer-social-link"
        >
          <FaXTwitter size={16} />
          <span>@worldofnads</span>
        </a>

        {authenticated && (
          <span
            onClick={logout}
            className="footer-logout"
          >
            Log Out
          </span>
        )}
      </div>
    </footer>
  );
};

export default Footer;
