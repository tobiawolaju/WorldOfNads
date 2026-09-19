const toStartTime = (dateTime) => Math.floor(new Date(dateTime).getTime() / 1000);
const inMinutes = (m) => toStartTime(new Date(Date.now() + m * 60 * 1000));
const inDays = (d) => toStartTime(new Date(Date.now() + d * 24 * 60 * 60 * 1000));

export const staticMatches = [
  {
    id: 1,
    matchId: "match-training-lobby",
    sponsor: "Training Lobby",
    prize: "Practice",
    prizeAmount: 0,
    prizeToken: "WONs",
    status: "live",
    time: "Open",
    date: new Date().toISOString().slice(0, 10),
    startTime: Math.floor(Date.now() / 1000),
    image: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg",
    description: "Training Lobby is open for warmup runs and should always be playable.",
    url: "",
    ctaMode: "play"
  },
  {
    id: 2,
    matchId: "match-sunset-showdown",
    sponsor: "NadCity Arena",
    prize: "1.5K WONs",
    prizeAmount: 1500,
    prizeToken: "WONs",
    status: "live",
    time: "Live",
    date: new Date().toISOString().slice(0, 10),
    startTime: inMinutes(5),
    image: "/lobbybg.jpeg",
    description: "Sunset Showdown at NadCity Arena. First to flag takes the 1.5K WONs pot.",
    url: "",
    ctaMode: "countdown"
  },
  {
    id: 3,
    matchId: "match-weekend-clash",
    sponsor: "Monad Labs",
    prize: "3K WONs",
    prizeAmount: 3000,
    prizeToken: "WONs",
    status: "live",
    time: "Live",
    date: new Date().toISOString().slice(0, 10),
    startTime: inMinutes(30),
    image: "/lobbybg.jpeg",
    description: "The Weekend Clash is live. Cash prizes for the top 3 flags planted.",
    url: "",
    ctaMode: "countdown"
  },
  {
    id: 4,
    matchId: "match-champions-cup",
    sponsor: "WONs Major",
    prize: "10K WONs",
    prizeAmount: 10000,
    prizeToken: "WONs",
    status: "upcoming",
    time: "Upcoming",
    date: "",
    startTime: inDays(2),
    image: "/lobbybg.jpeg",
    description: "The WONs Major Championship Cup. Winner takes home 10K WONs.",
    url: "",
    ctaMode: "countdown"
  },
  {
    id: 7,
    matchId: "match-alpha-sprint",
    sponsor: "Alpha Sprint",
    prize: "500 WONs",
    prizeAmount: 500,
    prizeToken: "WONs",
    status: "completed",
    time: "Completed",
    date: "",
    startTime: inDays(-2),
    image: "/lobbybg.jpeg",
    description: "Alpha Sprint is done — check the leaderboard for the final standings.",
    url: "",
    ctaMode: "countdown"
  }
];