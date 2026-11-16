class_name Ped
extends CharacterBody3D
## Pedestrians and police officers. Low-poly procedural bodies with simple
## procedural walk animation, a tiny state machine, and conversion to a
## physics ragdoll when hit hard, grabbed, or killed.

enum State { WANDER, FLEE, CHASE, ATTACK, RAGDOLL, DEAD }

var is_cop := false
var has_gun := false
var health := 100.0
var state: State = State.WANDER
var alive := true

var parts: Dictionary = {}          # part -> MeshInstance3D
var pivots: Dictionary = {}         # part -> Node3D (limb pivot)
var part_local: Dictionary = {}     # part -> Transform3D (mesh local under pivot)
var shapes: Dictionary = {}         # part -> Shape3D (for ragdoll)
var ragdoll: Ragdoll = null
var weapon_mesh: MeshInstance3D = null

var target_node: Vector2i
var prev_node: Vector2i
var target_pos: Vector3
var walk_speed := 1.4
var run_speed := 4.0
var anim_phase := 0.0
var flee_time := 0.0
var flee_from := Vector3.ZERO
var stuck_time := 0.0
var last_pos := Vector3.ZERO
var think_timer := 0.0
var attack_cd := 0.0
var swing_anim := 0.0
var ragdoll_rest := 0.0
var sees_player := false
var yaw := 0.0
var col: CollisionShape3D

func _ready() -> void:
	add_to_group("peds")
	if is_cop:
		add_to_group("cops")
	collision_layer = Game.bit(Game.L_NPC)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP])
	col = MeshLib.collider(MeshLib.capsule_shape(0.3, 1.7), Vector3(0, 0.9, 0), Vector3.ZERO, self)
	_build_body()
	walk_speed = Game.randf_range(1.2, 1.7)
	run_speed = Game.randf_range(3.8, 4.6) if not is_cop else Game.randf_range(4.6, 5.2)
	var n := Game.city.nearest_walk_node(global_position)
	target_node = n
	prev_node = n
	target_pos = Game.city.walk_pos(n.x, n.y)
	yaw = Game.randf_range(0, TAU)
	rotation.y = yaw
	last_pos = global_position
	if Game.gore:
		Game.gore.register_blob(self, 0.9)

# ---------------------------------------------------------------- body
# Appearances are pre-built (merged meshes) so spawning a person is cheap and
# each person costs only 6 draw calls.
static var looks_civ: Array = []
static var looks_cop: Array = []

