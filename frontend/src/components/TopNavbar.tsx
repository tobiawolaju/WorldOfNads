import { useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import './topnav.css';

const TopNavbar = () => {
  const [isDrawerOpen, setDrawerOpen] = useState(false);
  const location = useLocation(); // get current route

  const toggleDrawer = () => {
    setDrawerOpen(!isDrawerOpen);
  };

  // Map route paths to text for display
  const pageTextMap: Record<string, string> = {
    '/': '', // Home shows only image
    '/pre-tge-arena': 'Pre-TGE Arena',
    '/roadmap': 'Project Leaderboards',
    '/crew': 'Swap',
    '/partners': 'Partners',
    '/community': 'FAQ',
  };

  const currentText = pageTextMap[location.pathname] || '';

  return (
    <nav className="topnav">
      {/* Logo + Optional Text */}
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <img
          style={{
            width: '40px',
            zIndex: '999',
          }}
          src="logo.jpg"
          alt="logo"
        />
        {currentText && (
          <p
            style={{
              fontSize: 'larger',
              margin: '10px',
              color: " rgba(0, 0, 0, 1)",
              fontFamily: "'Font1', sans-serif",
              fontWeight: "bold",
    
            }}
          >
        {currentText}
      </p>
        )}
    </div>

      {/* Navigation Links for Desktop */ }
  <div className="nav-links">
    <NavLink to="/" className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
      WONs
    </NavLink>
    <NavLink to="/pre-tge-arena" className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
      Pre-TGE Arena
    </NavLink>
    <NavLink to="/roadmap" className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
      Project Leaderboards
    </NavLink>
    <NavLink to="/crew" className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
      Swap
    </NavLink>
    <NavLink to="/partners" className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
      Partners
    </NavLink>
    <NavLink to="/community" className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
      FAQ
    </NavLink>
  </div>

  {/* Hamburger Menu Button */ }
  <button onClick={toggleDrawer} className="hamburger-btn" aria-expanded={isDrawerOpen}>
    ☰
  </button>

  {/* Drawer Menu for Mobile */ }
  {
    isDrawerOpen && (
      <div className="drawer">
        <button onClick={toggleDrawer} className="close-btn">
          ✖
        </button>

        <div className="drawer-links">
          <NavLink to="/" onClick={toggleDrawer} className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
            WONs
          </NavLink>
          <NavLink to="/pre-tge-arena" onClick={toggleDrawer} className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
            Pre-TGE Arena
          </NavLink>
          <NavLink to="/roadmap" onClick={toggleDrawer} className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
            Project Leaderboards
          </NavLink>
          <NavLink to="/crew" onClick={toggleDrawer} className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
            Swap
          </NavLink>
          <NavLink to="/partners" onClick={toggleDrawer} className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
            Partners
          </NavLink>
          <NavLink to="/community" onClick={toggleDrawer} className={({ isActive }) => (isActive ? 'link active-link' : 'link')}>
            FAQ
          </NavLink>
        </div>
      </div>
    )
  }
    </nav >
  );
};

export default TopNavbar;
