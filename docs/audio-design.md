# Audio design — World of Nads

Status: planning. Nothing here is implemented yet beyond the dashboard music loop.

Goal: one `Audio` autoload that owns every sound in the game, so no scene ever
creates its own `AudioStreamPlayer`. UI is 2D. World sound is spatial (3D) but
selective: your own footsteps/weapon are 2D so they stay punchy, everything that
belongs to *someone else* or to the world is 3D.

---

## 1. What exists today

| Thing | State |
| --- | --- |
| Assets | `godot/assets/audio/lobbysong.mp3` only (2.7 MB) |
| Dashboard music | `LobbyMusic` node in `scenes/dshbord.tscn`, `autoplay`, `-8 dB` |
| Lobby / gameplay / HUD | no audio at all |
| 3D audio | none |
| Settings | no volume controls, no persistence |
| Web unlock | nothing (browser autoplay policy may keep audio silent) |

The 100 MiB pck cap means audio has to earn its bytes. Budget below is ~12 MB.

---

## 2. Decisions

1. **Single autoload `Audio`** (`godot/scripts/audio/audio.gd`), registered in
   `project.godot`. Everything calls `Audio.play("ui_click")` /
   `Audio.play_at("gun_ak_fire", pos)` / `Audio.music("game")`.
2. **2D by default, 3D by exception.** The registry entry says which. Calling
   `play_at()` on a 2D entry just plays it centred, so mis-use degrades instead
   of crashing.
3. **No `AudioStreamPlayer` nodes in scenes**, except continuous emitters that
   must follow a node exactly (vehicle engine, bee, held chicken). Those get an
   `AudioEmitter` helper that registers with `Audio` for voice accounting.
4. **Pooled players.** 8 × `AudioStreamPlayer` (2D) and 24 ×
   `AudioStreamPlayer3D`, created once, reused. No per-shot allocation.
5. **Priority + voice cap + distance cull.** The lobby can hold 100 stress bots;
   without caps their footsteps would melt the audio thread.
6. **Music/ambience are separate from SFX** and crossfade, never restart.
7. **Bus layout**: `Master → Music, Ambience, SFX → (UI, World)`. `Master` gets a
   limiter so a rocket + 6 gunshots on web cannot clip.
8. **Settings** in `user://audio.cfg` (master / music / sfx / ambience + mute),
   applied through `AudioServer.set_bus_volume_db`.
9. **Web unlock**: mute `Master` until first pointer/key event, then unmute. Also
   handled in `play.html` if needed.

---

## 3. Asset spec

### Formats

| Use | Format | Why |
| --- | --- | --- |
| SFX < 0.3 s | WAV, 16-bit, mono, 44.1 kHz | no codec delay, tiny |
| SFX ≥ 0.3 s | OGG Vorbis q4, mono, 44.1 kHz | ~6–20 KB each |
| Loops (engine, slide, smoke, bee, storm) | OGG Vorbis q4, mono, seamless loop | `loop=true` in the import |
| Music | OGG Vorbis q4, stereo, 44.1 kHz, seamless loop | ~1.3 MB per 90 s |
| Ambience | OGG Vorbis q3, stereo, 45–60 s loop | ~0.5 MB each |

Rules:

- **Mono for anything that can be 3D.** Godot's 3D panner folds stereo to mono
  anyway, you just pay double.
- Normalize SFX to about **-18 LUFS short-term**, music to **-14 LUFS**, peaks
  ≤ -1 dBFS. The Master limiter is a safety net, not a mixing tool.
- No long reverb tails on gameplay SFX; the map already has a lot going on.
- Every looping file needs a **seamless** loop (no click, no fade at the seam).
- Variations: 3–4 takes per footstep/impact type, either separate files
  (`_01.._04`) or one `AudioStreamRandomizer`. Files are easier to swap.

### Naming / folders

