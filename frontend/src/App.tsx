import React, { useEffect, useRef } from "react";
import { BrowserRouter as Router, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";

// Layout Components
import BackgroundPattern from "./components/Background";
import TopNavbar from "./components/TopNavbar";
// UI
import { FullScreenLoader } from "./components/ui/fullscreen-loader";
import Footer from "./components/Footer";

// Pages
import Home from "./pages/Home";
import Crew from "./pages/DexSwap";
import PreTGEArena from "./pages/PreTGEArena";
import Roadmap from "./pages/Leaderboard";
import Community from "./pages/FAQ";
import Partners from "./pages/Partners";
import Dashboard from "./pages/Dashboard";
import Play from "./pages/Play";
import Careers from "./pages/Careers";
import SpounsorDashbaord from "./pages/SpounsorDashbaord";
import AdminAnalytics from "./pages/AdminAnalytics";
import { trackSessionEnded, trackSessionStarted } from "./lib/analyticsClient";
import { getUsernameFromPrivy } from "./pages/firebaseClient";

const AppContent: React.FC = () => {
  const { ready, authenticated, user } = usePrivy();
  const location = useLocation();
  const sessionTrackedRef = useRef(false);
  const lastUserIdRef = useRef<string | null>(null);

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
  const hideFooter = location.pathname === "/dashboard";

  return (
    <>
      <BackgroundPattern />
      <div style={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}>
        {!hideNavbar && <TopNavbar />}

        <main style={{ flex: 1 }}>
          <Routes>
            {/* Public Routes */}
            <Route path="/" element={authenticated ? <Navigate to="/dashboard" replace /> : <Home />} />
            <Route path="/crew" element={<Crew />} />
            <Route path="/pre-tge-arena" element={<PreTGEArena />} />
            <Route path="/roadmap" element={<Roadmap />} />
            <Route path="/community" element={<Community />} />
            <Route path="/partners" element={<Partners />} />
            <Route path="/careers" element={<Careers />} />
            <Route path="/admin/analytics" element={<AdminAnalytics />} />

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
              element={authenticated ? <SpounsorDashbaord /> : <Navigate to="/" replace />}
            />

            {/* Fallback */}
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>

        {!hideFooter && <Footer />}
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
