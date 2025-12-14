import { useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import './topnav.css';

const TopNavbar = () => {
  const [isDrawerOpen, setDrawerOpen] = useState(false);
  const location = useLocation();

  const toggleDrawer = () => setDrawerOpen(!isDrawerOpen);

  // central nav config
  const navItems = [
    { path: '/', label: 'WONs' },
    { path: '/pre-tge-arena', label: 'Arena' },
    { path: '/roadmap', label: 'Leaderboards' },
    { path: '/crew', label: 'Swap' },
    { path: '/partners', label: 'Partners' },
    { path: '/community', label: 'FAQ' },
    { path: '/careers', label: 'Careers' },
  ];

  const currentText = navItems.find(item => item.path === location.pathname)?.label || '';

  const renderNavLinks = (onClick?: () => void) =>
    navItems.map(item => (
      <NavLink
        key={item.path}
        to={item.path}
        onClick={onClick}
        className={({ isActive }) => (isActive ? 'link active-link' : 'link')}
      >
        {item.label}
      </NavLink>
    ));

  return (
    <nav className="topnav">
      {/* Logo + Optional Page Text */}
      <div className="logo-section" style={{ display: 'flex', alignItems: 'center' }}>
        <img src="logo.jpg" alt="logo" style={{ width: '40px', zIndex: 999 }} />
        {currentText && (
          <p style={{ fontSize: 'larger', margin: '10px', color: '#000', fontFamily: "'Font1', sans-serif", fontWeight: 'bold' }}>
            {currentText}
          </p>
        )}
      </div>

      {/* Desktop Links */}
      <div className="nav-links">{renderNavLinks()}</div>

      {/* Hamburger */}
      <button onClick={toggleDrawer} className="hamburger-btn" aria-expanded={isDrawerOpen}>
        ☰
      </button>

      {/* Drawer */}
      {isDrawerOpen && (
        <div className="drawer">
          <button onClick={toggleDrawer} className="close-btn">✖</button>
          <div className="drawer-links">{renderNavLinks(toggleDrawer)}</div>
        </div>
      )}
    </nav>
  );
};

export default TopNavbar;
