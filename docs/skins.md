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

## The skin index (id &#8660; combo)

For numbered skins an id is not just a label — it is a slot in an ordered
catalog. `backend/skinCombos.json` lists the combinations in order:

```
combo n (0-based)  ->  ids 2n+1 (shaded, odd)  and  2n+2 (unshaded, even)
id N               ->  combo floor((N-1)/2)
```

So `0001`/`0002` are the shaded and flat halves of combo 1, `0003`/`0004` of
combo 2, and so on — every possible outcome automatically gets both variants.
Each combo is one readable line:

```json
{ "name": "Viking", "attachments": ["vikingHemblet"] }
```

The list is **append-only**: adding a combo extends the index while old ids keep
their slot. Non-numeric ids (`s-default`) sit outside the index and are pinned
in the same file's `defaults` map.

`backend/skinIndex.js` is the single implementation of the mapping
(`comboForId`, `attachmentsForId`, `idsForCombo`) and serves it at
`GET /api/skin-combos` as `{ combos, defaults }`. Both clients fetch that and
seed an id index:

- Godot: `SkinApplier.seed_index_from_api()` (called by `PlayerManager` and
  `preview.tscn`). `get_skin_data()` falls back to the index for any id whose own
  config has no `attachments` list.
- Web: `buildComboMap()` / `resolveSkinAttachments()` in `skinMapping.ts`, used
  by the dashboard before it hands a skin to `ThreeScene`.

Materializing docs is convenience, not a requirement: a brand new numbered id
(or a preview of an unminted one) dresses correctly straight from the index. A
skin that pins its own `attachments` list always wins over the index.

Numeric ids are normalised (`0002` == `2`) on both sides, so zero-padded ids,
bare ids and the index all agree.

### Materializing the index

```
cd backend
node scripts/generateSkinsFromCombos.js                        # dry run
node scripts/generateSkinsFromCombos.js --write                # stamp existing skins
node scripts/generateSkinsFromCombos.js --write --create-missing
```

- **Stamp (default write):** for every existing skin, set `skinConfig.attachments`
  to the combo its id owns, preserving palette, name and tier. This is what
  fixed the pre-attachments skins that rendered bare.
- **`--create-missing`:** also write a doc for every combo pair that has no skin
  yet, so a future mint/preview of that id resolves the right combo. Opt-in,
  because the in-game store and the web dashboard list every `/api/skins` entry.

`POST /admin/create-skin` derives attachments from the index when the caller
does not pass a list, so minting a new numbered id dresses it with no extra
data entry.

### Resetting to a clean catalog

A fresh `WONsSkins` starts at `nextSkinId = 1`, so creating one skin per combo
slot in index order makes the on-chain id, the Firebase doc key and the combo
all line up exactly.

```
cd backend
node scripts/deploySkinsContract.js                # dry run (shows balance/owner)
node scripts/deploySkinsContract.js --broadcast    # deploy a fresh WONsSkins

node scripts/resetSkinCatalog.js                          # dry-run plan
node scripts/resetSkinCatalog.js --wipe --onchain --write # delete + createSkin + save docs
```

`resetSkinCatalog.js` wipes the numeric `skins/<id>` docs, then for each id in
combo order calls `createSkin` (owner-only) and writes the matching doc. It
aborts loudly if the contract is not fresh (`nextSkinId != 1`), because ids
would be offset. Every combo carries its own palette / outline / crown / tier /
price / supply in `skinCombos.json`, and `newDocForCombo()` in `skinIndex.js`
turns that into the Firebase doc for both scripts.

After deploying, update `SKINS_ADDRESS` (backend/Render) and
`VITE_SKINS_CONTRACT_ADDRESS` (frontend/Vercel, then rebuild — Vite inlines it).

## Attachment lists

A skin chooses what the nad wears with a flat list of node names:

```json
"attachments": ["duck", "hair_001"]
```

Rules — identical in Godot and on the web:

- **Exact set.** Listed names are shown, every other attachment is hidden.
- **Missing or empty list = wears nothing.** The default loadout
  (empty list) is spelled out explicitly in
  `SkinApplier.FALLBACK_SHADED/FALLBACK_UNSHADED` and in
  `frontend/src/data/items.json`, never inherited implicitly.
- **Unknown names are ignored** (with a console warning). A skin may reference an
  attachment that only lands in `skin.tscn` later, and an old skin may still
  name a node that was renamed away — neither may break the rest of the skin.
- **Only visibility is toggled, never transforms.** Every attachment keeps the
  transform authored in `godot/scenes/skin.tscn`.

No colours are pinned onto attachments: they keep the colours and textures
they were authored with. The body colour system (palette, outline, crown,
`shader_targets`) is a separate concern and works exactly as before.

The one shading rule attachments do follow is the **unshaded edition**
(`shader = "unshaded"` — every even id and `s-default-unshaded`): it flattens
each attachment mesh — keeping its authored colour and texture — and adds the
same black 1.04 outline pass the body uses, so the flat variant reads as one
look instead of a flat nad wearing lit, outline-less hats. Any other shader
hands the authored material straight back, so toggling never leaves a stale
override. Godot does this in `SkinApplier._apply_attachment_shader`, the web
in the named-attachment effect in `ThreeScene.tsx`.

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
3. Append a combo that uses it to `backend/skinCombos.json`, then run
   `generateSkinsFromCombos.js --write --create-missing` — or let the next mint
   of that id derive it automatically. No game or web code changes.

**A new skin** (e.g. id `0004`, unshaded by parity):

1. Create it via admin/`POST /admin/create-skin`. For a numbered id the
   `attachments` list is filled from the index automatically; pass an explicit
   `attachments` list in `skinConfig` to override.
2. Nothing else. Godot and the web both pick it up from `/api/skins`.

## Verifying changes

```
Godot_v4.7-stable_win64_console.exe --headless --path godot --script res://tools/_test_skin_applier.gd
```

Prints `PASS`/`FAIL` per expectation (attachment visibility, unknown-name
handling, parity, no-transform-touched guarantees, unshaded attachment
flattening + outline restore) and exits non-zero on failure.
