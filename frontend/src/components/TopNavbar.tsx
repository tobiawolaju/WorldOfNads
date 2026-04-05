import { useEffect, useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import './topnav.css';

const TopNavbar = () => {
  const [isDrawerOpen, setDrawerOpen] = useState(false);
  const [isScrolledPastHero, setIsScrolledPastHero] = useState(false);
  const location = useLocation();

  const isHome = location.pathname === '/';
  const toggleDrawer = () => setDrawerOpen(!isDrawerOpen);

  useEffect(() => {
    const onScroll = () => {
      setIsScrolledPastHero(window.scrollY >= window.innerHeight);
    };

    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });

    return () => {
      window.removeEventListener('scroll', onScroll);
    };
  }, []);


  // central nav config

  const navItems = [

    { path: '/', label: 'WONs' },

    { path: '/nad-arena', label: 'Nad Arena' },

    { path: '/roadmap', label: 'Leaderboards' },
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

        {item.label}

      </NavLink>

    ));



  const navClass = `topnav ${isHome ? 'home-nav' : ''} ${isHome && isScrolledPastHero ? 'home-nav-scrolled' : ''}`.trim();

  return (
    <nav className={navClass}>
      {/* Logo + Optional Page Text */}

      <div className="logo-section" style={{ display: 'flex', alignItems: 'center' }}>

        <img src="/logo.png" alt="logo" style={{ width: '40px', zIndex: 999 }} />
        {currentText && (
          <p
            style={{
              fontSize: 'larger',
              margin: '10px',
              color: isHome && !isScrolledPastHero ? '#ffffff' : '#000',
              fontFamily: "'Font1', sans-serif",
              fontWeight: 'bold',
            }}
          >
            {currentText}
          </p>
        )}
      </div>


      {/* Desktop Links */}

      <div className="nav-links">{renderNavLinks()}</div>



      {/* Hamburger */}

      <button onClick={toggleDrawer} className={`hamburger-btn ${isHome && !isScrolledPastHero ? 'home-hamburger' : ''}`} aria-expanded={isDrawerOpen}>
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
