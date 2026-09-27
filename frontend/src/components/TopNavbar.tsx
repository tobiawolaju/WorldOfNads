import { useMemo, useCallback, useState, useEffect } from 'react';
import { NavLink, useLocation, useNavigate } from 'react-router-dom';
import { usePrivy } from '@privy-io/react-auth';
import { showSuccessToast } from './ui/custom-toast';
import { getPrimaryWalletAddress, getProfilePictureFromPrivy, getUsernameFromPrivy, fetchUserRoles } from '../pages/firebaseClient';
import {
  QUALITY_LABELS,
  QUALITY_OPTIONS,
  readGameQuality,
  resolveQuality,
  writeGameQuality,
  type GameQuality
} from '../lib/gameQuality';
import './topnav.css';

type TopNavbarProps = {
  hideContents?: boolean;
};

const NAV_ITEMS = [
  { path: '/', label: 'Play' },
  { path: '/nad-arena', label: 'Nad Arena' },
  { path: '/leaderboard', label: 'Leaderboards' },
  { path: '/hosts', label: 'Hosts' },
  { path: '/community', label: 'FAQ' },
  { path: '/careers', label: 'Careers' },
];

const TopNavbar = ({ hideContents = false }: TopNavbarProps) => {
  const [isDrawerOpen, setDrawerOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [roles, setRoles] = useState<string[]>([]);
  const [quality, setQuality] = useState<GameQuality>(() => readGameQuality());
  const location = useLocation();
  const navigate = useNavigate();
  const { ready, authenticated, user, logout } = usePrivy();

  const isHome = location.pathname === '/';

  const currentText = useMemo(
    () => NAV_ITEMS.find(item => item.path === location.pathname)?.label || '',
    [location.pathname]
  );

  const qualityHint = useMemo(
    () =>
      resolveQuality('auto').renderScale < 1
        ? 'Auto - reduced resolution on this device'
        : 'Auto - full resolution on this device',
    []
  );

  const walletAddress = useMemo(
    () => (user ? getPrimaryWalletAddress(user) : ""),
    [user]
  );

  const shortAddress = walletAddress
    ? `${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`
    : "";

  const handleCopyWallet = useCallback(() => {
    if (!walletAddress) return;
    navigator.clipboard.writeText(walletAddress);
    showSuccessToast("Wallet address copied!");
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [walletAddress]);

  useEffect(() => {
    if (!authenticated || !user) {
      setRoles([]);
      return;
    }
    let cancelled = false;
    const loadRoles = async () => {
      try {
        const username = getUsernameFromPrivy(user);
        const data = await fetchUserRoles(username);
        if (!cancelled) setRoles(data || []);
      } catch {}
    };
    loadRoles();
    return () => { cancelled = true; };
  }, [authenticated, user]);

  useEffect(() => {
    if (!menuOpen) return;
    const onPointerDown = (e: PointerEvent | MouseEvent | TouchEvent) => {
      const trigger = document.getElementById("user-menu-trigger");
      if (trigger && !trigger.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    };
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [menuOpen]);

  const handleMenuAction = useCallback((action: () => void) => {
    setMenuOpen(false);
    action();
  }, []);

  const handleQualityChange = useCallback((next: GameQuality) => {
    setQuality(next);
    writeGameQuality(next);
  }, []);

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
          <div className="user-badge" id="user-menu-trigger">
            <button
              type="button"
              className="user-badge__top user-badge__trigger"
              onClick={() => setMenuOpen(prev => !prev)}
              aria-haspopup="menu"
              aria-expanded={menuOpen}
            >
              <img src={getProfilePictureFromPrivy(user) || '/loadinglogo.png'} alt="avatar" className="user-badge__avatar" />
              <p className="user-badge__name">
                {getUsernameFromPrivy(user) || 'Player'}
              </p>
              <span className="user-badge__caret" aria-hidden="true">▾</span>
            </button>
            {shortAddress && (
              <button
                className="user-badge__meta"
                onClick={handleCopyWallet}
                title={walletAddress || ""}
                disabled={!walletAddress}
              >
                {copied ? 'Copied!' : shortAddress}
              </button>
            )}
            {menuOpen && (
              <div className="user-menu" role="menu">
                {roles.includes("admin") && (
                  <button
                    type="button"
                    className="user-menu__item"
                    role="menuitem"
                    onClick={() => handleMenuAction(() => navigate("/admin/dashboard"))}
                  >
                    Admin
                  </button>
                )}
                {roles.includes("sponsor") && (
                  <button
                    type="button"
                    className="user-menu__item"
                    role="menuitem"
                    onClick={() => handleMenuAction(() => navigate("/sponsor"))}
                  >
                    Host Match
                  </button>
                )}
                <div className="user-menu__group">
                  <span className="user-menu__label">Graphics</span>
                  <div className="user-menu__options">
                    {QUALITY_OPTIONS.map(option => (
                      <button
                        key={option}
                        type="button"
                        role="menuitemradio"
                        aria-checked={quality === option}
                        title={option === 'auto' ? qualityHint : undefined}
                        className={`user-menu__option ${quality === option ? 'is-active' : ''}`}
                        onClick={() => handleQualityChange(option)}
                      >
                        {QUALITY_LABELS[option]}
                      </button>
                    ))}
                  </div>
                </div>
                <button
                  type="button"
                  className="user-menu__item user-menu__item--logout"
                  role="menuitem"
                  onClick={() => handleMenuAction(() => logout())}
                >
                  Logout
                </button>
              </div>
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
