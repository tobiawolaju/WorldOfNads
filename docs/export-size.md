# Export size budget

Godot exports the **whole project** because both presets use
`export_filter="all_resources"`. Anything that lives under `res://` and is
importable gets packed, even if no scene or script ever references it.

Baseline before the 2026-11 audit:

| Artifact | Size |
| --- | --- |
| `frontend/public/godot/index.pck` (Web, S3TC + ETC2) | 196.6 MB |
| `Release/wons.apk` (Android, arm64 only) | 168.8 MB |

## Where the bytes were

- 107.6 MB of GPU texture blobs in `.godot/imported`
  (53.8 MB S3TC + 53.8 MB ETC2 — the Web preset packs both formats).
- 29.7 MB of imported scenes (`.scn`) from glTF/FBX sources.
- 62.8 MB of that total belonged to **127 resources that nothing references**:
  leftover prop textures, duplicate glTF copies under `scenes/props/`,
  the unused `scene.gltf`/`scene.bin` level source, unused player FBX files,
  the old `assets/img/lobbybg/*` and `assets/img/skins/*` folders, and a stale
  `webexport/` dump.
- 196 MB → ~52 MB of that is `godot/scenes/busyland.tscn`, which embeds the
  level meshes, collisions and six `Image` sub-resources inline.

## What we changed

1. **`godot/export_presets.cfg`** — added the verified-unused resources to
   `exclude_filter` on both the Web and Android presets. They stay in the repo
   and in the editor; they are simply not packed.
   Expected saving: **-62.8 MB Web**, **-48.9 MB Android**.
2. **`process/size_limit=512`** on the 31 referenced prop/level textures that
   were imported at 1024×1024. Godot downscales on import, so the source PNGs
   stay untouched and the change is reversible.
   Expected saving: **-44 MB Web**, **-22 MB Android**.

Expected after reimport + re-export: **~90 MB pck** (Web) and **~100 MB APK**.

## Status (2026-11-18)

Two regressions were fixed on this pass:

1. **The Android APK had been exported with the debug template.** The packed
   `libgodot_android.so` was 67.13 MB, byte-identical to
   `export_templates/4.8.beta1/android_debug.apk`; the release template's is
   62.49 MB. Debug templates are also substantially slower at runtime, so this
   was a performance bug, not just a size one. Export with
   `--export-release "Android"` and leave "Export With Debug" unticked.
2. **27 heavy prop textures still imported at 512 px as ETC2 RGBA** (0.33 MB
   each instead of 0.17). They are now `process/size_limit=256` -> 85 KB each
   on ETC2. Affected: `trash_can_2`, `chain_link_fence_{0,2}`,
   `asian_mini_truck_{2,5,6,8}`, `broadcast_tower_game_ready (1)_{2,3,5}`,
   `water_bottle_{2,5}`, `sign_pole_{2,5,8}`, `trash_bag_2`, `old_keg_2`,
   `palete_game_ready_2`, `scrap_shield_2`, `set_of_cardboard_boxes (1)_2`,
   `supply_drop_box_-_fortnite_1`, `low_poly_barrel_21_2`, `lowpoly_grass_{0,1}`,
   `logo.png`, `mon.png` and `scenes/props/rpg7_-_anti_tank_0.png`.
3. **The four lobby background plates were stored lossless** (0.50-0.99 MB
   each). They are now lossy WebP at `compress/lossy_quality=0.85`:
   `lobbybg.jpeg` 39 KB, `lobbybg_masked.png` 39 KB, `chogcard.jpg` 117 KB,
   `chogbg.jpg` 74 KB.

Result after reimport + both exports:

| Artifact | Before | After |
| --- | --- | --- |
| `frontend/public/godot/index.pck` | 94,038,928 B (89.7 MiB) | 84,836,332 B (80.9 MiB) |
| `Release/wons.apk` | 107,822,441 B (102.8 MiB, **debug**) | 96,726,641 B (92.25 MiB, release) |

The pck figure also includes the art restored in the 2026-11-17 fix, so the
real saving is larger than the table suggests. Both exports were produced
headless:

```
godot --headless --path godot --export-release "Web" ../frontend/public/godot/index.html
godot --headless --path godot --export-release "Android" ../Release/wons.apk
```

then validated with `--headless --main-pack frontend/public/godot/index.pck` on
`lobby.tscn` and `gameplay.tscn` (no "Can't load dependency"). The APK is
7.75 MiB under GitHub's 100 MiB per-file limit.

## Status (2026-11-17)

- Commit `b16c2c3` — exclude list + 31 × `size_limit=512` + this doc.
- Godot editor reopened and **reimported the capped textures**: `.godot/imported`
  went from 148.1 MB to 104.1 MB (S3TC 53.8 → 31.8 MB, ETC2 53.8 → 31.8 MB).
  Spot check: `trash_can_2.png` is now 0.33 MB per format instead of 1.34 MB.
- Preset exclude filter verified byte-identical to `godot/export-exclude.txt`.
- **Pending:** re-export Web + Android, then check the new `index.pck` size.
  Estimated ~90 MB Web / ~100 MB APK. Under 100 MB means the pck can finally be
  committed and the web deploy fixed.
- `Godot` may offer "Recovery Mode" after an unclean shutdown; it only disables
  tool scripts for that session, it does not revert any files.

## Regression found after the first trimmed export (2026-11-17)

Reproduced by running the exported pck headless:

```
Godot_v4.8-beta1_win64_console.exe --headless --main-pack frontend/public/godot/index.pck res://scenes/lobby.tscn
```

Three kinds of resource are referenced from *inside* imported binaries and were
invisible to a `res://` text search, so the first exclude list removed them:

1. **glTF sibling textures.** `busyland.tscn` uses
   `assets/models/props/low_poly_barrel_21.glb`, whose imported `.scn` loads
   `low_poly_barrel_21_{0,1,2}.png` as external resources. With those excluded,
   `busyland.tscn` → `lobby.tscn` and `gameplay.tscn` all failed to load (the
   Play button bounced back to the home screen). Restored + capped at 512.
2. **`assets/img/lobbybg/`** is loaded by name at runtime in `dshbord.gd`
   (`"/lobbybg/lobby (1).jpg"` → `res://assets/img/lobbybg/%s`,
   `_lobby_bg_texture()` / `_card_texture()`). Excluding it made every match card
   fall back to `MATCH_SRC`, i.e. all card images looked identical. Restored.
3. **`assets/img/skins/`** is `SKIN_DIR + base + ".png"` in `dshbord.gd`.
   Restored.

Rule: a model's sibling textures are part of the model. Before excluding an
image, check whether a `.glb`/`.fbx` with the same stem is still exported, and
whether any script builds the path from a directory constant or a
`"/lobbybg/..."`-style record field.

## Rules for new art

- Do not drop a second `.glb` copy of a model into `scenes/props/`; reference
  the file in `assets/models/` instead.
- Before committing new art, check that it is referenced by a scene/script
  (`res://` path or `uid://`), otherwise add it to `exclude_filter` or delete it.
- 512 px is the default for world props. 1024 px only for player/skin textures
  and full-screen UI art.
- Textures are VRAM compressed (S3TC for desktop, ETC2 for mobile). Keep both
  enabled for Web unless we drop mobile browsers.
- `godot/scenes/busyland.tscn` is the single largest tracked file. Do not
  "make local" another imported level on top of it; instance the glTF instead.
