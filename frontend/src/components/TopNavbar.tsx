import { useMemo, useCallback, useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { usePrivy } from '@privy-io/react-auth';
import { getProfilePictureFromPrivy, getUsernameFromPrivy } from '../pages/firebaseClient';
import './topnav.css';

type TopNavbarProps = {
  hideContents?: boolean;
};

const NAV_ITEMS = [
  { path: '/', label: 'WONs' },
  { path: '/nad-arena', label: 'Nad Arena' },
  { path: '/leaderboard', label: 'Leaderboards' },
  { path: '/hosts', label: 'Hosts' },
  { path: '/community', label: 'FAQ' },
  { path: '/careers', label: 'Careers' },
];

const TopNavbar = ({ hideContents = false }: TopNavbarProps) => {
  const [isDrawerOpen, setDrawerOpen] = useState(false);
  const location = useLocation();
  const { ready, authenticated, user } = usePrivy();

  const isDashboard = location.pathname === '/dashboard';
  const isHome = location.pathname === '/';

  const currentText = useMemo(
    () => NAV_ITEMS.find(item => item.path === location.pathname)?.label || '',
    [location.pathname]
  );

  const renderNavLinks = useCallback((onClick?: () => void) =>
    NAV_ITEMS.map(item => (
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
    )),
    []
  );

  const toggleDrawer = useCallback(() => setDrawerOpen(prev => !prev), []);

  const navClass = `topnav ${isHome ? 'home-nav' : ''}`.trim();

  return (
    <nav className={navClass}>
      <div className="logo-section" style={{ display: 'flex', alignItems: 'center' }}>
        {isDashboard && ready && authenticated && user ? (
          <div style={{ display: 'flex', alignItems: 'center', transform: 'scale(0.8)', transformOrigin: 'left center' }}>
            <img src={getProfilePictureFromPrivy(user) || '/loadinglogo.png'} alt="avatar" style={{ width: '40px', height: '40px', objectFit: 'cover' }} />
            <p style={{ fontSize: 'larger', margin: '10px', fontFamily: "'Font1', sans-serif", fontWeight: 'bold' }}>
              {getUsernameFromPrivy(user) || 'Player'}
            </p>
          </div>
        ) : (
          <>
            <img src="/loadinglogo.png" alt="logo" style={{ width: '40px', zIndex: 999 }} />
            {!hideContents && currentText && (
              <p style={{ fontSize: 'larger', margin: '10px', fontFamily: "'Font1', sans-serif", fontWeight: 'bold' }}>
                {currentText}
              </p>
            )}
          </>
        )}
      </div>

      {!hideContents && <div className="nav-links">{renderNavLinks()}</div>}

      {!hideContents && (
        <button onClick={toggleDrawer} className="hamburger-btn" aria-expanded={isDrawerOpen}>
          ☰
          <span className="notif-badge">
            <span className="notif-badge-text">1</span>
          </span>
        </button>
      )}

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