```
godot/assets/audio/
  music/     mus_menu.ogg  mus_game.ogg  mus_win.ogg  mus_lose.ogg
  ambience/  amb_day.ogg   amb_storm.ogg  amb_wall.ogg
  ui/        ui_click.wav  ui_error.wav   ...
  player/    ft_soft_01.wav  jump.wav  slide_loop.ogg  ...
  combat/    sword_swing_01.wav  bullet_whiz_01.wav  ...
  weapons/   gun_pistol.wav  gun_ak.wav  rpg_fire.wav  ...
  pickups/   power_pickup.wav  chicken_pickup.wav  ...
  vehicles/  car_engine_loop.ogg  car_crash.wav  ...
  world/     monster_roar.ogg  bee_loop.ogg  ...
  voice/     vo_3.ogg  vo_go.ogg  vo_chicken.ogg   (optional announcer)
```

`sfx_` prefix is unnecessary inside these folders; the folder is the category.

---

## 4. Sound inventory

`Space` — `2D` always centred, `3D` positional, `3D+2D` local player gets 2D and
remote players 3D. `T` — tier 1 ships first, tier 2 is polish.
`Var` — number of alternates to source.

### 4.1 UI / UX (`ui_`)

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ui_click` | any button press | 2D | no | 0.08 | 2 | 1 | soft click, never harsh |
| `ui_back` | back / close button | 2D | no | 0.10 | 1 | 1 | lower pitch than click |
| `ui_tab` | dashboard tab change | 2D | no | 0.12 | 1 | 1 | short whoosh + tick |
| `ui_hover` | card / tab hover | 2D | no | 0.05 | 1 | 2 | default off, web only |
| `ui_open` | panel / modal in | 2D | no | 0.18 | 1 | 1 | airy swell |
| `ui_close` | panel / modal out | 2D | no | 0.15 | 1 | 1 | reverse of open |
| `ui_locked` | locked skin / not owned | 2D | no | 0.20 | 1 | 1 | dull thud + rattle |
| `ui_error` | failed action / invalid | 2D | no | 0.25 | 1 | 1 | two-note descend |
| `ui_confirm` | generic success | 2D | no | 0.30 | 1 | 1 | bright two-note rise |
| `ui_purchase` | buy / mint confirm | 2D | no | 0.60 | 1 | 1 | coin/cash sparkle |
| `ui_purchase_fail` | buy / mint rejected | 2D | no | 0.35 | 1 | 1 | buzz + error |
| `ui_equip` | equip skin | 2D | no | 0.35 | 1 | 1 | cloth flap + snap |
| `ui_mint_start` | mint submitted | 2D | no | 1.2 | 1 | 1 | rising charge, can loop |
| `ui_mint_done` | mint confirmed on chain | 2D | no | 0.9 | 1 | 1 | chime + chain confirm |
| `ui_mint_fail` | mint reverted / timeout | 2D | no | 0.6 | 1 | 1 | error + power down |
| `ui_toast` | event feed row appears | 2D | no | 0.10 | 1 | 1 | quiet, fires a lot |
| `ui_chat` | chat message | 2D | no | 0.08 | 1 | 2 | quieter than toast |
| `ui_count_tick` | 3 / 2 / 1 | 2D | no | 0.16 | 1 | 1 | pitch up per tick in code |
| `ui_count_go` | match start | 2D | no | 0.7 | 1 | 1 | horn / riser, no VO needed |
| `ui_match_found` | queue accepted | 2D | no | 1.4 | 1 | 1 | big, this is the hook |
| `ui_queue_join` | joined queue | 2D | no | 0.3 | 1 | 2 | |
| `ui_queue_cancel` | left queue | 2D | no | 0.25 | 1 | 2 | |
| `ui_card_select` | match card selected | 2D | no | 0.15 | 1 | 1 | |
| `ui_card_hover` | match card hover | 2D | no | 0.06 | 1 | 2 | |
| `ui_coin_tick` | MON / XP counter rolls | 2D | no | 0.05 | 1 | 2 | throttled to ~12/s |
| `ui_level_up` | level up flash | 2D | no | 1.6 | 1 | 1 | fanfare, ducks music |
| `ui_reconnect` | connection dropped, retrying | 2D | no | 0.6 | 1 | 1 | |
| `ui_offline` | gave up / offline | 2D | no | 0.9 | 1 | 1 | |

### 4.2 Music and ambience

| ID | Trigger | Space | Loop | Len | T | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `mus_menu` | dashboard (reuse `lobbysong.mp3`) | 2D | yes | 2–3 min | 1 | already exists, keep as-is |
| `mus_game` | lobby → gameplay | 2D | yes | 90–120 s | 1 | tense, percussive, leaves room for SFX |
| `mus_final` | last 30 s / final chicken push | 2D | yes | 30–45 s | 2 | or a layer over `mus_game` |
| `mus_win` | round won | 2D | no | 4–6 s | 1 | stinger, then silence |
| `mus_lose` | round lost | 2D | no | 4–6 s | 1 | stinger, subdued |
| `amb_day` | map bed | 2D | yes | 45–60 s | 1 | wind, distant traffic, birds |
| `amb_storm` | player outside the zone | 2D | yes | 30 s | 1 | muffled roar, crossfade 1.5 s |
| `amb_wall` | near storm wall | 3D | yes | 15–20 s | 1 | electrical hum, per-wall emitter |
| `amb_lobby` | lobby crowd | 2D | yes | 30 s | 2 | very quiet, ducks under UI |
| `amb_gust` | random wind gust | 2D | no | 3–5 s | 2 | randomised every 20–40 s |
| `amb_thunder` | random, storm only | 2D | no | 2–4 s | 2 | |

### 4.3 Player movement (`ft_`, `jump`, `slide`, `climb`)

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ft_soft_01..04` | footstep, grass/dirt | 3D+2D | no | 0.15 | 4 | 1 | stride-locked in code |
| `ft_hard_01..04` | footstep, concrete/metal | 3D+2D | no | 0.18 | 4 | 1 | surface chosen by raycast material |
| `ft_water_01..02` | puddle | 3D+2D | no | 0.2 | 2 | 2 | |
| `land_soft` | landing, small fall | 3D+2D | no | 0.2 | 2 | 1 | |
| `land_hard` | landing, big fall | 3D+2D | no | 0.35 | 2 | 1 | dust/impact |
| `jump` | "Jump" action | 3D+2D | no | 0.25 | 2 | 1 | cloth + effort breath |
| `slide_start` | "Attack" while sprinting | 3D+2D | no | 0.25 | 1 | 1 | gravel scuff |
| `slide_loop` | while sliding | 3D+2D | yes | 1.0 | 1 | 1 | pitch follows speed |
| `slide_end` | slide stops | 3D+2D | no | 0.2 | 1 | 1 | |
| `climb_start` | begin climb | 3D+2D | no | 0.2 | 1 | 1 | grab + grunt |
| `climb_loop` | while climbing | 3D+2D | yes | 1.0 | 1 | 1 | effort breathing |
| `climb_end` | climb ends | 3D+2D | no | 0.2 | 1 | 1 | |
| `breath_exhausted` | stamina hits 0 | 2D | no | 0.9 | 1 | 1 | local only, heavy pant |
| `breath_recovered` | stamina refilled | 2D | no | 0.6 | 1 | 2 | local only |
| `leap_whoosh` | using LEAP | 3D+2D | no | 0.6 | 1 | 1 | |
| `leap_land` | LEAP landing | 3D | no | 0.9 | 1 | 1 | impact + shockwave |

