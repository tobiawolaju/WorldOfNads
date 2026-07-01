const toStartTime = (dateTime) => Math.floor(new Date(dateTime).getTime() / 1000);

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
  }
];