static func _make_look(cop: bool) -> Dictionary:
	var rng := Game.rng
	var skin: Color = MeshLib.SKIN[rng.randi_range(0, MeshLib.SKIN.size() - 1)]
	var shirt: Color
	var pants: Color
	if cop:
		shirt = Color(0.12, 0.2, 0.45)
		pants = Color(0.08, 0.1, 0.2)
	else:
		shirt = Game.rand_color_variant(MeshLib.SHIRTS[rng.randi_range(0, MeshLib.SHIRTS.size() - 1)])
		pants = Game.rand_color_variant(MeshLib.PANTS[rng.randi_range(0, MeshLib.PANTS.size() - 1)])
	var torso := [MeshLib.part(MeshLib.box(Vector3(0.38, 0.56, 0.22)), Vector3.ZERO, Vector3.ZERO, shirt, 0.9)]
	if cop:
		torso.append(MeshLib.part(MeshLib.box(Vector3(0.06, 0.07, 0.02)), Vector3(-0.1, 0.12, -0.115), Vector3.ZERO, Color(1.0, 0.85, 0.2), 0.3, 0.8))
		torso.append(MeshLib.part(MeshLib.box(Vector3(0.4, 0.06, 0.24)), Vector3(0, -0.26, 0), Vector3.ZERO, Color(0.05, 0.05, 0.05), 0.5))
		torso.append(MeshLib.part(MeshLib.box(Vector3(0.39, 0.08, 0.23)), Vector3(0, 0.24, 0), Vector3.ZERO, Color(0.1, 0.16, 0.36), 0.9))
	elif rng.randf() < 0.45:
		torso.append(MeshLib.part(MeshLib.box(Vector3(0.2, 0.3, 0.02)), Vector3(0, 0.05, -0.115), Vector3.ZERO, Game.rand_color_variant(shirt, 0.3), 0.9))
	var head := [MeshLib.part(MeshLib.sphere(0.12, 8, 5), Vector3.ZERO, Vector3.ZERO, skin, 0.7)]
	head.append(MeshLib.part(MeshLib.box(Vector3(0.025, 0.025, 0.02)), Vector3(-0.045, 0.02, -0.11), Vector3.ZERO, Color(0.05, 0.05, 0.05), 0.3))
	head.append(MeshLib.part(MeshLib.box(Vector3(0.025, 0.025, 0.02)), Vector3(0.045, 0.02, -0.11), Vector3.ZERO, Color(0.05, 0.05, 0.05), 0.3))
	head.append(MeshLib.part(MeshLib.box(Vector3(0.03, 0.04, 0.03)), Vector3(0, -0.01, -0.12), Vector3.ZERO, skin.darkened(0.08), 0.7))
	if cop:
		head.append(MeshLib.part(MeshLib.box(Vector3(0.26, 0.07, 0.26)), Vector3(0, 0.1, 0), Vector3.ZERO, Color(0.08, 0.1, 0.22), 0.9))
		head.append(MeshLib.part(MeshLib.box(Vector3(0.24, 0.02, 0.1)), Vector3(0, 0.07, -0.16), Vector3.ZERO, Color(0.05, 0.05, 0.05), 0.5))
	elif rng.randf() < 0.85:
		var hair_c := [Color(0.1, 0.07, 0.05), Color(0.45, 0.3, 0.15), Color(0.9, 0.8, 0.5), Color(0.2, 0.2, 0.2), Color(0.6, 0.1, 0.1)]
		head.append(MeshLib.part(MeshLib.box(Vector3(0.22, 0.08, 0.22)), Vector3(0, 0.09, 0.01), Vector3.ZERO, hair_c[rng.randi_range(0, hair_c.size() - 1)], 0.9))
	var arm := [MeshLib.part(MeshLib.capsule(0.055, 0.6, 6, 3), Vector3.ZERO, Vector3.ZERO, shirt, 0.9),
		MeshLib.part(MeshLib.sphere(0.06, 6, 4), Vector3(0, -0.3, 0), Vector3.ZERO, skin, 0.7)]
	var leg := [MeshLib.part(MeshLib.capsule(0.075, 0.84, 6, 3), Vector3.ZERO, Vector3.ZERO, pants, 0.9),
		MeshLib.part(MeshLib.box(Vector3(0.12, 0.06, 0.24)), Vector3(0, -0.42, -0.04), Vector3.ZERO, Color(0.1, 0.08, 0.06), 0.6)]
	return {"torso": MeshLib.build(torso), "head": MeshLib.build(head), "arm": MeshLib.build(arm), "leg": MeshLib.build(leg)}

## Build the appearance pools once (called at startup).
static func prebuild_looks() -> void:
	if looks_civ.is_empty():
		for i in 22:
			looks_civ.append(_make_look(false))
		for i in 5:
			looks_cop.append(_make_look(true))

