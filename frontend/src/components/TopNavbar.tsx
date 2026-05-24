import { useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import './topnav.css';

type TopNavbarProps = {
  hideContents?: boolean;
};

const TopNavbar = ({ hideContents = false }: TopNavbarProps) => {
  const [isDrawerOpen, setDrawerOpen] = useState(false);
  const location = useLocation();

  const isHome = location.pathname === '/';
  const toggleDrawer = () => setDrawerOpen(!isDrawerOpen);




  // central nav config

  const navItems = [

    { path: '/', label: 'WONs' },

    { path: '/nad-arena', label: 'Nad Arena' },

    { path: '/leaderboard', label: 'Leaderboards' },
    { path: '/hosts', label: 'Hosts' },
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
        <span className={item.path === '/nad-arena' ? 'nav-link-with-badge' : ''}>
          {item.label}
          {item.path === '/nad-arena' && (
            <span className="notif-badge">
              <span className="notif-badge-text">1</span>
            </span>
          )}
        </span>

      </NavLink>

    ));



  const navClass = `topnav ${isHome ? 'home-nav' : ''}`.trim();

  return (
    <nav className={navClass}>
      {/* Logo + Optional Page Text */}

      <div className="logo-section" style={{ display: 'flex', alignItems: 'center' }}>

        <img src="/logo.png" alt="logo" style={{ width: '40px', zIndex: 999 }} />
        {!hideContents && currentText && (
          <p
            style={{
              fontSize: 'larger',
              margin: '10px',
              fontFamily: "'Font1', sans-serif",
              fontWeight: 'bold',
            }}
          >
            {currentText}
          </p>
        )}
      </div>


      {/* Desktop Links */}

      {!hideContents && <div className="nav-links">{renderNavLinks()}</div>}



      {/* Hamburger */}

      {!hideContents && (
        <button onClick={toggleDrawer} className="hamburger-btn" aria-expanded={isDrawerOpen}>
          ☰
          <span className="notif-badge">
            <span className="notif-badge-text">1</span>
          </span>
        </button>
      )}


      {/* Drawer */}

      {!hideContents && isDrawerOpen && (

        <div className="drawer">

          <button onClick={toggleDrawer} className="close-btn">✖</button>

          <div className="drawer-links">{renderNavLinks(toggleDrawer)}</div>

        </div>

      )}

    </nav>

  );

};



export default TopNavbar;