### 4.4 Weapons and combat

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `sword_swing_01..03` | SWORD action | 3D+2D | no | 0.3 | 3 | 1 | whoosh |
| `sword_hit_flesh` | SWORD connects | 3D | no | 0.25 | 2 | 1 | |
| `sword_hit_world` | SWORD hits prop | 3D | no | 0.25 | 2 | 1 | metal clang |
| `knife_swing_01..03` | KNIFE action | 3D+2D | no | 0.22 | 3 | 1 | shorter, snappier |
| `knife_hit_flesh` | KNIFE connects | 3D | no | 0.2 | 2 | 1 | |
| `knife_hit_world` | KNIFE hits prop | 3D | no | 0.2 | 2 | 1 | |
| `gun_pistol_01..02` | GLOCK fire | 3D+2D | no | 0.5 | 2 | 1 | tail cut under 0.6 s |
| `gun_pistol_dry` | GLOCK out of charges | 2D | no | 0.1 | 1 | 1 | click |
| `gun_ak_01..02` | AK47 fire | 3D+2D | no | 0.45 | 2 | 1 | one per bullet, pitch jitter |
| `gun_ak_dry` | AK47 empty | 2D | no | 0.1 | 1 | 1 | |
| `rpg_fire` | RPG fire | 3D+2D | no | 0.9 | 1 | 1 | launch + backblast |
| `rocket_loop` | rocket in flight | 3D | yes | 0.8 | 1 | 1 | |
| `rocket_boom` | rocket impact | 3D | no | 2.2 | 2 | 1 | the one sound that can be huge |
| `boom_debris` | after a big explosion | 3D | no | 1.5 | 2 | 2 | |
| `bullet_whiz_01..03` | bullet passes near you | 3D | no | 0.3 | 3 | 1 | only when within 2–3 m |
| `impact_concrete` | bullet hits world | 3D | no | 0.2 | 3 | 1 | |
| `impact_metal` | bullet hits metal | 3D | no | 0.25 | 2 | 1 | |
| `impact_wood` | bullet hits wood | 3D | no | 0.2 | 2 | 1 | |
| `impact_flesh` | bullet hits a player | 3D | no | 0.2 | 2 | 1 | |
| `hitmarker` | your shot connected | 2D | no | 0.08 | 1 | 1 | tiny, high, never annoying |
| `kill_confirm` | you eliminated someone | 2D | no | 0.5 | 1 | 1 | satisfying, plays once |
| `weapon_pickup_melee` | grab sword/knife | 2D | no | 0.3 | 1 | 1 | |
| `weapon_pickup_gun` | grab glock/ak | 2D | no | 0.3 | 1 | 1 | mag slap |
| `weapon_pickup_heavy` | grab RPG | 2D | no | 0.4 | 1 | 1 | heavy clunk |
| `weapon_stow` | weapon back to back slot | 2D | no | 0.2 | 1 | 2 | |
| `weapon_spawn` | pickup respawns | 3D | no | 0.6 | 1 | 2 | shimmer, quiet |