func _build_body() -> void:
	prebuild_looks()
	var pool: Array = looks_cop if is_cop else looks_civ
	var look: Dictionary = pool[Game.rng.randi_range(0, pool.size() - 1)]
	var torso := MeshLib.inst_built(look["torso"], Vector3(0, 1.15, 0), Vector3.ZERO, self)
	_register("torso", torso, self, MeshLib.box_shape(Vector3(0.38, 0.56, 0.22)))
	var head_p := Node3D.new()
	head_p.position = Vector3(0, 1.45, 0)
	add_child(head_p)
	var head := MeshLib.inst_built(look["head"], Vector3(0, 0.17, 0), Vector3.ZERO, head_p)
	_register("head", head, head_p, MeshLib.sphere_shape(0.12))
	for side in [-1.0, 1.0]:
		var p := Node3D.new()
		p.position = Vector3(0.25 * side, 1.4, 0)
		add_child(p)
		var upper := MeshLib.inst_built(look["arm"], Vector3(0, -0.28, 0), Vector3.ZERO, p)
		var hand := Node3D.new()
		hand.name = "hand"
		hand.position = Vector3(0, -0.3, 0)
		upper.add_child(hand)
		_register("arm_l" if side < 0 else "arm_r", upper, p, MeshLib.capsule_shape(0.06, 0.62))
	for side in [-1.0, 1.0]:
		var p := Node3D.new()
		p.position = Vector3(0.1 * side, 0.86, 0)
		add_child(p)
		var leg := MeshLib.inst_built(look["leg"], Vector3(0, -0.43, 0), Vector3.ZERO, p)
		_register("leg_l" if side < 0 else "leg_r", leg, p, MeshLib.capsule_shape(0.08, 0.86))
	if is_cop:
		_give_weapon(has_gun)

func _register(part: String, mesh: MeshInstance3D, pivot: Node3D, shape: Shape3D) -> void:
	parts[part] = mesh
	pivots[part] = pivot
	part_local[part] = mesh.transform
	shapes[part] = shape
	mesh.set_meta("part", part)

func _give_weapon(gun: bool) -> void:
	var hand: Node3D = parts["arm_r"].get_node("hand")
	if gun:
		weapon_mesh = MeshLib.inst(MeshLib.box(Vector3(0.04, 0.12, 0.2)), MeshLib.mat(Color(0.1, 0.1, 0.1), 0.4, 0.7), Vector3(0, -0.02, -0.1), Vector3.ZERO, hand)
	else:
		weapon_mesh = MeshLib.inst(MeshLib.cylinder(0.02, 0.6, 5), MeshLib.mat(Color(0.05, 0.05, 0.05), 0.5), Vector3(0, 0.05, -0.25), Vector3(90, 0, 0), hand)

# ---------------------------------------------------------------- AI
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		if ragdoll and is_instance_valid(ragdoll):
			global_position = ragdoll.torso().global_position
		return
	if state == State.RAGDOLL:
		_ragdoll_follow(delta)
		return
	var player := Game.player
	var ppos := Game.player_pos()
	var to_player := Game.flat(ppos - global_position)
	var dist := to_player.length()
	think_timer -= delta
	attack_cd -= delta
	if think_timer <= 0.0:
		think_timer = Game.randf_range(0.25, 0.45)
		_think(dist, to_player)
	var speed := walk_speed
	var move_target := target_pos
	match state:
		State.WANDER:
			speed = walk_speed
		State.FLEE:
			speed = run_speed
			flee_time -= delta
			if flee_time <= 0.0:
				state = State.WANDER
				_pick_next_node()
		State.CHASE:
			speed = run_speed
			move_target = ppos
			if dist < 1.8:
				state = State.ATTACK
		State.ATTACK:
			speed = 0.0
			if dist > 2.3:
				state = State.CHASE
			_attack(player, dist, to_player, delta)
	# movement
	var dir := Game.flat(move_target - global_position)
	var d := dir.length()
	if d > 0.5 and speed > 0.0:
		dir = dir / d
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if state == State.WANDER or state == State.FLEE:
			_pick_next_node()
		elif state == State.ATTACK and dist > 0.1:
			yaw = lerp_angle(yaw, atan2(-to_player.x, -to_player.z), 12.0 * delta)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	rotation.y = yaw
	move_and_slide()
	# stuck detection
	if (global_position - last_pos).length() < 0.05 * delta * 90.0 * 0.1 and speed > 0.0:
		stuck_time += delta
		if stuck_time > 1.5:
			stuck_time = 0.0
			_pick_next_node()
			global_position += Vector3(Game.randf_range(-0.5, 0.5), 0, Game.randf_range(-0.5, 0.5))
	else:
		stuck_time = 0.0
	last_pos = global_position
	# animation (only near the player)
	if dist < Game.ANIM_RANGE:
		_animate(delta, speed if d > 0.5 else 0.0)

