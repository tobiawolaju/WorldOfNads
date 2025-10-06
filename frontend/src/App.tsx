import React from "react";
import { BrowserRouter as Router, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";

// Layout Components
import BackgroundPattern from "./components/Background";
import TopNavbar from "./components/TopNavbar";
import Footer from "./components/Footer";

// UI
import { FullScreenLoader } from "./components/ui/fullscreen-loader";

// Pages
import Home from "./pages/Home";
import Crew from "./pages/Crew";
import PreTGEArena from "./pages/PreTGEArena";
import Roadmap from "./pages/Roadmap";
import Community from "./pages/Community";
import Partners from "./pages/Partners";
import Dashboard from "./pages/Dashboard";
import Play from "./pages/Play";

const AppContent: React.FC = () => {
  const { ready, authenticated, login } = usePrivy();
  const location = useLocation();

  if (!ready) {
    return <FullScreenLoader />;
  }

  // Hide navbar on /play route
  const hideNavbar = location.pathname === "/play";

  return (
    <>
      <BackgroundPattern />
      <div style={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}>
        {!hideNavbar && <TopNavbar />} {/* 👈 conditionally render navbar */}

        <main style={{ flex: 1 }}>
          <Routes>
            {/* Public Routes */}
            <Route path="/" element={<Home onLogin={login} authenticated={authenticated} />} />
            <Route path="/crew" element={<Crew />} />
            <Route path="/pre-tge-arena" element={<PreTGEArena />} />
            <Route path="/roadmap" element={<Roadmap />} />
            <Route path="/community" element={<Community />} />
            <Route path="/partners" element={<Partners />} />

            {/* Protected Routes */}
            <Route
              path="/dashboard"
              element={authenticated ? <Dashboard /> : <Navigate to="/" replace />}
            />
            <Route
              path="/play"
              element={authenticated ? <Play /> : <Navigate to="/" replace />}
            />

            {/* Fallback */}
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>

        <Footer />
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
