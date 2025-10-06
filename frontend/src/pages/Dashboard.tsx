import React from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";

const Dashboard: React.FC = () => {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();

  if (!ready) return <FullScreenLoader />;
  if (!authenticated) return null; // handled by router redirect

  return (
    <div className="bg-[#E0E7FF66] min-h-screen flex flex-col justify-between p-6">
      {/* Main content */}
      <main className="flex-grow flex justify-center items-center">
        <div className="max-w-3xl w-full bg-white/70 backdrop-blur-md rounded-2xl shadow-lg p-8 border border-indigo-100">
          <h2 className="text-2xl font-semibold text-gray-800 mb-6 text-center">
            User Dashboard
          </h2>

          <div className="overflow-auto max-h-[70vh] rounded-lg border border-gray-200 bg-gray-50 p-4">
            <pre className="text-sm text-gray-800 whitespace-pre-wrap break-words">
              {JSON.stringify(user, null, 2)}
            </pre>
          </div>
        </div>
      </main>

      {/* Footer buttons */}
      <footer className="flex justify-center gap-6 py-6">
        <button
          onClick={() => navigate("/play")}
          className="px-6 py-3 bg-indigo-600 text-white text-lg rounded-full shadow-md hover:bg-indigo-700 transition"
        >
          Join Match
        </button>

        <button
          onClick={logout}
          className="px-6 py-3 bg-red-500 text-white text-lg rounded-full shadow-md hover:bg-red-600 transition"
        >
          Logout
        </button>
      </footer>
    </div>
  );
};

export default Dashboard;
