import { DEFAULT_LOBBY_BG } from "../data/lobbyBackgrounds";

// The dashboard's always-open cards: the shared training lobby and Chog World
// Order. Neither is an allocated match, so neither has a Firebase `matches/<id>`
// record, an entry fee or a prize pool.
//
// `default` is the shared room the room server has always allowed and which
// never needs a match record. Chog World Order is the second permanent room
// (`backend-rust/src/net.rs`: `CHOG_ROOM`), accepted without a record for the
// same reason. Every other id must be an allocated match: the room server reads
// the control plane's registry and refuses anything it does not find.
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
    image: "/lobbybg/trainingcard.jpg",
    lobbyBg: DEFAULT_LOBBY_BG,
    description: "Training Lobby is open for warmup runs and should always be playable.",
    url: "",
    ctaMode: "play"
  },
  {
    id: 2,
    matchId: "match-chog-world-order",
    sponsor: "Chog World Order",
    prize: "Free play",
    prizeAmount: 0,
    prizeToken: "WONs",
    status: "live",
    time: "Open",
    date: new Date().toISOString().slice(0, 10),
    // One second after the training card so the carousel still opens on Training
    // when both permanent rooms are live.
    startTime: Math.floor(Date.now() / 1000) + 1,
    image: "/lobbybg/chogcard.jpg",
    lobbyBg: "/lobbybg/chogbg.jpg",
    description: "Chog World Order is always open. No entry fee, no prize pool — drop in and hold the point.",
    url: "",
    ctaMode: "play"
  }
];