func _think(dist: float, to_player: Vector3) -> void:
	var player := Game.player
	if player == null:
		return
	if is_cop:
		if Game.wanted_stars > 0 and dist < 48.0 and _line_of_sight():
			Game.cop_saw_player()
			sees_player = true
			if state != State.ATTACK:
				state = State.CHASE
		elif state == State.CHASE and dist > 70.0:
			state = State.WANDER
			_pick_next_node()
		if (state == State.CHASE or state == State.ATTACK) and has_gun:
			_try_shoot(dist, to_player)
	else:
		var armed: bool = player.has_method("is_armed") and player.is_armed()
		if state != State.FLEE and ((dist < 7.0 and (armed or Game.wanted_stars > 0)) or (dist < 3.0 and Game.wanted_stars > 1)):
			scare(Game.player_pos())

func _line_of_sight() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.5, 0)
	var to := Game.player_pos() + Vector3(0, 1.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.bit(Game.L_WORLD))
	var r := space.intersect_ray(q)
	return r.is_empty()

func scare(from: Vector3) -> void:
	if state == State.RAGDOLL or state == State.DEAD or is_cop:
		return
	if state != State.FLEE and Game.rng.randf() < 0.5:
		Game.sfx.play("scream", global_position, -6.0, Game.randf_range(0.8, 1.3))
	state = State.FLEE
	flee_time = Game.randf_range(7.0, 14.0)
	flee_from = from
	_pick_next_node()

func _pick_next_node() -> void:
	var city := Game.city
	var cur := city.nearest_walk_node(global_position)
	if state == State.FLEE:
		# choose the neighbour furthest from the threat
		var best := cur
		var bd := -1.0
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + dd
			if n.x < 0 or n.y < 0 or n.x >= city.walk_count() or n.y >= city.walk_count():
				continue
			var dist := Game.flat(city.walk_pos(n.x, n.y) - flee_from).length()
			if dist > bd:
				bd = dist
				best = n
		prev_node = cur
		target_node = best
	else:
		var n := city.next_walk_node(cur, prev_node)
		prev_node = cur
		target_node = n
	target_pos = city.walk_pos(target_node.x, target_node.y) + Vector3(Game.randf_range(-0.8, 0.8), 0, Game.randf_range(-0.8, 0.8))

func _attack(player: Node3D, dist: float, to_player: Vector3, delta: float) -> void:
	if player == null or not is_cop:
		return
	if has_gun:
		return   # handled by _try_shoot
	if attack_cd <= 0.0 and dist < 2.1:
		attack_cd = 1.0
		swing_anim = 1.0
		Game.sfx.play("whoosh", global_position, -8.0, 1.6)
		if player.has_method("take_damage"):
			player.take_damage(9.0, to_player.normalized() * 2.0)
			Game.sfx.play("punch", player.global_position, -2.0)
		Game.cop_saw_player()

func _try_shoot(dist: float, to_player: Vector3) -> void:
	if attack_cd > 0.0 or dist < 2.5 or dist > 32.0:
		return
	if not _line_of_sight():
		return
	attack_cd = Game.randf_range(0.9, 1.5)
	swing_anim = 0.6
	var hand: Node3D = parts["arm_r"].get_node("hand")
	var from := hand.global_position
	var target := Game.player_pos() + Vector3(0, 1.2, 0)
	var acc := clampf(0.8 - dist * 0.012, 0.25, 0.8)
	var hit := Game.rng.randf() < acc
	var aim := target
	if not hit:
		aim += Vector3(Game.randf_range(-1.5, 1.5), Game.randf_range(-0.8, 0.8), Game.randf_range(-1.5, 1.5))
	Game.gore.tracer(from, aim)
	Game.sfx.play("pistol", from, -4.0)
	if hit and Game.player and Game.player.has_method("take_damage"):
		Game.player.take_damage(8.0, to_player.normalized() * 1.0)
	Game.cop_saw_player()