### 4.5 Power-ups and objectives

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `power_pickup` | grab any power-up | 2D | no | 0.4 | 1 | 1 | |
| `power_rush` | RUSH activated | 2D | no | 0.9 | 1 | 1 | rising whoosh + heartbeat |
| `power_twin` | TWIN activated | 2D | no | 0.7 | 1 | 1 | digital clone blip |
| `power_twin_pop` | decoy disappears | 3D | no | 0.3 | 1 | 1 | |
| `power_smoke_pop` | SMOG thrown | 3D | no | 0.5 | 1 | 1 | canister pop |
| `power_smoke_loop` | smoke cloud active | 3D | yes | 2.0 | 1 | 1 | hiss, cull > 25 m |
| `power_leap_ready` | LEAP granted | 2D | no | 0.6 | 1 | 1 | |
| `power_expire` | timed power-up ends | 2D | no | 0.3 | 1 | 2 | soft down-blip |
| `chicken_pickup` | grab the chicken | 3D+2D | no | 0.6 | 2 | 1 | comedic squawk |
| `chicken_drop` | drop / knocked out | 3D | no | 0.4 | 1 | 1 | |
| `chicken_held` | while you carry it | 2D | yes | 2.0 | 1 | 1 | panicked clucking, low |
| `chicken_tick` | last 10 s of the 60 s | 2D | no | 0.12 | 1 | 1 | once per second, pitch rises |
| `chicken_win` | 60 s reached | 2D | no | 3.0 | 1 | 1 | fanfare + cluck |
| `lootbox_pickup` | grab lootbox | 3D+2D | no | 0.5 | 1 | 1 | coin rattle |
| `lootbox_drop` | drop lootbox | 3D | no | 0.4 | 1 | 1 | |
| `lootbox_held` | carrying lootbox | 2D | yes | 2.0 | 1 | 2 | quiet rattle |
| `objective_steal` | someone takes the objective from you | 2D | no | 0.6 | 1 | 1 | alert sting |

