import React, { useEffect, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { resolveGameSkinName } from "../lib/skinMapping";

const BACKEND_URL = import.meta.env.VITE_ANALYTICS_API_URL || "https://worldofnads.onrender.com";

function getUsernameFromPrivy(user: any): string {
  if (!user?.linkedAccounts) return "Anon";
  const providers = [
    { type: "twitter_oauth", field: "username" },
    { type: "farcaster", field: "username" },
    { type: "google_oauth", field: "name" },
    { type: "twitch_oauth", field: "username" },
    { type: "tiktok_oauth", field: "username" },
    { type: "spotify_oauth", field: "name" }
  ];
  for (const provider of providers) {
    const acc = user.linkedAccounts.find((a: any) => a.type === provider.type);
    if (acc) {
      const val = acc[provider.field];
      if (val) return val;
    }
  }
  const wallet = user?.linkedAccounts?.find((acc: any) => acc.type === "wallet");
  return wallet?.address || "Anon";
}

async function requestAuthToken(username: string): Promise<string | null> {
  try {
    const res = await fetch(`${BACKEND_URL}/auth/request-token`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username })
    });
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.ok || !data.token) return null;
    return data.token;
  } catch {
    return null;
  }
}

const Play: React.FC = () => {
  const { user } = usePrivy();
  const username = getUsernameFromPrivy(user);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const redirectToGame = async () => {
      const params = new URLSearchParams(window.location.search);
      const skin = resolveGameSkinName(params.get("skin") || params.get("skinId") || "s-default");
      const match = params.get("match") || "";

      try {
        const skinRes = await fetch(`${BACKEND_URL}/api/skins`);
        const skinData = await skinRes.json();
        if (skinData.ok && Array.isArray(skinData.skins)) {
          sessionStorage.setItem("wons_skin_cache", JSON.stringify(skinData.skins));
        }
      } catch {}

      let urlUsername = username;
      const token = await requestAuthToken(username);
      if (token) {
        urlUsername = `${token}:${username}`;
      }

      const nextParams = new URLSearchParams({
        username: urlUsername,
        skin,
        ...(match ? { match } : {})
      });
      const nextUrl = `/play.html?${nextParams.toString()}`;

      setLoading(false);

      if (window.location.pathname !== "/play.html" || window.location.search !== `?${nextParams.toString()}`) {
        window.location.replace(nextUrl);
      }
    };

    redirectToGame();
  }, [username]);

  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "100vh", background: "#0a0a1a", color: "#fff" }}>
        <p>Authenticating...</p>
      </div>
    );
  }

  return null;
};

export default Play;
