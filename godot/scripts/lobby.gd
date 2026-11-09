extends Node3D

# === PLAYER & NPC EXPORTS ===
@export var local_player_scene: PackedScene
@export var camera_node: NodePath

# 👉 NEW: spawn point reference
@export var spawn_point: Node3D
@export var spawn_lobby_stress_agents: bool = false
@export var lobby_stress_agent_count: int = 100


var local_player
var npcs := []
var _stress_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_recovery_ms: int = 0

# === LOBBY TEST BOTS ===
# The bots are built the way PlayerManager builds another player's avatar in a
# match: the skin scene's visuals are re-parented under a RemotePlayer node with
# every collision shape dropped. The lobby therefore shows the same avatar, name
# label and six-state animation machine a real remote player has, which makes it
# usable for testing remote-player work without a second client.
const REMOTE_PLAYER_SCRIPT: GDScript = preload("res://scripts/player/RemotePlayer.gd")
const BOT_GRAVITY: float = 22.0
const BOT_JUMP_HEIGHT: float = 1.5

# One orbit per bot. A RemotePlayer has no _process of its own - in a match
# PlayerManager feeds it positions and animation states from world-state packets
# - so the lobby plays that part: it walks each bot around its own circle, lets
# it hop and stand still, and drives the same animation states a remote gets
# from the server.
class BotMotion:
	var rig: CharacterBody3D = null
	var home: Vector3 = Vector3.ZERO
	var radius: float = 1.5
	var speed: float = 1.0
	var angle: float = 0.0
	var direction: float = 1.0
	var wobble: float = 0.5
	var wobble_phase: float = 0.0
	var jump_min: float = 1.0
	var jump_max: float = 3.0
	var jump_timer: float = 1.0
	## Counts down to the next stand-still, which then runs in pause_left.
	var pause_timer: float = 0.0
	var pause_left: float = 0.0
	## Simulation LOD (Hitman-style crowd budget): accumulate dt and step less
	## often when far from the viewer. Keeps near bots smooth, far bots cheap.
	var sim_accum: float = 0.0
	var lod: int = 0 # 0=near, 1=mid, 2=far, 3=culled
	var dist_sq: float = INF
	## Orbit advanced even when dormant so teleported bots don't freeze in time.
	var orbit_accum: float = 0.0
	# Hive-mind goal (assigned centrally at low frequency). Overrides orbit when set.
	var goal_node: Node3D = null
	var goal_kind: String = "" # "chicken","lootbox","powerup","weapon"
	var action_cooldown: float = 0.0
	var held_item: Node = null
	var held_kind: String = ""

var _bot_motions: Array[BotMotion] = []
var _bot_lod_timer: float = 0.0
var _bot_budget_timer: float = 0.0
var _bot_hive_timer: float = 0.0
var _bot_sim_set: Dictionary = {} # motion index -> true (full-physics budget)
var _bot_lod_cursor: int = 0
var _stress_spawn_pending: int = 0
var _stress_spawn_base: Vector3 = Vector3.ZERO
var _stress_spawn_picks: Array[String] = []

const CLIMBABLE_ACTOR_SCRIPT := preload("res://scripts/environment/ClimbableActor.gd")

const BOT_HIVE_INTERVAL: float = 0.75 # one "brain" tick for all bots
const BOT_GOAL_REACH: float = 2.0

# Distance tiers (meters): near=full sim+anim, mid=throttled sim/anim LOD,
# far=very low sim rate + mesh/anim disabled. Tuned for low-end browser crowds.
const BOT_LOD_NEAR: float = 18.0
const BOT_LOD_MID: float = 40.0
const BOT_LOD_FAR: float = 70.0
const BOT_LOD_CULL: float = 110.0
const BOT_LOD_INTERVAL: float = 0.25
const BOT_LOD_SLICE: int = 256 # LOD distance refresh batch per interval tick
const BOT_BUDGET_INTERVAL: float = 0.35
const BOT_FULL_SIM_BUDGET: int = 120 # only these get CharacterBody move_and_slide
const BOT_VISUAL_BUDGET: int = 280 # beyond this (by distance) mesh stays hidden
const BOT_SPAWN_PER_FRAME: int = 40
const BOT_SIM_STEP_NEAR: float = 0.0 # every physics tick
const BOT_SIM_STEP_MID: float = 1.0 / 12.0
const BOT_SIM_STEP_FAR: float = 1.0 / 4.0
const BOT_SIM_STEP_CULL: float = 1.0 / 2.0

# Hand-off from dshbord.gd: READY counts down on the dashboard and then sends the
# player here with the match they queued and the nad they picked, written straight
# onto these exports by SceneTransition.change_scene() so the lobby can read them
# without hunting them down again. Empty means "resolve it yourself", which is what
# the frontend's /play?match=...&skin=... entry relies on.
@export var selected_match_id: String = ""
@export var selected_skin_id: String = ""

const DEFAULT_SKIN_NAME := "s-default"
const SKIN_SCENE: PackedScene = preload("res://scenes/skin.tscn")
const API_BASE: String = "https://worldofnads.onrender.com"
const SKIN_NAME_ALIASES := {
	"s-default": "s-default",
	"s-default-unshaded": "s-default-unshaded",
}