### 4.6 Damage, death, respawn, storm

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `hurt_light` | damage < 25 | 2D | no | 0.35 | 2 | 1 | grunt + thud |
| `hurt_heavy` | damage ≥ 25 | 2D | no | 0.5 | 2 | 1 | bigger, adds a ring |
| `death` | local player dies | 2D | no | 1.2 | 1 | 1 | dissolve whoosh |
| `death_remote` | another player dies nearby | 3D | no | 1.0 | 1 | 2 | |
| `respawn` | respawn / spawn-in | 2D | no | 0.8 | 1 | 1 | shimmer + intake |
| `health_low` | HP < 25 | 2D | yes | 1.5 | 1 | 1 | heartbeat, stops on heal/death |
| `storm_hurt` | storm damage tick | 2D | no | 0.3 | 2 | 1 | throttled to 1/s |
| `heal` | health pickup | 2D | no | 0.5 | 1 | 2 | |

### 4.7 Vehicles

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `car_start` | `CarController.ride()` | 3D | no | 0.6 | 1 | 1 | ignition |
| `car_engine` | while driving | 3D | yes | 2–3 s | 1 | 1 | `pitch_scale` 0.8→1.5 by speed |
| `car_stop` | `exit_ride()` | 3D | no | 0.4 | 1 | 1 | |
| `car_skid` | drifting / handbrake | 3D | yes | 1.5 | 1 | 1 | volume by lateral slip |
| `car_impact_soft` | low-speed bump | 3D | no | 0.3 | 3 | 1 | |
| `car_impact_hard` | high-speed hit | 3D | no | 0.6 | 2 | 1 | |
| `car_crash` | player hit by vehicle | 3D | no | 0.9 | 1 | 1 | metal + body |
| `car_horn` | horn input (if added) | 3D | no | 0.6 | 1 | 2 | |
| `car_bump` | suspension bottom-out | 3D | no | 0.15 | 2 | 2 | |
| `car_enter` | enter vehicle | 2D | no | 0.3 | 1 | 1 | door |
| `car_exit` | leave vehicle | 2D | no | 0.3 | 1 | 1 | door |

### 4.8 World, NPCs, props

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `monster_roar` | monster idle, every 20–35 s | 3D | no | 2.5 | 2 | 1 | cull > 60 m |
| `monster_step` | monster walk cycle | 3D | no | 0.4 | 2 | 1 | heavy, low |
| `monster_attack` | monster swipe | 3D | no | 0.8 | 1 | 1 | |
| `monster_death` | monster dies (if killable) | 3D | no | 1.5 | 1 | 2 | |
| `bee_loop` | bee/prop hive proximity | 3D | yes | 2.0 | 1 | 1 | cull > 12 m, volume by distance |
| `prop_break_wood` | destructible prop | 3D | no | 0.6 | 3 | 2 | |
| `prop_break_glass` | destructible prop | 3D | no | 0.8 | 2 | 2 | |
| `prop_break_metal` | destructible prop | 3D | no | 0.7 | 2 | 2 | |
| `pickup_shimmer` | power-up idles near you | 3D | no | 0.8 | 1 | 2 | throttled, > 8 m skip |
| `fire_loop` | burning prop | 3D | yes | 2.0 | 1 | 2 | |