func _animate(delta: float, speed: float) -> void:
	anim_phase += delta * speed * 2.4
	var amp := clampf(speed / 3.0, 0.0, 1.0) * 0.9
	var s := sin(anim_phase) * amp
	pivots["leg_l"].rotation.x = s
	pivots["leg_r"].rotation.x = -s
	var arm_swing := -s * 0.7
	pivots["arm_l"].rotation.x = arm_swing
	pivots["arm_r"].rotation.x = -arm_swing
	if state == State.FLEE:
		pivots["arm_l"].rotation.x -= 0.8
		pivots["arm_r"].rotation.x -= 0.8
	if swing_anim > 0.0:
		swing_anim = maxf(0.0, swing_anim - delta * 3.0)
		pivots["arm_r"].rotation.x = -1.6 + (1.0 - swing_anim) * 1.2
	if has_gun and (state == State.CHASE or state == State.ATTACK):
		pivots["arm_r"].rotation.x = -1.5
	pivots["head"].rotation.y = sin(anim_phase * 0.5) * 0.15

# ---------------------------------------------------------------- damage
## Hit by the player (hands, weapons, bullets, telekinesis throws, cars).
func take_hit(dmg: float, impulse: Vector3, pos: Vector3, part: String, kind: String) -> void:
	if state == State.DEAD:
		if ragdoll and is_instance_valid(ragdoll):
			ragdoll.take_hit(dmg, impulse, pos, part, kind)
		return
	if state == State.RAGDOLL and ragdoll and is_instance_valid(ragdoll):
		ragdoll.take_hit(dmg, impulse, pos, part, kind)
		return
	if part == "":
		part = part_from_point(pos)
	if part == "head":
		dmg *= 2.0 if kind == "bullet" else 1.4
	health -= dmg
	Game.gore.spray(pos, impulse.normalized() + Vector3.UP * 0.4, clampf(dmg / 25.0, 0.6, 2.2))
	if kind == "punch":
		Game.sfx.play("punch", pos, 0.0)
	elif kind == "sharp":
		Game.sfx.play("slash", pos, 0.0)
	else:
		Game.sfx.play("squish", pos, -3.0)
	if is_cop:
		Game.crime("cop_assault")
	else:
		Game.crime("assault")
	Game.panic(global_position, 14.0)
	if health <= 0.0:
		die(kind, impulse, pos, part)
		return
	Game.sfx.play("grunt" if Game.rng.randf() < 0.6 else "yell", global_position, -4.0, Game.randf_range(0.8, 1.2))
	if kind in ["car", "throw", "explosion", "sharp"] or impulse.length() > 7.0:
		go_ragdoll(impulse, pos, part)
	elif is_cop:
		state = State.CHASE
	else:
		scare(Game.player_pos())

## Damage taken while already ragdolled and alive (impacts, drops).
func ragdoll_damage(dmg: float, kind: String) -> void:
	if state == State.DEAD:
		return
	health -= dmg
	if health <= 0.0:
		state = State.DEAD
		alive = false
		if ragdoll and is_instance_valid(ragdoll):
			ragdoll.alive = false
		_on_killed()

func part_from_point(pos: Vector3) -> String:
	var l := to_local(pos)
	if l.y > 1.42:
		return "head"
	if l.y < 0.86:
		return "leg_l" if l.x < 0.0 else "leg_r"
	if absf(l.x) > 0.19:
		return "arm_l" if l.x < 0.0 else "arm_r"
	return "torso"

