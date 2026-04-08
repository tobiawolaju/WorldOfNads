import React, { useEffect, useRef, useState } from "react";
import { BrowserRouter as Router, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";

// Layout Components
import BackgroundPattern from "./components/Background";
import RainbowBeam from "./components/RainbowBeam";
import TopNavbar from "./components/TopNavbar";

// UI
import { FullScreenLoader } from "./components/ui/fullscreen-loader";

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
const SpounsorDashbaord = lazy(() => import("./pages/SpounsorDashbaord"));
const AdminAnalytics = lazy(() => import("./pages/AdminAnalytics"));
const AdminUsers = lazy(() => import("./pages/AdminUsers"));
import { trackSessionEnded, trackSessionStarted } from "./lib/analyticsClient";
import { fetchUserRoles, getUsernameFromPrivy } from "./pages/firebaseClient";

const RequireRole: React.FC<{ role: string; children: React.ReactElement }> = ({ role, children }) => {
  const { ready, authenticated, user } = usePrivy();
  const [checking, setChecking] = useState(true);
  const [allowed, setAllowed] = useState(false);

  useEffect(() => {
    const verify = async () => {
      if (!ready) return;
      if (!authenticated || !user) {
        setAllowed(false);
        setChecking(false);
        return;
      }
      try {
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

  if (!ready || checking) return <FullScreenLoader />;
  if (!authenticated || !user || !allowed) return <Navigate to="/" replace />;

  return children;
};

const AppContent: React.FC = () => {
  const { ready, authenticated, user } = usePrivy();
  const location = useLocation();
  const sessionTrackedRef = useRef(false);
  const lastUserIdRef = useRef<string | null>(null);

  useEffect(() => {
    const viewportMeta = document.querySelector<HTMLMetaElement>('meta[name="viewport"]');
    if (!viewportMeta) return;

    const defaultViewport =
      "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no";
    const desktopBaseWidth = 1280;
    const desktopViewport = "width=1280, initial-scale=0.8, maximum-scale=0.8, user-scalable=no";
    const originalViewport = viewportMeta.getAttribute("content") || defaultViewport;
    const mobileDeviceQuery = window.matchMedia("(hover: none) and (pointer: coarse)");
    const landscapeQuery = window.matchMedia("(orientation: landscape)");

    const applyViewportMode = () => {
      const shouldUseDesktopMode = mobileDeviceQuery.matches && landscapeQuery.matches;
      if (!shouldUseDesktopMode) {
        viewportMeta.setAttribute("content", defaultViewport);
        return;
      }

      // Calculate the desktop viewport width needed so content fits without
      // introducing a horizontal scrollbar in mobile-landscape desktop mode.
      const documentWidth = Math.max(
        document.documentElement.scrollWidth,
        document.body?.scrollWidth ?? 0,
      );
      const requiredDesktopWidth = Math.max(desktopBaseWidth, Math.ceil(documentWidth));
      const desktopViewport =
        `width=${requiredDesktopWidth}, initial-scale=1.0, maximum-scale=1.0, user-scalable=no`;

      viewportMeta.setAttribute("content", desktopViewport);
    };

    applyViewportMode();
    landscapeQuery.addEventListener("change", applyViewportMode);
    mobileDeviceQuery.addEventListener("change", applyViewportMode);

    return () => {
      landscapeQuery.removeEventListener("change", applyViewportMode);
      mobileDeviceQuery.removeEventListener("change", applyViewportMode);
      viewportMeta.setAttribute("content", originalViewport);
    };
  }, []);

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

    const username = getUsernameFromPrivy(user);
    trackSessionStarted({ userId: user.id, metadata: { username } });

    const handleUnload = () => {
      trackSessionEnded({ userId: user.id, metadata: { username } });
    };

    window.addEventListener("beforeunload", handleUnload);
    return () => window.removeEventListener("beforeunload", handleUnload);
  }, [ready, authenticated, user]);

  if (!ready) {
    return <FullScreenLoader />;
  }

  // Hide navbar on /play route
  const hideNavbar = location.pathname === "/play";

  return (
    <>
      <BackgroundPattern />
      <RainbowBeam />
      <div style={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}>
        {!hideNavbar && <TopNavbar />}

        <main style={{ flex: 1 }}>
          <Suspense fallback={<FullScreenLoader />}>
            <Routes>
              {/* Public Routes */}
              <Route path="/" element={authenticated ? <Navigate to="/dashboard" replace /> : <Home />} />
              <Route path="/nad-arena" element={<NadArena />} />
              <Route path="/leaderboard" element={<Leaderboard />} />
              <Route path="/community" element={<Community />} />
              <Route path="/hosts" element={<Partners />} />
              <Route path="/milestone" element={<Milestone />} />
              <Route path="/partners" element={<Navigate to="/hosts" replace />} />
              <Route path="/careers" element={<Careers />} />
              <Route
                path="/admin/analytics"
                element={
                  <RequireRole role="admin">
                    <AdminAnalytics />
                  </RequireRole>
                }
              />
              <Route
                path="/admin/users"
                element={
                  <RequireRole role="admin">
                    <AdminUsers />
                  </RequireRole>
                }
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
    </>
  );
};

const App: React.FC = () => (
  <Router>
    <AppContent />
  </Router>
);

export default App;
