# World of Nads Skins

How a skin is defined, how attachments are chosen, and how the same skin renders
in the Godot game and on the web.

A skin is nothing but an **id plus a config**: the id names the skin, the config
(`skinConfig`) says which colours, which shader and which **attachments** the nad
wears. Adding a skin never requires code, and adding an attachment later never
breaks a skin that already exists.

## Skin ids and shading parity

| Id shape | Shading |
| --- | --- |
| **Odd number** (`0001`, `0003`, `1001`) | Shaded edition (`shader = "default"`, lit) |
| **Even number** (`0002`, `0004`, `1002`) | Unshaded variant (`shader = "unshaded"`, flat + outline) |
| **Non-numeric** (`s-default`, `s-default-unshaded`) | Whatever its config asks for |

Parity only applies to ids that are purely numeric, and it overrides whatever
`shader` the config contains — a numbered skin is always in its correct
shaded/unshaded slot by construction. Named ids keep their explicit behaviour.
Both shader variants exist because both are used: the unshaded pipeline
(`skin_unshaded.gdshader` + `outline.gdshader`) is what even ids and
`s-default-unshaded` run through.

Implementation: `SkinApplier._apply_shading_parity()` (Godot) and
`resolveShaderType()` (`frontend/src/lib/skinMapping.ts`, web).

## Attachment lists

A skin chooses what the nad wears with a flat list of node names:

```json
"attachments": ["duck", "hair_001"]
```

Rules — identical in Godot and on the web:

- **Exact set.** Listed names are shown, every other attachment is hidden.
- **Missing or empty list = wears nothing.** The default loadout
  (`["linnconcap", "duck"]`) is spelled out explicitly in
  `SkinApplier.FALLBACK_SHADED/FALLBACK_UNSHADED` and in
  `frontend/src/data/items.json`, never inherited implicitly.
- **Unknown names are ignored** (with a console warning). A skin may reference an
  attachment that only lands in `skin.tscn` later, and an old skin may still
  name a node that was renamed away — neither may break the rest of the skin.
- **Only visibility is toggled, never transforms.** Every attachment keeps the
  transform authored in `godot/scenes/skin.tscn`.

No colours are pinned onto attachments: they keep the materials they were
authored with. The body colour system (palette, outline, crown,
`shader_targets`) is a separate concern and works exactly as before.

## Slots

Attachments hang off bone attachment nodes in `godot/scenes/skin.tscn`. The
direct children of these paths are the equippable units
(`SkinApplier.ATTACHMENT_SLOTS`):

| Slot | Contents |
| --- | --- |
| `Skeleton3D/heddds/offset` | `linnconcap`, `vikingHemblet`, `strawhat`, `samuriehat`, `hair`, `hair_001`, `rown`, `burgr`, `hedset` |
| `Skeleton3D/hips` | `duck` |
| `Skeleton3D/Back/offset` | back items (empty by default; pickups only copy its position, they never reparent into it) |

Slot children are discovered at runtime, so a new attachment node needs **no
code change** — only a new *slot* (a new bone) needs its path added to
`ATTACHMENT_SLOTS`.

## Data flow

```
  Firebase skins/<id>.skinConfig          frontend/src/data/items.json
  (admin create-skin, migration scripts)  (local defaults)
            │                                       │
            │  GET /api/skins                       │ bundled store data
            ▼                                       ▼
  SkinApplier.seed_from_api() ──► _api_cache ──► get_skin_data()
            │                                       │
            │            parity rule applied here  │
            ▼                                       ▼
  Godot: SkinApplier.apply_skin()        Web: ThreeScene.tsx
  (materials, eye tint, attachments)     (toon/shader materials, GLB attachments)
```

`skinConfig` passes through the backend verbatim — no key whitelist on the API
or the `POST /admin/create-skin` route. The one place that rebuilds
`skinConfig` field-by-field is `backend/scripts/migrateSkinsToFirebase.js`; it
copies `attachments` too.

## Web preview (ThreeScene.tsx)

The store/dashboard preview dresses the same attachments as the game. Two
export steps keep it in sync:

1. **Attachment GLBs** — export every slot child from `skin.tscn` as its own
   GLB plus `manifest.json` into `frontend/public/attachments/`:

   ```
   Godot_v4.7-stable_win64_console.exe --headless --path godot --script res://tools/export_attachments.gd
   ```

   The manifest maps each name to its GLB file and its bone
   (`mixamorig_Head`, `mixamorig_Hips`, ...). Each GLB carries the node's
   authored bone-local transform: at runtime a `BoneAttachment3D` overwrites its
   own transform with the bone pose (verified by `tools/_probe_bone_attachment.gd`),
   so slot children live in pure bone space and re-parenting the GLB under the
   same bone reproduces the game's placement exactly.

2. **Godot web build** — after changing any GDScript or `skin.tscn`, re-export
   the game itself:

   ```
   Godot_v4.7-stable_win64_console.exe --headless --path godot --export-release "Web" ../frontend/public/godot/index.html
   ```

   `tools/*` (this repo's headless helpers) is excluded from both export
   presets.

The preview fails soft by design: a missing manifest, a missing GLB or an
unknown attachment name only means that item is not shown.

## Adding things

**A new attachment** (e.g. `wings`):

1. Add the node under the right slot in `godot/scenes/skin.tscn` and place it.
2. Re-run `tools/export_attachments.gd`.
3. Reference it: `"attachments": ["duck", "wings"]`.

**A new skin** (e.g. id `0004`, unshaded by parity):

1. Create it via admin/`POST /admin/create-skin` with its `skinConfig`:
   `palette`, `outline_color`, `crown_color`, `shader_targets`, and
   `attachments` (use `[]` for a bare nad).
2. Nothing else. Godot and the web both pick it up from `/api/skins`.

## Verifying changes

```
Godot_v4.7-stable_win64_console.exe --headless --path godot --script res://tools/_test_skin_applier.gd
```

Prints `PASS`/`FAIL` per expectation (attachment visibility, unknown-name
handling, parity, no-transform-touched guarantees) and exits non-zero on
failure.
