# Skin artwork

One 966px render per store **card**, named after the two catalog slots it
covers. The catalog lists the two default skins first, then the numeric combos,
whose ids pair up as `2n+1` (shaded) / `2n+2` (unshaded). Both ids of a pair
share a single render, so the store grid shows one card per skin rather than a
shaded and a flat edition side by side.

| File        | Skin          | Catalog ids                       |
| ----------- | ------------- | --------------------------------- |
| `1-2.png`   | Default Nad   | `s-default`, `s-default-unshaded` |
| `3-4.png`   | Classic Cap   | 1, 2                              |
| `5-6.png`   | Bedhead       | 3, 4                              |
| `7-8.png`   | Burger Fiend  | 5, 6                              |
| `9-10.png`  | Headset       | 7, 8                              |
| `11-12.png` | Viking        | 9, 10                             |
| `13-14.png` | Samurai       | 11, 12                            |
| `15-16.png` | Straw Hat     | 13, 14                            |
| `17-18.png` | Crowned       | 15, 16                            |
| `19-20.png` | Long Hair     | 17, 18                            |
| `21-22.png` | Just Duck     | 19, 20                            |
| `23-24.png` | Bare          | 21, 22                            |

The filename is derived from the skin id, never from the `image` field a skin
document carries, so a stale doc cannot point at artwork that is not here:

- web: `skinArtworkFileName()` in `../../src/lib/skinMapping.ts`
- game: `Dshbord._skin_basename()` in
  `../../../godot/scripts/screens/dshbord.gd`

Godot keeps downscaled 416px copies in `godot/assets/img/skins/`. Add a combo to
`backend/skinCombos.json` and it takes the next pair, so a new render is the only
asset work needed. The store grids in both the web build and Godot draw the
artwork in full colour; ownership reads from the card's resting opacity and its
name/price caption alone, so no `_gray` variants are kept.
