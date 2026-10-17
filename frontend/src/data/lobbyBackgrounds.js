// Every image in `frontend/public/lobbybg/`, served at `/lobbybg/<name>`.
//
// The dashboard picks one of these at random each time the selected match card
// changes (see Dashboard.tsx). Drop a new image into `frontend/public/lobbybg/`
// and add its path here so the randomiser can choose it.
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

// Kept as the safety net if the folder above is ever empty.
export const FALLBACK_LOBBY_BG = "/lobbybg.jpeg";

// Pick a random backdrop, never returning `exclude` (the one currently shown) so
// changing match cards always visibly swaps the image.
export function pickRandomLobbyBg(exclude) {
  if (!lobbyBackgrounds.length) return FALLBACK_LOBBY_BG;
  if (lobbyBackgrounds.length === 1) return lobbyBackgrounds[0];
  let choice = lobbyBackgrounds[Math.floor(Math.random() * lobbyBackgrounds.length)];
  let guard = 0;
  while (choice === exclude && guard < 16) {
    choice = lobbyBackgrounds[Math.floor(Math.random() * lobbyBackgrounds.length)];
    guard += 1;
  }
  return choice;
}