### 4.9 Network / social

| ID | Trigger | Space | Loop | Len | Var | T | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `player_join` | someone joins the room | 2D | no | 0.4 | 1 | 1 | pairs with the feed toast |
| `player_leave` | someone leaves | 2D | no | 0.35 | 1 | 1 | |
| `reconnect_ok` | socket restored | 2D | no | 0.6 | 1 | 1 | |
| `reconnect_fail` | giving up | 2D | no | 0.9 | 1 | 1 | |
| `emote_battlecry` | battlecry emote | 3D | no | 1.2 | 3 | 2 | character shout |

Optional announcer (VO) layer, if wanted later: `vo_3`, `vo_2`, `vo_1`,
`vo_go`, `vo_chicken_taken`, `vo_chicken_dropped`, `vo_win`, `vo_lose`. These
cost voice-recording time, so they are deliberately out of tier 1.

**Totals:** ~118 ids, ~150 files with variations. Tier 1 ≈ 95 ids.

---

## 5. Architecture

### 5.1 Files

```
godot/scripts/audio/audio.gd          # autoload "Audio"
godot/scripts/audio/sound_library.gd  # id -> SoundDef dictionary
godot/scripts/audio/audio_emitter.gd  # follows a Node3D (engine, bee, chicken)
godot/scripts/audio/audio_settings.gd # user://audio.cfg
godot/default_bus_layout.tres         # Master / Music / Ambience / SFX / UI / World
```

### 5.2 Sound registry

```gdscript
class SoundDef:
    var path: String          # res://assets/audio/...
    var bus: StringName = &"SFX"
    var space: int            # SPACE_2D | SPACE_3D | SPACE_BOTH
    var volume_db: float = 0.0
    var pitch_min: float = 1.0
    var pitch_max: float = 1.0
    var max_polyphony: int = 3      # per id, global
    var priority: int = 2           # 0 ambient .. 5 alert
    var min_interval_ms: int = 0    # dedupe identical retriggers
    var max_distance: float = 45.0  # 3D only
    var unit_size: float = 9.0      # 3D only
    var cull_distance: float = 45.0 # skip creating the voice at all
    var loop: bool = false
```

Registry is a `const` dictionary in `sound_library.gd`, so a typo in an id is a
parse-time error and missing files are caught by a single loop in `_ready()`
(push a warning with the id).

### 5.3 API

```gdscript
Audio.play(id, opts := {})                     # 2D / UI / music-less SFX
Audio.play_at(id, position, opts := {})        # 3D one-shot
Audio.play_on(id, node3d, opts := {})          # 3D loop that follows a node
Audio.music(id, fade := 1.5)
Audio.ambience(id, fade := 2.0)
Audio.set_bus_volume(bus, db)
Audio.set_muted(bool)
Audio.duck(bus, db, seconds := 0.25)
```

`opts`: `{volume_db, pitch, pitch_jitter, bus, fade, attach_to}`. Internal
helpers pick a free pooled player, set `stream`, `bus`, `volume_db`, `pitch_scale`,
`max_distance`, `unit_size`, `global_position`, then `play()`. On `finished`,
the player returns to the pool (`_free_2d` / `_free_3d` arrays).

### 5.4 Voice budget

| Group | 2D | 3D | Cull | Notes |
| --- | --- | --- | --- | --- |
| UI | 6 | – | – | never culled, never ducked |
| Own player | 4 | – | – | footsteps, weapons, breaths |
| Remote players | – | 10 | 45 m | footsteps cull at 25 m |
| Weapons / impacts | – | 12 | 60 m | min 30 ms per id |
| Ambience / loops | – | 4 | 30 m | bee, smoke, fire, engine |
| Objective | 2 | – | – | chicken/lootbox alerts always audible |

