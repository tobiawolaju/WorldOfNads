import React, { useEffect, useRef, useState } from "react";
import { BrowserRouter as Router, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";

// Layout Components
import BackgroundPattern from "./components/Background";
import RainbowBeam from "./components/RainbowBeam";
import TopNavbar from "./components/TopNavbar";
import FullscreenToggle from "./components/FullscreenToggle";

// UI
import { FullScreenLoader } from "./components/ui/fullscreen-loader";
import { ToastContainer } from "react-toastify";

import { lazy, Suspense } from "react";

// Pages (Lazy Loaded)
const Home = lazy(() => import("./pages/Home"));
const NadArena = lazy(() => import("./pages/NadArena"));
const Leaderboard = lazy(() => import("./pages/Leaderboard"));
const Community = lazy(() => import("./pages/FAQ"));
const Partners = lazy(() => import("./pages/Partners"));
const Milestone = lazy(() => import("./pages/Milestone"));
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Play = lazy(() => import("./pages/Play"));
const Careers = lazy(() => import("./pages/Careers"));
const Waitlist = lazy(() => import("./pages/Waitlist"));
// Device authorization page for native (Android/iOS/desktop) clients. NOT the
// game's normal login page -- see docs/authentication.md.
const DeviceAuth = lazy(() => import("./pages/DeviceAuth"));
const SpounsorDashbaord = lazy(() => import("./pages/SpounsorDashbaord"));
const AdminDashboard = lazy(() => import("./pages/AdminDashboard"));
import { trackSessionEnded, trackSessionStarted } from "./lib/analyticsClient";

const RequireRole: React.FC<{ role: string; children: React.ReactElement }> = ({ role, children }) => {
  const { ready, authenticated, user } = usePrivy();
  const [checking, setChecking] = useState(true);
  const [allowed, setAllowed] = useState(false);
  const [showLoader, setShowLoader] = useState(true);

  useEffect(() => {
    const verify = async () => {
      if (!ready) return;
      if (!authenticated || !user) {
        setAllowed(false);
        setChecking(false);
        return;
      }
      try {
        const { fetchUserRoles, getUsernameFromPrivy } = await import("./pages/firebaseClient");
        const username = getUsernameFromPrivy(user);
        const roles = await fetchUserRoles(username);
        setAllowed(roles.includes(role));
      } catch (error) {
        console.error("Failed to verify role", error);
        setAllowed(false);
      } finally {
        setChecking(false);
      }
    };

    verify();
  }, [ready, authenticated, user, role]);

  useEffect(() => {
    setShowLoader(!ready || checking);
  }, [ready, checking]);

  return (
    <>
      <FullScreenLoader visible={showLoader} />
      {!showLoader && (!authenticated || !user || !allowed ? <Navigate to="/" replace /> : children)}
    </>
  );
};

// Snapshot of the device landscape width used for mobile desktop-mode.
// Cached at module scope so fullscreen toggles / resize events can't re-derive
// a different scale and blow up text/button sizes.
let cachedLandscapeWidth: number | null = null;

const AppContent: React.FC = () => {
  const { ready, authenticated, user } = usePrivy();
  const location = useLocation();
  const sessionTrackedRef = useRef(false);
  const lastUserIdRef = useRef<string | null>(null);
  const [showLoader, setShowLoader] = useState(true);


  useEffect(() => {
    document.body.classList.toggle("play-immersive", location.pathname === "/play");

    return () => {
      document.body.classList.remove("play-immersive");
    };
  }, [location.pathname]);

  useEffect(() => {
    const viewportMeta = document.querySelector<HTMLMetaElement>('meta[name="viewport"]');
    if (!viewportMeta) return;

    const defaultViewport =
      "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover";
    const originalViewport = viewportMeta.getAttribute("content") || defaultViewport;
    const mobileDeviceQuery = window.matchMedia("(hover: none) and (pointer: coarse)");
    const landscapeQuery = window.matchMedia("(orientation: landscape)");

    const applyViewportMode = () => {
      const shouldUseDesktopMode = mobileDeviceQuery.matches && landscapeQuery.matches;
      const inFullscreen = Boolean(
        (document as any).fullscreenElement ||
          (document as any).webkitFullscreenElement
      );
      const html = document.documentElement;
      html.classList.toggle("is-fullscreen", inFullscreen);
      html.classList.toggle("desktop-mode", shouldUseDesktopMode);
      // Fullscreen renders on the native device width so the 3D canvas is
      // never CSS-zoomed (Chrome mis-renders WebGL canvases under an ancestor
      // CSS zoom). The compact "zoomed-out" look is reproduced in CSS by
      // scaling only the right info panel via --fs-zoom.
      if (!shouldUseDesktopMode || inFullscreen) {
        const fsScale = Math.min(1, (Math.max(screen.width, screen.height) - 50) / 1280);
        cachedLandscapeWidth = null;
        (html.style as any).zoom = "";
        html.style.setProperty("--rev-scale", "1");
        html.style.setProperty("--fs-zoom", fsScale.toString());
        viewportMeta.setAttribute("content", defaultViewport);
        return;
      }

      // Render at 1280px desktop width, then zoom out so it fits the
      // device screen exactly – no horizontal overscroll.
      const desktopWidth = 1280;
      if (cachedLandscapeWidth === null) {
        cachedLandscapeWidth = Math.max(screen.width, screen.height) - 50;
      }
      const scale = Math.min(1, cachedLandscapeWidth / desktopWidth);
      const revScale = 1 / scale;
      const desktopViewport =
        `width=${desktopWidth}, initial-scale=${scale}, maximum-scale=${scale}, user-scalable=no, viewport-fit=cover`;

      viewportMeta.setAttribute("content", desktopViewport);
      html.style.setProperty("--rev-scale", revScale.toString());
      html.style.setProperty("--fs-zoom", "1");
      (html.style as any).zoom = "";
    };

    let resizeTimeout: NodeJS.Timeout;
    const throttledApply = () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(applyViewportMode, 200);
    };

    // Re-apply the same (cached) scale when entering/exiting fullscreen instead
    // of re-deriving it from screen dimensions that change in fullscreen mode.
    // Chrome re-reads the viewport meta multiple times across the fullscreen
    // transition, so re-apply it a few times afterwards to keep the layout
    // identical before and after fullscreen.
    const fullscreenTimers: number[] = [];
    const handleFullscreenChange = () => {
      clearTimeout(resizeTimeout);
      fullscreenTimers.forEach((t) => clearTimeout(t));
      fullscreenTimers.length = 0;
      applyViewportMode();
      [50, 150, 400].forEach((ms) => {
        fullscreenTimers.push(window.setTimeout(applyViewportMode, ms));
      });
    };

    applyViewportMode();

    window.addEventListener("resize", throttledApply);
    document.addEventListener("fullscreenchange", handleFullscreenChange);
    document.addEventListener("webkitfullscreenchange", handleFullscreenChange);
    landscapeQuery.addEventListener("change", applyViewportMode);
    mobileDeviceQuery.addEventListener("change", applyViewportMode);

    return () => {
      clearTimeout(resizeTimeout);
      fullscreenTimers.forEach((t) => clearTimeout(t));
      window.removeEventListener("resize", throttledApply);
      document.removeEventListener("fullscreenchange", handleFullscreenChange);
      document.removeEventListener("webkitfullscreenchange", handleFullscreenChange);
      landscapeQuery.removeEventListener("change", applyViewportMode);
      mobileDeviceQuery.removeEventListener("change", applyViewportMode);
      viewportMeta.setAttribute("content", originalViewport);
      document.documentElement.style.setProperty('--rev-scale', '1');
      document.documentElement.style.setProperty('--fs-zoom', '1');
      (document.documentElement.style as any).zoom = "";
    };
  }, [location.pathname]);


  useEffect(() => {
    const themeColorMeta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    if (!themeColorMeta) return;

    const originalThemeColor = themeColorMeta.getAttribute("content") || "#e795e7";
    const isHomeRoute = location.pathname === "/" || location.pathname === "/home";

    if (isHomeRoute) {
      themeColorMeta.setAttribute("content", originalThemeColor);
      return;
    }

    const darkModeQuery = window.matchMedia("(prefers-color-scheme: dark)");

    const applyThemeColor = () => {
      const routeThemeColor = darkModeQuery.matches ? "#6553c7" : "#ffffff";
      themeColorMeta.setAttribute("content", routeThemeColor);
    };

    applyThemeColor();
    darkModeQuery.addEventListener("change", applyThemeColor);

    return () => {
      darkModeQuery.removeEventListener("change", applyThemeColor);
      themeColorMeta.setAttribute("content", originalThemeColor);
    };
  }, [location.pathname]);

  useEffect(() => {
    if (user?.id && lastUserIdRef.current !== user.id) {
      sessionTrackedRef.current = false;
      lastUserIdRef.current = user.id;
    }
  }, [user]);

  useEffect(() => {
    if (!ready || !authenticated || !user) return;
    if (sessionTrackedRef.current) return;
    sessionTrackedRef.current = true;

    let unlisten: (() => void) | undefined;

    void (async () => {
      const { getUsernameFromPrivy } = await import("./pages/firebaseClient");
      const username = getUsernameFromPrivy(user);
      trackSessionStarted({ userId: user.id, metadata: { username } });

      const handleUnload = () => {
        trackSessionEnded({ userId: user.id, metadata: { username } });
      };

      window.addEventListener("beforeunload", handleUnload);
      unlisten = () => window.removeEventListener("beforeunload", handleUnload);
    })();

    return () => unlisten?.();
  }, [ready, authenticated, user]);

  useEffect(() => {
    setShowLoader(!ready);
  }, [ready]);

  useEffect(() => {
    const t = window.setTimeout(() => {
      void import("./pages/Dashboard");
      void import("./pages/Play");
      void import("./pages/NadArena");
      void import("./pages/Leaderboard");
    }, 2500);
    return () => window.clearTimeout(t);
  }, []);

  // Hide navbar on immersive/special landing routes
  const hideNavbar = location.pathname === "/play" || location.pathname === "/auth";
  const hideTopNavbarContents = location.pathname === "/waitlist" || location.pathname === "/wait-list";

  return (
    <>
      <BackgroundPattern />
      <RainbowBeam />
      <FullscreenToggle />
      <FullScreenLoader visible={showLoader} />
      <ToastContainer
        position="top-center"
        autoClose={5000}
        hideProgressBar
        closeOnClick={false}
        pauseOnHover
        draggable={false}
        closeButton={false}
        icon={false}
        className="!bg-transparent !shadow-none"
        style={{ background: "transparent", boxShadow: "none" }}
      />
      {!showLoader && (
        <div style={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}>
          {!hideNavbar && <TopNavbar hideContents={hideTopNavbarContents} />}

          <main style={{ flex: 1 }}>
            <Suspense fallback={<FullScreenLoader visible />}>
              <Routes>
                {/* Public Routes */}
                <Route path="/" element={authenticated ? <Navigate to="/dashboard" replace /> : <Home />} />
                {/* Device linking for native clients. Reachable signed-out on
                    purpose: the page shows what is asking before sign-in. */}
                <Route path="/auth" element={<DeviceAuth />} />
                <Route path="/nad-arena" element={<NadArena />} />
                <Route path="/leaderboard" element={<Leaderboard />} />
                <Route path="/community" element={<Community />} />
                <Route path="/hosts" element={<Partners />} />
                <Route path="/milestone" element={<Milestone />} />
                <Route path="/partners" element={<Navigate to="/hosts" replace />} />
                <Route path="/careers" element={<Careers />} />
                <Route path="/waitlist" element={<Waitlist />} />
                <Route
                  path="/admin"
                  element={
                    <RequireRole role="admin">
                      <AdminDashboard />
                    </RequireRole>
                  }
                />
                <Route
                  path="/admin/dashboard"
                  element={
                    <RequireRole role="admin">
                      <AdminDashboard />
                    </RequireRole>
                  }
                />
                <Route
                  path="/admin/analytics"
                  element={<Navigate to="/admin/dashboard" replace />}
                />
                <Route
                  path="/admin/users"
                  element={<Navigate to="/admin/dashboard" replace />}
                />
                <Route
                  path="/admin/contracts"
                  element={<Navigate to="/admin/dashboard" replace />}
                />
                <Route
                  path="/admin/skins"
                  element={<Navigate to="/admin/dashboard" replace />}
                />

                {/* Protected Routes */}
                <Route
                  path="/dashboard"
                  element={authenticated ? <Dashboard /> : <Navigate to="/" replace />}
                />
                <Route
                  path="/play"
                  element={authenticated ? <Play /> : <Navigate to="/" replace />}
                />
                <Route
                  path="/sponsor"
                  element={
                    <RequireRole role="sponsor">
                      <SpounsorDashbaord />
                    </RequireRole>
                  }
                />

                {/* Fallback */}
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </Suspense>
          </main>
        </div>
      )}
    </>
  );
};

const App: React.FC = () => (
  <Router>
    <AppContent />
  </Router>
);

export default App;
