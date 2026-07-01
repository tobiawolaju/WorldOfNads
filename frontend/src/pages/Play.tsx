import React, { useEffect } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { resolveGameSkinName } from "../lib/skinMapping";

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

const Play: React.FC = () => {
  const { user } = usePrivy();
  const username = getUsernameFromPrivy(user);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const params = new URLSearchParams(window.location.search);
    const skin = resolveGameSkinName(params.get("skin") || params.get("skinId") || "s-default");
    const match = params.get("match") || "";
    const nextParams = new URLSearchParams({
      username,
      skin,
      ...(match ? { match } : {})
    });
    const nextUrl = `/play.html?${nextParams.toString()}`;

    if (window.location.pathname !== "/play.html" || window.location.search !== `?${nextParams.toString()}`) {
      window.location.replace(nextUrl);
    }
  }, [username]);
  return null;
};

export default Play;
