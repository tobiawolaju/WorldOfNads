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
