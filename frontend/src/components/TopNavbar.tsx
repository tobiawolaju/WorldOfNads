import { useMemo, useCallback, useState, useEffect } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { usePrivy } from '@privy-io/react-auth';
import { ethers } from 'ethers';
import { getPrimaryWalletAddress, getProfilePictureFromPrivy, getUsernameFromPrivy } from '../pages/firebaseClient';
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
  const [monBalance, setMonBalance] = useState<string | null>(null);
  const location = useLocation();
  const { ready, authenticated, user } = usePrivy();

  const isHome = location.pathname === '/';

  const currentText = useMemo(
    () => NAV_ITEMS.find(item => item.path === location.pathname)?.label || '',
    [location.pathname]
  );

  const walletAddress = useMemo(
    () => (user ? getPrimaryWalletAddress(user) : ""),
    [user]
  );

  const shortAddress = walletAddress
    ? `${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`
    : "";

  useEffect(() => {
    if (!authenticated || !user) {
      setMonBalance(null);
      return;
    }

    let cancelled = false;

    const fetchBalance = async () => {
      try {
        const address = getPrimaryWalletAddress(user);
        if (!address) {
          if (!cancelled) setMonBalance(null);
          return;
        }
        const provider = new ethers.JsonRpcProvider("https://testnet-rpc.monad.xyz");
        const balance = await provider.getBalance(address);
        const formatted = Number(ethers.formatEther(balance)).toFixed(4);
        if (!cancelled) setMonBalance(formatted);
      } catch (error) {
        console.error("Failed to fetch MON balance:", error);
        if (!cancelled) setMonBalance(null);
      }
    };

    fetchBalance();
    const interval = setInterval(fetchBalance, 30000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [authenticated, user]);

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
        {ready && authenticated && user ? (
          <div className="user-badge">
            <div className="user-badge__top">
              <img src={getProfilePictureFromPrivy(user) || '/loadinglogo.png'} alt="avatar" className="user-badge__avatar" />
              <p className="user-badge__name">
                {getUsernameFromPrivy(user) || 'Player'}
              </p>
            </div>
            {(monBalance !== null || shortAddress) && (
              <p className="user-badge__meta">
                {monBalance !== null ? `${monBalance} MON` : '—'} {shortAddress && `· ${shortAddress}`}
              </p>
            )}
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
