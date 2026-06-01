const DEFAULT_GAME_SKIN_NAME = "defaultnad";

const GAME_SKIN_NAME_BY_KEY: Record<string, string> = {
  "s-default": DEFAULT_GAME_SKIN_NAME,
  s0: "buggy",
  s1: "Aurum",
  s2: "Abbss",
  s3: "Hellion",
  s4: "Seraphim",
  s5: "mouch",
  s6: "john deo",
  defaultnad: DEFAULT_GAME_SKIN_NAME,
  buggy: "buggy",
  aurum: "Aurum",
  abbss: "Abbss",
  abyss: "Abbss",
  hellion: "Hellion",
  seraphim: "Seraphim",
  mouch: "mouch",
  "john deo": "john deo",
  johndeo: "john deo"
};

function normalizeSkinKey(rawSkin: string | null | undefined): string {
  return String(rawSkin || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

export function resolveGameSkinName(rawSkin: string | null | undefined): string {
  const key = normalizeSkinKey(rawSkin);
  return GAME_SKIN_NAME_BY_KEY[key] || DEFAULT_GAME_SKIN_NAME;
}
