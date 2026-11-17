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
