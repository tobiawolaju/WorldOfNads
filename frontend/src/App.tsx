import React from "react";
import { BrowserRouter as Router, Routes, Route, Navigate, useLocation } from "react-router-dom";

// Layout Components
import BackgroundPattern from "./components/Background";
import TopNavbar from "./components/TopNavbar";
// UI
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

const AppContent: React.FC = () => {
  const location = useLocation();

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
            <Route path="/" element={<Home />} />
            <Route path="/crew" element={<Crew />} />
            <Route path="/pre-tge-arena" element={<PreTGEArena />} />
            <Route path="/roadmap" element={<Roadmap />} />
            <Route path="/community" element={<Community />} />
            <Route path="/partners" element={<Partners />} />
            <Route path="/careers" element={<Careers />} />

            {/* Previously protected routes - now public */}
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/play" element={<Play />} />

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