static var _skin_applier: SkinApplier = SkinApplier.new()
var _skin_cycle_index: int = -1

func _input(event: InputEvent):
	if event is InputEventKey and event.keycode == KEY_T and event.pressed and not event.echo:
		_cycle_skin()

func _cycle_skin() -> void:
	var keys := SkinApplier._api_cache.keys()
	if keys.is_empty():
		print("[CYCLE] No cached skins to cycle")
		return
	_skin_cycle_index = (_skin_cycle_index + 1) % keys.size()
	var chosen := str(keys[_skin_cycle_index])
	print("[CYCLE] Applying skin #%d: '%s'" % [_skin_cycle_index, chosen])
	if local_player:
		_skin_applier.apply_skin(local_player, chosen)

func _ready():
	_stress_rng.randomize()
	_pre_seed_from_session_storage()
	_fetch_skin_data()
	_spawn_local_player()
	_spawn_lobby_stress_agents()
	_assign_camera()

func _physics_process(delta: float) -> void:
	_tick_stress_spawn()
	_tick_hive_mind(delta)
	_drive_lobby_bots(delta)

func _process(_delta: float) -> void:
	_check_map_recovery()

func _check_map_recovery() -> void:
	# Respawn at lobby spawn point if player falls off map
	if local_player == null:
		return
	if local_player.global_position.y >= -5.0:
		return
	
	# Cooldown to prevent rapid re-triggering
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_recovery_ms < 750:
		return
	_last_recovery_ms = now_ms
	
	var spawn_pos: Vector3
	if spawn_point:
		spawn_pos = spawn_point.global_position
	else:
		spawn_pos = global_position
	
	local_player.global_position = spawn_pos
	local_player.velocity = Vector3.ZERO if local_player.has_method("get_velocity") else Vector3.ZERO
	print("Lobby: Player fell off map, respawned at ", spawn_pos)

func _fetch_skin_data() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_skin_data_fetched.bind(http))
	http.request("%s/api/skins" % API_BASE)

func _on_skin_data_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("SkinApplier (lobby): API fetch failed (%d %d), using bundled fallback." % [result, response_code])
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.get("ok") == true:
		var skins_array = parsed.get("skins")
		if skins_array is Array:
			SkinApplier.seed_from_api(skins_array)
			print("SkinApplier (lobby): Cached %d skins from API." % skins_array.size())
	if local_player:
		_skin_applier.apply_skin(local_player, _resolve_local_skin_name())
	# Bots spawned before this answer wore a bundled alias; now that the real
	# skin list is in, dress them from it.
	_redress_fallback_bots()

func _spawn_local_player():
	var skin_name := _resolve_local_skin_name()

	local_player = SKIN_SCENE.instantiate()
	_skin_applier.apply_skin(local_player, skin_name)
	add_child(local_player)

	local_player.is_local = true
	local_player.add_to_group("local_player")
	local_player.player_id = "PLAYER_1"
	local_player.root = self  # Set root so death respawn works
	print("Local player skin:", skin_name)

	if spawn_point:
		local_player.global_transform = spawn_point.global_transform
	else:
		local_player.global_position = global_position


func _assign_camera():

	if not camera_node:
		return

	var cam = get_node(camera_node)

	if cam and local_player:
		local_player.camera = cam

func get_local_spawn_position() -> Vector3:
	if spawn_point:
		return spawn_point.global_position
	return global_position

func _spawn_lobby_stress_agents() -> void:
	if not spawn_lobby_stress_agents or lobby_stress_agent_count <= 0:
		return
	if spawn_point == null:
		return
	_stress_spawn_base = spawn_point.global_position
	_stress_spawn_picks = _bot_skin_picks(lobby_stress_agent_count)
	_stress_spawn_pending = lobby_stress_agent_count
	print("[LOBBY] Spawning %d stress bots in batches of %d..." % [lobby_stress_agent_count, BOT_SPAWN_PER_FRAME])


func _tick_stress_spawn() -> void:
	if _stress_spawn_pending <= 0:
		return
	var total := lobby_stress_agent_count
	var budget := mini(BOT_SPAWN_PER_FRAME, _stress_spawn_pending)
	for _k in range(budget):
		var i := total - _stress_spawn_pending
		_spawn_one_stress_bot(i, total)
		_stress_spawn_pending -= 1
	if _stress_spawn_pending <= 0:
		print("[LOBBY] Spawned %d remote-player bots from %d skins." % [npcs.size(), _bot_skin_pool().size()])


