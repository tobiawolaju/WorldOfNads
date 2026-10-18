import { DEFAULT_LOBBY_BG } from "../data/lobbyBackgrounds";

// The dashboard's only placeholder card: the shared training lobby.
//
// It is deliberately NOT a match id. The room server only accepts rooms a host
// allocated (it mirrors Firebase `matches`), so anything else — including every
// demo id that used to live here (match-training-lobby, match-sunset-showdown,
// match-weekend-clash, match-champions-cup, match-alpha-sprint) — is refused with
// `1008 unknown_match`. Training instead passes `default`, the shared room, which
// the server always allows and which never needs a match record.
//
// Everything else on the dashboard is a real allocated match, loaded from Firebase
// in Dashboard.tsx and merged in over this list.
export const staticMatches = [
  {
    id: 1,
    matchId: "default",
    sponsor: "Training Lobby",
    prize: "Practice",
    prizeAmount: 0,
    prizeToken: "WONs",
    status: "live",
    time: "Open",
    date: new Date().toISOString().slice(0, 10),
    startTime: Math.floor(Date.now() / 1000),
    image: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg",
    lobbyBg: DEFAULT_LOBBY_BG,
    description: "Training Lobby is open for warmup runs and should always be playable.",
    url: "",
    ctaMode: "play"
  }
];
