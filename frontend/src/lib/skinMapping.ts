const DEFAULT_GAME_SKIN_NAME = "defaultnad";

const GAME_SKIN_NAME_BY_KEY: Record<string, string> = {
  "s-default": DEFAULT_GAME_SKIN_NAME,
  s1: "sprout",
  s2: "cobalt",
  s3: "magma",
  s4: "aether",
  defaultnad: DEFAULT_GAME_SKIN_NAME,
  sprout: "sprout",
  cobalt: "cobalt",
  magma: "magma",
  aether: "aether"
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