func _spawn_one_stress_bot(i: int, total: int) -> void:
	var skin_name: String = _stress_spawn_picks[i] if i < _stress_spawn_picks.size() else DEFAULT_SKIN_NAME
	var rig := _instantiate_bot_rig(skin_name)
	rig.name = "Bot%04d" % (i + 1)
	add_child(rig)
	var bot: Node3D = rig.get_node("Avatar")
	npcs.append(bot)

	var ring_index := int(floor(sqrt(float(i))))
	var ring_radius := 2.0 + (ring_index * 1.5)
	var ring_angle := (TAU * float(i)) / maxf(1.0, float(total))
	var spawn_offset := Vector3(cos(ring_angle), 0.0, sin(ring_angle)) * ring_radius
	var home_center := _stress_spawn_base + spawn_offset

	bot.is_local = false
	bot.root = self
	bot.player_id = "BOT_%04d" % (i + 1)
	bot.display_name = "BOT %04d" % (i + 1)
	bot.add_to_group("los_target")
	rig.global_position = home_center
	_disable_bot_shadows(rig)

	var motion := BotMotion.new()
	motion.rig = rig
	motion.home = home_center
	motion.radius = _stress_rng.randf_range(0.9, 3.5)
	motion.speed = _stress_rng.randf_range(0.55, 1.6)
	motion.angle = _stress_rng.randf_range(0.0, TAU)
	motion.direction = -1.0 if _stress_rng.randi_range(0, 1) == 0 else 1.0
	motion.wobble = _stress_rng.randf_range(0.2, 1.1)
	motion.wobble_phase = _stress_rng.randf_range(0.0, TAU)
	motion.jump_min = _stress_rng.randf_range(0.8, 2.4)
	motion.jump_max = _stress_rng.randf_range(2.5, 5.5)
	motion.jump_timer = _stress_rng.randf_range(motion.jump_min, motion.jump_max)
	motion.pause_timer = _stress_rng.randf_range(2.0, 8.0)
	_bot_motions.append(motion)
	# Start dormant/cheap; budget + LOD passes will promote nearest.
	_apply_bot_lod(bot, 3)
	rig.visible = false


# PlayerManager turns another player's skin scene into a RemotePlayer node: the
# visuals are re-parented under it and every collider is dropped, because the
# server moves that avatar. A lobby bot has no server, so it keeps a body of its
# own - otherwise the avatar hangs at the spawn point's height instead of
# standing on the floor. The RemotePlayer still owns the look and the animation
# machine, exactly like a remote in a match.
func _instantiate_bot_rig(skin_name: String) -> CharacterBody3D:
	var source := SKIN_SCENE.instantiate()

	var rig := CharacterBody3D.new()
	# Layer 3 (value 4): melee/queries can still find us, but pickups (mask=layer 1)
	# won't be pushed by bots. Layer 1 mask keeps us standing on the world floor.
	rig.collision_layer = 4
	rig.collision_mask = 1
	rig.floor_max_angle = deg_to_rad(50.0)

	var avatar: Node3D = REMOTE_PLAYER_SCRIPT.new()
	avatar.name = "Avatar"
	rig.add_child(avatar)

	# Horde FX: local player can climb on bots (disabled by default; LOD enables near).
	var climb: Area3D = CLIMBABLE_ACTOR_SCRIPT.new()
	climb.name = "ClimbActor"
	climb.monitoring = false
	rig.add_child(climb)
	if climb.has_method("set_climb_enabled"):
		climb.call("set_climb_enabled", false)

	# The character's own capsule: skin.tscn ships it at the right size and
	# height, so the body reuses that shape instead of guessing one.
	var shape := source.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		source.remove_child(shape)
		shape.owner = null
		rig.add_child(shape)

	_strip_physics_nodes(source)
	for child in source.get_children():
		source.remove_child(child)
		child.owner = null
		avatar.add_child(child)
		_own_subtree(child, avatar)
	source.queue_free()

	# Applied after the visuals are re-parented, so the same call also serves a
	# re-dress later on (see _redress_fallback_bots).
	_skin_applier.apply_skin(avatar, skin_name)
	return rig