func die(kind: String, impulse: Vector3, pos: Vector3, part: String) -> void:
	if state == State.DEAD:
		return
	alive = false
	state = State.DEAD
	if ragdoll == null or not is_instance_valid(ragdoll):
		go_ragdoll(impulse, pos, part)
	else:
		ragdoll.alive = false
		ragdoll.apply_impulse_to(part, impulse, pos)
	if ragdoll and is_instance_valid(ragdoll):
		if kind == "explosion":
			ragdoll.gib()
		elif kind == "sharp" and part != "torso":
			ragdoll.dismember(part, impulse * 0.5)
		elif kind == "bullet" and part == "head" and Game.rng.randf() < 0.5:
			ragdoll.pop_head(impulse)
		elif kind in ["punch", "melee"] and part == "head" and impulse.length() > 10.0:
			ragdoll.pop_head(impulse)
		elif kind == "car" and Game.rng.randf() < 0.5:
			ragdoll.dismember(["arm_l", "arm_r", "leg_l", "leg_r"][Game.randi_range(0, 3)], impulse * 0.3)
	Game.sfx.play("dead", global_position, -6.0, Game.randf_range(0.8, 1.25))
	_on_killed()

func _on_killed() -> void:
	Game.crime("cop_murder" if is_cop else "murder")
	Game.panic(global_position, 20.0)
	if is_cop and Game.main and Game.main.has_method("drop_weapon"):
		Game.main.drop_weapon("pistol" if has_gun else "baton", global_position + Vector3(0, 1.0, 0))
	remove_from_group("peds")
	remove_from_group("cops")
	add_to_group("corpses")

## Switch to physics ragdoll (alive or dead).
func go_ragdoll(impulse: Vector3, pos: Vector3 = Vector3.INF, part: String = "torso") -> void:
	if ragdoll and is_instance_valid(ragdoll):
		ragdoll.apply_impulse_to(part, impulse, pos)
		return
	if state != State.DEAD:
		state = State.RAGDOLL
	# reset limb pivots to neutral so the ragdoll starts in a sane pose
	for limb in pivots.keys():
		if limb != "torso":
			pivots[limb].rotation = Vector3.ZERO
	ragdoll = Ragdoll.new()
	get_tree().current_scene.add_child(ragdoll)
	ragdoll.setup(self, parts, shapes, alive)
	collision_layer = 0
	collision_mask = 0
	col.disabled = true
	velocity = Vector3.ZERO
	if weapon_mesh and is_instance_valid(weapon_mesh):
		weapon_mesh.queue_free()
		weapon_mesh = null
	ragdoll.apply_impulse_to(part, impulse, pos)
	ragdoll_rest = 0.0
	Ragdoll_limit()

static func Ragdoll_limit() -> void:
	# Keep ragdoll count bounded: freeze/remove the oldest.
	var list := []
	for c in Game.main.get_children():
		if c is Ragdoll:
			list.append(c)
	if list.size() > Game.MAX_RAGDOLLS:
		list.sort_custom(func(a, b): return a.age > b.age)
		for i in range(0, list.size() - Game.MAX_RAGDOLLS):
			var r: Ragdoll = list[i]
			if r.held_count == 0:
				if r.ped and is_instance_valid(r.ped):
					r.ped.queue_free()
				r.queue_free()

func _ragdoll_follow(delta: float) -> void:
	if ragdoll == null or not is_instance_valid(ragdoll):
		state = State.DEAD
		return
	var t := ragdoll.torso()
	global_position = t.global_position
	if ragdoll.held_count > 0 or t.linear_velocity.length() > 0.6:
		ragdoll_rest = 0.0
		return
	ragdoll_rest += delta
	if ragdoll_rest > 2.2 and alive:
		_stand_up()

func _stand_up() -> void:
	var t := ragdoll.torso()
	var p := t.global_position
	var returned := ragdoll.release_parts()
	for part in returned.keys():
		var mi: MeshInstance3D = returned[part]
		mi.reparent(pivots[part], false)
		mi.transform = part_local[part]
	ragdoll.queue_free()
	ragdoll = null
	global_position = Vector3(p.x, 0.0, p.z)
	collision_layer = Game.bit(Game.L_NPC)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP])
	col.disabled = false
	velocity = Vector3.ZERO
	if is_cop:
		state = State.CHASE
		_give_weapon(has_gun)
	else:
		scare(Game.player_pos())
		state = State.FLEE
		flee_time = 12.0