Budget: 12 × 2D + 24 × 3D. When full, steal the **lowest priority, then
farthest, then oldest**. Loops registered through `play_on` are excluded from
stealing while active (they own their emitter node).

Lobby special case: up to `lobby_stress_agent_count` bots. In lobby mode,
`Audio` switches to `max_3d_voices = 8`, footstep cull 14 m, and no remote
weapon sounds beyond 20 m. Otherwise 100 bots = 100 footstep streams.

### 5.5 Bus and mix

```
Master (limiter -1 dBFS, ceiling)
 ├── Music      (-6 dB default, ducked -8 dB on win/lose/level-up)
 ├── Ambience   (-10 dB, crossfaded)
 ├── SFX        (-3 dB)
 │    ├── UI    (0 dB, never ducked)
 │    └── World (0 dB, 3D players)
```

- Pause: `Music` + `Ambience` duck to -14 dB, SFX muted except UI.
- Low health (< 25): optional `AudioEffectLowPassFilter` on `SFX` at 900 Hz,
  disabled on heal/death. Off by default; test before shipping.
- Death: duck Music to -10 dB for 1 s under `death`.
- Storm outside: `amb_day` -8 dB, `amb_storm` 0 dB, 1.5 s crossfade.

### 5.6 Settings

`user://audio.cfg`:

```ini
[audio]
master_db=0.0
music_db=0.0
sfx_db=0.0
ambience_db=0.0
muted=false
```

Applied on boot before the first frame so the menu music never blasts at full
volume. Add three sliders (Master / Music / SFX) to the dashboard settings
panel; Ambience follows SFX if there is no fourth slider.

### 5.7 Web

- `Audio` mutes `Master` in `_ready()` when `OS.has_feature("web")`, then
  unmutes on the first `InputEventMouseButton` / `InputEventKey` /
  `InputEventScreenTouch` (one-shot connection on the root viewport).
- Never autoplay music before the unlock; queue the requested track and start
  it on unlock.
- Keep BGM at OGG; the web build streams it, so RAM stays flat.

---

## 6. Hook map (implementation checklist)

| File | Function / signal | Sounds |
| --- | --- | --- |
| `scripts/screens/dshbord.gd` | tab press, card press, `_on_play_pressed`, `_begin_match` | `ui_tab`, `ui_card_*`, `ui_count_*`, `ui_match_found`, `mus_menu` |
| `scripts/screens/dshbord.gd` | purchase / mint / equip handlers | `ui_purchase*`, `ui_mint_*`, `ui_equip`, `ui_error` |
| `scripts/screens/GameOverScreen.gd` | `_apply_result` | `mus_win` / `mus_lose` |
| `scripts/screens/GameOverScreen.gd` | `_play_xp_progression`, `_play_level_up_flash` | `ui_coin_tick`, `ui_level_up` |
| `scripts/home.gd` | `_ready` | `amb_day` preload, music handoff |
| `scripts/lobby.gd` | `_ready`, `match_handoff` | `mus_game`, `amb_lobby` |
| `scripts/player.gd` | `request_jump`, `_start_landing_bob` | `jump`, `land_*` |
| `scripts/player.gd` | `_start_slide`, `_stop_slide` | `slide_*` |
| `scripts/player.gd` | `begin_climb`, `end_climb` | `climb_*` |
| `scripts/player.gd` | stamina empty/recover | `breath_*` |
| `scripts/player.gd` | `_trigger_weapon_fx`, `_fire_bullet` | `sword_*`, `knife_*`, `gun_*`, `rpg_fire` |
| `scripts/player.gd` | `_try_pickup_weapon`, `_clear_held_weapon` | `weapon_pickup_*`, `weapon_stow` |
| `scripts/player.gd` | `_use_held_power_up` | `power_*` |
| `scripts/player.gd` | `take_damage`, `die`, `respawn_at_spawn_point` | `hurt_*`, `death`, `respawn` |
| `scripts/player.gd` | `_update_storm_damage` | `storm_hurt` |
| `scripts/player.gd` | `enter_vehicle`, `exit_vehicle` | `car_enter`, `car_exit` |
| `scripts/weapons/Bullet.gd` | `_on_body_entered` | `impact_*`, `hitmarker` |
| `scripts/pickups/LocalPickup.gd` | `pick_up`, `drop`, `consume_and_respawn` | `chicken_*`, `lootbox_*`, `power_pickup` |
| `scripts/pickups/LocalPickup2.gd` | `pick_up`, `deplete_and_respawn` | `weapon_pickup_*`, `weapon_spawn` |
| `scripts/vehicle/CarController.gd` | `ride`, `exit_ride`, `_physics_process` | `car_*` |
| `scripts/map/StormEye.gd` | `set_storm_radius`, outside flags | `amb_storm`, `amb_wall` |
| `scripts/player/PlayerManager.gd` | `_handle_chicken_state_event`, `_handle_lootbox_state_event` | `objective_steal`, `chicken_*` |
| `scripts/player/PlayerManager.gd` | `_emit_player_event`, `_show_local_event` | `player_join`, `player_leave`, `ui_toast` |
| `scripts/player/PlayerManager.gd` | `_on_reconnect_success`, `_give_up_reconnection` | `reconnect_ok`, `reconnect_fail` |
| `scenes/props/monster.gd` | attack / idle | `monster_*` |
| `scenes/bee.gd` | hover | `bee_loop` |
| `scripts/ui/buttons.gd` | `_ready` connections | `ui_click` (global default) |