# SkinApplier walks the player's own children - find_children's `owned` flag
# defaults to true - so every visual has to be owned by the RemotePlayer or
# apply_skin silently skips its meshes. That is how a bot ends up wearing the
# right hat on the scene's default pink body: attachments are looked up by node
# path, body colours by walking the children. PlayerManager dodges this by
# dressing the skin scene before it re-parents it; owning the subtree lets the
# lobby re-dress a bot at any time instead.
func _own_subtree(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_own_subtree(child, owner_node)


func _strip_physics_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Area3D or child is RayCast3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_physics_nodes(child)


# RemotePlayer has no disable_character_shadows() - that lives on player.gd - but
# a lobby full of bots should not add a shadow caster per mesh either.
func _disable_bot_shadows(rig: Node3D) -> void:
	for child in rig.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# The skins the backend actually knows about (GET /api/skins, or the
# sessionStorage pre-seed on web), minus the two bundled default aliases: those
# both paint the generic pink Nad that made every bot look identical. The
# aliases only stand in while the list is still empty, and _redress_fallback_bots()
# swaps them out the moment the real list lands.
func _bot_skin_pool() -> Array[String]:
	var pool: Array[String] = []
	for key in SkinApplier._api_cache.keys():
		var skin_name := str(key)
		if skin_name == DEFAULT_SKIN_NAME or skin_name == "s-default-unshaded":
			continue
		pool.append(skin_name)
	if pool.is_empty():
		for alias in SKIN_NAME_ALIASES.values():
			pool.append(str(alias))
	pool.sort()
	return pool


# One random skin per bot, dealt from a shuffled deck: two bots standing next to
# each other never wear the same skin, and the deck is reshuffled instead of
# repeating the same order when there are more bots than skins.
func _bot_skin_picks(count: int) -> Array[String]:
	var picks: Array[String] = []
	var pool := _bot_skin_pool()
	if pool.is_empty() or count <= 0:
		return picks
	var deck: Array[String] = pool.duplicate()
	for _i in range(count):
		if deck.is_empty():
			deck = pool.duplicate()
		var index := _stress_rng.randi_range(0, deck.size() - 1)
		picks.append(deck[index])
		deck.remove_at(index)
	return picks


# Bots spawned before GET /api/skins answered wear a bundled alias. Once the real
# list is in, re-dress only those bots - a bot that already wears a real skin
# keeps it, so a warm skin cache does not flicker on every refresh.
func _redress_fallback_bots() -> void:
	if npcs.is_empty():
		return
	var pool := _bot_skin_pool()
	if pool.is_empty():
		return
	var picks := _bot_skin_picks(npcs.size())
	for i in range(npcs.size()):
		var bot = npcs[i]
		if not is_instance_valid(bot):
			continue
		var worn := str(bot.get_meta(SkinApplier.APPLIED_SKIN_META, ""))
		if pool.has(worn):
			continue
		_skin_applier.apply_skin(bot, picks[i] if i < picks.size() else DEFAULT_SKIN_NAME)


# --- HIVE MIND (one cheap brain, low frequency) --------------------------
# Assigns goals only to sim-budgeted bots so 2000 agents don't run per-bot AI.
func _tick_hive_mind(delta: float) -> void:
	_bot_hive_timer -= delta
	if _bot_hive_timer > 0.0:
		return
	_bot_hive_timer = BOT_HIVE_INTERVAL
	if _bot_sim_set.is_empty():
		return

	var chicken := _find_pickup_objective("Chicken")
	var lootbox := _find_pickup_objective("LootBox")
	var powerups := _find_available_powerups()
	var weapons := _find_available_weapons()
	var sim_ids: Array = _bot_sim_set.keys()
	# Shuffle a little by rotating start so assignments don't stick statically.
	if sim_ids.size() > 1:
		sim_ids.sort()

	var want_chicken := 3
	var want_lootbox := 3
	for idx in sim_ids:
		var i := int(idx)
		if i < 0 or i >= _bot_motions.size():
			continue
		var motion: BotMotion = _bot_motions[i]
		if motion == null:
			continue
		# Clear invalid/consumed goals/items.
		if motion.goal_node != null and not is_instance_valid(motion.goal_node):
			motion.goal_node = null
			motion.goal_kind = ""
		if motion.held_item != null and not is_instance_valid(motion.held_item):
			motion.held_item = null
			motion.held_kind = ""

		# Holding something: if stolen (objective) or gone, release; else keep.
		if motion.held_kind != "" and motion.held_item != null and is_instance_valid(motion.held_item):
			if motion.held_kind == "objective":
				var avatar = npcs[i] if i < npcs.size() else null
				var it := motion.held_item
				var still_mine: bool = bool(it.get("remote_held")) and (it.get("holder") == avatar)
				if not still_mine:
					motion.held_item = null
					motion.held_kind = ""
					# fall through to get a new goal
				else:
					motion.goal_node = null
					motion.goal_kind = ""
					continue
			else:
				motion.goal_node = null
				motion.goal_kind = ""
				continue

		if chicken != null and want_chicken > 0 and _pickup_grabbable(chicken):
			motion.goal_node = chicken
			motion.goal_kind = "chicken"
			want_chicken -= 1
		elif lootbox != null and want_lootbox > 0 and _pickup_grabbable(lootbox):
			motion.goal_node = lootbox
			motion.goal_kind = "lootbox"
			want_lootbox -= 1
		else:
			# Opportunistic: nearest useful pickup to this bot.
			_assign_opportunistic_goal(motion, powerups, weapons)


func _find_pickup_objective(item_id: String) -> Node3D:
	# Objective items are LocalPickup nodes (CHICKEN/LOOTBOX) in lobby.
	var group := "local_pickup_items"
	for n in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(n):
			continue
		if n.has_method("objective_item_id") and str(n.call("objective_item_id")) == item_id:
			return n as Node3D
		# fallback by name/mode
		if n is Node and (n as Node).name == item_id:
			return n as Node3D
	return null


func _pickup_grabbable(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n.has_method("can_pick_up"):
		return bool(n.call("can_pick_up"))
	return true


func _find_available_powerups() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("local_pickup_items"):
		if out.size() >= 24:
			break
		if not is_instance_valid(n) or not _pickup_grabbable(n):
			continue
		if n.has_method("is_weapon_pickup") and bool(n.call("is_weapon_pickup")):
			continue
		if n.has_method("is_objective_item") and bool(n.call("is_objective_item")):
			continue
		if n.has_method("is_power_up_item") and bool(n.call("is_power_up_item")):
			out.append(n)
	return out


func _find_available_weapons() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("local_weapon_pickups"):
		if out.size() >= 16:
			break
		if is_instance_valid(n) and _pickup_grabbable(n):
			out.append(n)
	return out


func _assign_opportunistic_goal(motion: BotMotion, powerups: Array, weapons: Array) -> void:
	motion.goal_node = null
	motion.goal_kind = ""
	var rig := motion.rig
	if rig == null or not is_instance_valid(rig):
		return
	var best: Node3D = null
	var best_d := 60.0 * 60.0
	var best_kind := ""
	# Prefer weapon if unarmed, else powerup.
	var pool: Array = weapons if motion.held_kind != "weapon" else powerups
	if pool.is_empty():
		pool = powerups if pool == weapons else weapons
	for n in pool:
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var d := rig.global_position.distance_squared_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
			best_kind = "weapon" if n.has_method("is_weapon_pickup") and bool(n.call("is_weapon_pickup")) else "powerup"
	if best != null:
		motion.goal_node = best
		motion.goal_kind = best_kind


# "Hitman-style" crowd at scale (20..2000): fixed full-physics budget, distance
# tiers, and cheap dormant updates for the rest. 2000 full CharacterBody+AnimTree
# bots can't all step every tick in a browser, so only the nearest N get
# move_and_slide; others keep orbit state and teleport at low frequency.
func _drive_lobby_bots(delta: float) -> void:
	if _bot_motions.is_empty():
		return
	var viewer_pos := _bot_viewer_position()
	_bot_budget_timer -= delta
	if _bot_budget_timer <= 0.0:
		_bot_budget_timer = BOT_BUDGET_INTERVAL
		_refresh_bot_budget(viewer_pos)

	var count := mini(npcs.size(), _bot_motions.size())
	for i in range(count):
		var bot = npcs[i]
		if not is_instance_valid(bot):
			continue
		var motion: BotMotion = _bot_motions[i]
		var rig := motion.rig
		if rig == null or not is_instance_valid(rig):
			continue

		if bool(rig.get_meta("combat_dead", false)) or (bot.has_method("is_remote_player") and bot.get("_is_dead") == true):
			rig.velocity = Vector3.ZERO
			if _bot_sim_set.has(i) and rig.is_on_floor() == false:
				rig.velocity.y -= BOT_GRAVITY * minf(delta, 0.1)
				rig.move_and_slide()
			continue

		if _bot_sim_set.has(i):
			_step_bot(bot, motion, rig, delta)
		else:
			_step_bot_dormant(bot, motion, rig, delta)


func _refresh_bot_budget(viewer_pos: Vector3) -> void:
	var count := mini(npcs.size(), _bot_motions.size())
	if count <= 0:
		return
	# Update distances for all (cheap: 2000 dot/subs). Then pick nearest budgets.
	var ranked: Array = []
	ranked.resize(count)
	for i in range(count):
		var rig: CharacterBody3D = _bot_motions[i].rig
		var dsq := INF
		if rig != null and is_instance_valid(rig) and viewer_pos != Vector3.INF:
			dsq = viewer_pos.distance_squared_to(rig.global_position)
		_bot_motions[i].dist_sq = dsq
		ranked[i] = i
	ranked.sort_custom(func(a: int, b: int) -> bool: return _bot_motions[a].dist_sq < _bot_motions[b].dist_sq)

	_bot_sim_set.clear()
	# Scale budgets with crowd size so 2000 stays playable on low-end/browser.
	var sim_budget := BOT_FULL_SIM_BUDGET
	var vis_budget := BOT_VISUAL_BUDGET
	if count > 1200:
		sim_budget = 50
		vis_budget = 120
	elif count > 500:
		sim_budget = 80
		vis_budget = 180
	elif count > 200:
		sim_budget = 100
		vis_budget = 240
	var sim_n := mini(sim_budget, count)
	for r in range(sim_n):
		_bot_sim_set[int(ranked[r])] = true

	for r in range(count):
		var i := int(ranked[r])
		var bot = npcs[i]
		if not is_instance_valid(bot):
			continue
		var motion: BotMotion = _bot_motions[i]
		var dist := sqrt(motion.dist_sq) if motion.dist_sq != INF else INF
		var new_lod := _bot_lod_for_distance(dist)
		var visual := r < vis_budget
		if not visual and new_lod < 3:
			new_lod = 3
		motion.lod = new_lod
		_apply_bot_lod(bot, new_lod, visual)
		# Dormant rigs: stop physics/render cost, keep node for LOS targeting.
		var rig: CharacterBody3D = motion.rig
		if rig != null and is_instance_valid(rig):
			var active := _bot_sim_set.has(i)
			rig.visible = visual
			# Keep active bots off pickup-collision (pickups mask layer 1 only).
			rig.collision_layer = 4 if active else 0
			rig.collision_mask = 1 if active else 0
			# Horde: only near, visible, active bots are climbable (perf).
			var climb = rig.get_node_or_null("ClimbActor")
			if climb != null and climb.has_method("set_climb_enabled"):
				climb.call("set_climb_enabled", visual and active and new_lod <= 1)
			if not active:
				rig.velocity = Vector3.ZERO


func _step_bot_dormant(bot: Node, motion: BotMotion, rig: CharacterBody3D, delta: float) -> void:
	# Advance orbit cheaply and snap position occasionally; no move_and_slide.
	motion.orbit_accum = minf(motion.orbit_accum + delta, 1.0)
	var step := 0.5 if motion.lod >= 3 else 0.25
	if motion.orbit_accum < step:
		return
	var dt := motion.orbit_accum
	motion.orbit_accum = 0.0
	if motion.pause_left > 0.0:
		motion.pause_left -= dt
		if motion.pause_left <= 0.0:
			motion.pause_timer = _stress_rng.randf_range(4.0, 12.0)
	else:
		motion.angle = wrapf(motion.angle + (dt * motion.speed * motion.direction), 0.0, TAU)
		motion.pause_timer -= dt
		if motion.pause_timer <= 0.0:
			motion.pause_left = _stress_rng.randf_range(0.6, 1.8)
	rig.global_position = motion.home + _bot_orbit_offset(motion)
	rig.velocity = Vector3.ZERO


func _bot_viewer_position() -> Vector3:
	if local_player != null and is_instance_valid(local_player):
		return local_player.global_position
	if camera_node != NodePath() and has_node(camera_node):
		var cam := get_node(camera_node) as Node3D
		if cam != null:
			return cam.global_position
	return Vector3.INF


func _bot_lod_for_distance(dist: float) -> int:
	if dist <= BOT_LOD_NEAR:
		return 0
	if dist <= BOT_LOD_MID:
		return 1
	if dist <= BOT_LOD_FAR:
		return 2
	return 3


func _bot_step_dt(lod: int) -> float:
	match lod:
		0:
			return BOT_SIM_STEP_NEAR
		1:
			return BOT_SIM_STEP_MID
		2:
			return BOT_SIM_STEP_FAR
		_:
			return BOT_SIM_STEP_CULL


func _apply_bot_lod(bot: Node, lod: int, visual: bool = true) -> void:
	# Reuse RemotePlayer's LOD switches (animation/mesh) so we don't duplicate logic.
	var anim_on := visual and lod <= 1
	var mesh_on := visual and lod <= 2
	if bot.has_method("set_animation_lod_enabled"):
		bot.call("set_animation_lod_enabled", anim_on)
	if bot.has_method("set_mesh_lod_enabled"):
		bot.call("set_mesh_lod_enabled", mesh_on)
	if not anim_on and bot.has_method("set_animation_state"):
		bot.call("set_animation_state", "idle")
	# Hide name labels on non-visual bots (big draw/text savings at 2000).
	var label = bot.get("name_label")
	if label is Node3D:
		(label as Node3D).visible = visual and lod <= 2


func _step_bot(bot: Node, motion: BotMotion, rig: CharacterBody3D, delta: float) -> void:
	motion.action_cooldown = maxf(0.0, motion.action_cooldown - delta)
	# Held item use (hive-directed, cheap cooldown).
	if motion.held_kind != "" and motion.action_cooldown <= 0.0:
		_bot_use_held(bot, motion)
		return

	# Orbit baseline (always advanced so dormant/goal transitions stay smooth).
	if motion.pause_left > 0.0:
		motion.pause_left -= delta
		if motion.pause_left <= 0.0:
			motion.pause_timer = _stress_rng.randf_range(4.0, 12.0)
	else:
		motion.angle = wrapf(motion.angle + (delta * motion.speed * motion.direction), 0.0, TAU)
		motion.pause_timer -= delta
		if motion.pause_timer <= 0.0:
			motion.pause_left = _stress_rng.randf_range(0.6, 1.8)

	var seek_goal := false
	var target := motion.home + _bot_orbit_offset(motion)
	if motion.held_kind == "" and motion.goal_node != null and is_instance_valid(motion.goal_node):
		if _pickup_grabbable(motion.goal_node):
			target = (motion.goal_node as Node3D).global_position
			seek_goal = true
		else:
			motion.goal_node = null
			motion.goal_kind = ""

	var moving := motion.pause_left <= 0.0 or seek_goal

	if not rig.is_on_floor():
		rig.velocity.y -= BOT_GRAVITY * delta
	else:
		rig.velocity.y = 0.0
		if moving and not seek_goal:
			motion.jump_timer -= delta
			if motion.jump_timer <= 0.0:
				rig.velocity.y = sqrt(2.0 * BOT_GRAVITY * BOT_JUMP_HEIGHT)
				motion.jump_timer = _stress_rng.randf_range(motion.jump_min, motion.jump_max)

	var diff := target - rig.global_position
	diff.y = 0.0
	var speed := (motion.radius * motion.speed) * (1.7 if seek_goal else 1.0)
	if seek_goal and diff.length() <= BOT_GOAL_REACH:
		rig.velocity.x = 0.0
		rig.velocity.z = 0.0
		_bot_try_pickup_goal(bot, motion)
	else:
		if moving and diff.length() > 0.001:
			var dir := diff.normalized()
			var desired_speed := clampf(diff.length() / maxf(delta, 0.001), 0.0, maxf(speed * 2.0, 5.5))
			rig.velocity.x = dir.x * desired_speed
			rig.velocity.z = dir.z * desired_speed
			bot.rotation.y = atan2(dir.x, dir.z)
		else:
			rig.velocity.x = 0.0
			rig.velocity.z = 0.0

	rig.move_and_slide()

	if rig.global_position.y < -15.0:
		rig.global_position = motion.home
		rig.velocity = Vector3.ZERO

	if motion.lod <= 1 and bot.has_method("set_animation_state"):
		bot.set_animation_state(_bot_animation_state(motion, moving or seek_goal))


func _bot_try_pickup_goal(bot: Node, motion: BotMotion) -> void:
	var item := motion.goal_node
	if item == null or not is_instance_valid(item) or not _pickup_grabbable(item):
		motion.goal_node = null
		return
	# Use avatar as holder so attach paths (Back/offset) resolve on the skin rig.
	var holder: Node3D = bot as Node3D
	if item.has_method("is_objective_item") and bool(item.call("is_objective_item")):
		# Mark as held by another actor (remote-held) so the local player can
		# still snatch/steal objectives, same as stealing from a remote player.
		if item.has_method("set_remote_held"):
			item.call("set_remote_held", true, holder)
		elif not item.has_method("pick_up") or not item.call("pick_up", holder):
			return
		else:
			pass
		motion.held_kind = "objective"
		motion.held_item = item
		motion.action_cooldown = 999.0
		motion.goal_node = null
		motion.goal_kind = ""
		return
	if not item.has_method("pick_up") or not item.call("pick_up", holder):
		return
	if item.has_method("is_weapon_pickup") and bool(item.call("is_weapon_pickup")):
		motion.held_kind = "weapon"
		motion.held_item = item
		var kind_v = item.get("weapon_kind")
		var kind := int(kind_v) if kind_v != null else 0
		if bot.has_method("show_remote_weapon"):
			bot.call("show_remote_weapon", kind)
		motion.action_cooldown = 0.6
	elif item.has_method("is_power_up_item") and bool(item.call("is_power_up_item")):
		motion.held_kind = "powerup"
		motion.held_item = item
		motion.action_cooldown = _stress_rng.randf_range(0.8, 2.0)
	else:
		motion.held_kind = "item"
		motion.held_item = item
		motion.action_cooldown = 2.0
	motion.goal_node = null
	motion.goal_kind = ""


func _bot_use_held(bot: Node, motion: BotMotion) -> void:
	# "Use" held items (visual/perf-safe). Only meaningful for sim-budget bots.
	if motion.held_item != null and not is_instance_valid(motion.held_item):
		motion.held_item = null
		motion.held_kind = ""
		return
	match motion.held_kind:
		"weapon":
			_bot_fire_weapon(bot, motion)
		"powerup":
			_bot_use_powerup(bot, motion)
		"objective":
			motion.action_cooldown = 5.0 # keep carrying
		_:
			motion.held_kind = ""
			motion.held_item = null


func _bot_fire_weapon(bot: Node, motion: BotMotion) -> void:
	var item := motion.held_item
	if item == null or not is_instance_valid(item):
		_clear_bot_weapon(bot, motion)
		return
	var kind_v = item.get("weapon_kind")
	var kind := int(kind_v) if kind_v != null else 0
	# Face local player if present, else forward.
	var target := _hive_target_for_bot(bot)
	if target != Vector3.INF and bot is Node3D:
		var d := target - (bot as Node3D).global_position
		d.y = 0.0
		if d.length_squared() > 0.01:
			bot.rotation.y = atan2(d.x, d.z)
	var action := 2 # HOOK (melee swing anim) default
	if kind in [2, 3, 5]: # AK47, GLOCK, RPG -> SHOOT
		action = 1
	if bot.has_method("play_action"):
		bot.call("play_action", action)
	# Reuse LOS damage resolution for gun shots (cheap, bounded to sim bots).
	if action == 1:
		_bot_resolve_shot(bot, motion, kind)
	motion.action_cooldown = 0.9 if action == 1 else 1.2
	# Simple ammo/consumption: drop the weapon after a few uses.
	motion.set_meta("bot_ammo", int(motion.get_meta("bot_ammo", 0)) + 1)
	var ammo := int(motion.get_meta("bot_ammo", 0))
	var limit := 3
	if kind == 1 or kind == 4:
		limit = 2
	if ammo >= limit:
		_clear_bot_weapon(bot, motion)


func _clear_bot_weapon(bot: Node, motion: BotMotion) -> void:
	if bot.has_method("show_remote_weapon"):
		bot.call("show_remote_weapon", 0)
	var item := motion.held_item
	if item != null and is_instance_valid(item) and item.has_method("deplete_and_respawn"):
		var p: Vector3 = (bot as Node3D).global_position if bot is Node3D else Vector3.ZERO
		item.call("deplete_and_respawn", p)
	motion.held_item = null
	motion.held_kind = ""
	motion.action_cooldown = 0.5
	motion.remove_meta("bot_ammo")


func _hive_target_for_bot(bot: Node) -> Vector3:
	if local_player != null and is_instance_valid(local_player) and local_player is Node3D:
		return (local_player as Node3D).global_position + Vector3.UP
	return Vector3.INF


func _bot_resolve_shot(bot: Node, motion: BotMotion, kind: int) -> void:
	# Best-effort LOS damage using the same system as gameplay. Bot avatar is a
	# RemotePlayer-like node in lobby; if it can't provide a shot ray, skip.
	if bot == null or not bot.has_method("get_shot_ray"):
		return
	var ray: Dictionary = bot.call("get_shot_ray")
	if ray.is_empty():
		return
	var origin: Vector3 = ray.get("origin", Vector3.ZERO)
	var dir: Vector3 = ray.get("dir", Vector3.FORWARD)
	# Hive-mind stress test: simplified, softened gun stats (no player.gd coupling).
	# Signature: (shooter, origin, dir, base_damage, max_range, aim_radius,
	#             falloff_start, falloff_end, falloff_min)
	var damage := 8.0
	var max_range := 70.0
	var aim_radius := 1.0
	var falloff_start := 12.0
	var falloff_end := 55.0
	var falloff_min := 0.35
	if kind == 5: # RPG
		damage = 30.0
		aim_radius = 2.0
		max_range = 80.0
		falloff_start = 6.0
		falloff_end = 50.0
		falloff_min = 0.5
	elif kind == 2: # AK47
		damage = 10.0
		max_range = 90.0
		falloff_start = 18.0
		falloff_end = 75.0
		falloff_min = 0.3
	Bullet.resolve_los_damage(bot, origin, dir, damage, max_range, aim_radius, falloff_start, falloff_end, falloff_min)


func _bot_use_powerup(bot: Node, motion: BotMotion) -> void:
	# Consume and recycle (local respawn) so lobby items keep circulating.
	var item := motion.held_item
	if item != null and is_instance_valid(item):
		var from: Vector3 = (bot as Node3D).global_position if bot is Node3D else motion.home
		if item.has_method("consume_and_respawn"):
			item.call("consume_and_respawn", from)
		elif item.has_method("consume_for_server"):
			item.call("consume_for_server")
	motion.held_item = null
	motion.held_kind = ""
	motion.action_cooldown = 1.5


func _bot_orbit_offset(motion: BotMotion) -> Vector3:
	var offset := Vector3(cos(motion.angle), 0.0, sin(motion.angle)) * motion.radius
	offset.x += sin((motion.angle * 1.7) + motion.wobble_phase) * motion.wobble
	offset.z += cos((motion.angle * 1.3) + motion.wobble_phase) * motion.wobble
	return offset


# The states a remote player actually gets sent: standing still is idle, walking
# is running, and the two halves of a hop are runningjump and falling.
func _bot_animation_state(motion: BotMotion, moving: bool) -> String:
	if motion.rig != null and not motion.rig.is_on_floor():
		return "runningjump" if motion.rig.velocity.y > 0.0 else "falling"
	if not moving:
		return "idle"
	return "running"

func _pre_seed_from_session_storage() -> void:
	if not OS.has_feature("web"):
		return
	var raw = JavaScriptBridge.eval("sessionStorage.getItem('wons_skin_cache') || ''")
	if typeof(raw) != TYPE_STRING or raw.is_empty():
		return
	var parsed = JSON.parse_string(raw)
	if parsed is Array:
		SkinApplier.seed_from_api(parsed)
		print("SkinApplier (lobby): Pre-seeded %d skins from sessionStorage." % parsed.size())

func _resolve_local_skin_name() -> String:
	if selected_skin_id.strip_edges() != "":
		return _normalize_skin_name(selected_skin_id)
	if OS.has_feature("web"):
		var raw_skin = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('skin') || ''")
		if typeof(raw_skin) == TYPE_STRING:
			var skin_name := str(raw_skin).strip_edges()
			if skin_name != "":
				return _normalize_skin_name(skin_name)
	return DEFAULT_SKIN_NAME


# What the waiting room passes on when LobbyManager sends the player into the match.
# Gameplay drives itself from its PlayerManager node, so the keys are addressed at
# that node: the queued match id rides along next to the skin, which is the part
# that has to survive -- on a native build there is no ?skin= in the URL to fall
# back on.
func match_handoff() -> Dictionary:
	return {
		"PlayerManager/selected_match_id": selected_match_id,
		"PlayerManager/selected_skin_id": _resolve_local_skin_name(),
	}

func _normalize_skin_name(raw_skin: String) -> String:
	var key := str(raw_skin).strip_edges().to_lower()
	while key.find("  ") != -1:
		key = key.replace("  ", " ")
	if SKIN_NAME_ALIASES.has(key):
		return str(SKIN_NAME_ALIASES[key])
	return key if key != "" else DEFAULT_SKIN_NAME
