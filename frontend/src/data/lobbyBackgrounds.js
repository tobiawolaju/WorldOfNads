// Every image in `frontend/public/lobbybg/`, served at `/lobbybg/<name>`.
//
// These are the selectable lobby backdrops. The sponsor form picks one per match
// (stored as `lobbyBg` on the match record) and the dashboard shows the selected
// match's own choice — never a random one. Drop a new image into
// `frontend/public/lobbybg/` and add its path here to make it selectable.
export const lobbyBackgrounds = [
  "/lobbybg/lobby (1).jpg",
  "/lobbybg/lobby (2).jpg",
  "/lobbybg/lobby (3).jpg",
  "/lobbybg/lobby (4).jpg",
  "/lobbybg/lobby (5).jpg",
  "/lobbybg/lobby (6).jpg",
  "/lobbybg/lobby (7).jpg",
  "/lobbybg/lobby (8).jpg",
  "/lobbybg/lobby (9).jpg",
];

// Human-readable labels for the picker, aligned with `lobbyBackgrounds` by index.
export const lobbyBackgroundOptions = lobbyBackgrounds.map((src, index) => ({
  value: src,
  label: `Lobby ${index + 1}`,
}));

// Kept as the safety net if the folder above is ever empty.
export const FALLBACK_LOBBY_BG = "/lobbybg.jpeg";

// The picker's initial choice for a brand-new match.
export const DEFAULT_LOBBY_BG = lobbyBackgrounds[0] || FALLBACK_LOBBY_BG;

// Backdrops are matched to a match id, not rolled at random. This hashes the id
// onto the list above; it is the same hash
// `backend/scripts/assignLobbyBackgrounds.js` uses to backfill older records, so a
// match shows the same image before and after its record is backfilled.
export function stableLobbyBgFor(matchId) {
  if (!matchId || !lobbyBackgrounds.length) return FALLBACK_LOBBY_BG;
  let hash = 0;
  for (let i = 0; i < matchId.length; i += 1) {
    hash = (hash * 31 + matchId.charCodeAt(i)) >>> 0;
  }
  return lobbyBackgrounds[hash % lobbyBackgrounds.length];
}