---

## 7. Phases

**Phase 0 — skeleton (no assets needed)**
Bus layout, `Audio` autoload, registry with 3 test ids, pooling, settings file,
web unlock, `F3` debug overlay (active voices, bus peaks, last 10 ids).

**Phase 1 — UX layer**
All `ui_*` + `mus_menu` + `mus_game` + `amb_day`. Wire dashboard, lobby,
game-over. This is the biggest perceived-quality jump and needs zero 3D work.

**Phase 2 — own player**
Footsteps, jump/land, slide, climb, stamina, weapons, hit marker, hurt/death,
respawn. Local player 2D only. This is where the game starts feeling real.

**Phase 3 — world**
3D pool + culling, remote players, impacts, pickups, chicken/lootbox, storm,
monster, bee, vehicles.

**Phase 4 — mix**
Ducking, low-health filter, concurrency tuning on the 100-bot lobby, pause
behaviour, mobile speakers check.

**Phase 5 — polish**
Announcer VO if wanted, destructible props, extra ambience, final-loop layer.

---

## 8. QA checklist

- Web: first click unlocks audio; no console warning about blocked AudioContext.
- 100-bot lobby: audio thread stable, voice count ≤ 12, no footstep machine-gun.
- 4 players + 6 bots in gameplay: maximum 24 3D voices, no stealing of objective
  sounds.
- Rocket + 3 AKs + chicken win on the same frame: Master limiter holds, no clip.
- Pause menu silences gameplay but keeps UI clicks.
- Volume sliders persist across restarts and apply before music starts.
- Every registry id resolves to a file; missing ids log once with the id.
- No `AudioStreamPlayer` nodes left in gameplay scenes (grep check).
- pck growth ≤ 12 MB.

---

## 9. Open questions

1. Where are the sounds you already have? Drop them in
   `godot/assets/audio/_incoming/` and I will map, rename and import them, or
   tell me the folder and I will work from there.
2. Do you want a dedicated gameplay music loop, or reuse `lobbysong.mp3` for the
   lobby and only make one new `mus_game`?
3. Announcer VO ("3, 2, 1, GO", "chicken taken") — yes/no? It changes the
   sourcing list by ~8 recordings.
4. Any reference game for the mix (e.g. Fall Guys bright and cartoonish vs.
   Stumble Guys arcade-loud)?
