class_name Ped
extends CharacterBody3D
## Pedestrians and police officers. Smooth procedural bodies on an 11-bone
## skeleton (one skinned mesh = one draw call), procedural walk / run / idle /
## flee / aim / swing animation, a small state machine, and a physics ragdoll
## that drives the same skeleton when hit hard, grabbed or killed.

enum State { WANDER, FLEE, CHASE, ATTACK, RAGDOLL, DEAD }
const B = preload("res://scripts/body_gen.gd")

var is_cop := false
var has_gun := false
var health := 100.0
var state: State = State.WANDER
var alive := true

var look: Dictionary
var skel: Skeleton3D
var body_mesh: MeshInstance3D
var body_far: MeshInstance3D
var ragdoll: Ragdoll = null
var weapon_holder: BoneAttachment3D = null
var female := false

var target_node: Vector2i
var prev_node: Vector2i
var target_pos: Vector3
var walk_speed := 1.4
var run_speed := 4.0
var anim_phase := 0.0
var anim_speed := 0.0
var anim_time := 0.0
var flee_time := 0.0
var flee_from := Vector3.ZERO
var stuck_time := 0.0
var last_pos := Vector3.ZERO
var think_timer := 0.0
var attack_cd := 0.0
var swing_anim := 0.0
var ragdoll_rest := 0.0
var sees_player := false
var aiming := false
var yaw := 0.0
var col: CollisionShape3D
var idle_seed := 0.0

# ---------------------------------------------------------------- look pool
static var looks_civ: Array = []
static var looks_cop: Array = []

## Builds the appearance pools once at startup (each look = one skinned mesh).
static func prebuild_looks() -> void:
	if not looks_civ.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 24:
		var build := i % 4
		looks_civ.append(B.make_look(build, B.random_palette(rng, build, false)))
	for i in 6:
		var build: int = [0, 1, 2, 0, 1, 3][i]
		looks_cop.append(B.make_look(build, B.random_palette(rng, build, true)))

## A person sitting in a car seat (driver / passenger), as a posed skinned mesh.
static func make_seated(cop: bool) -> Node3D:
	prebuild_looks()
	var pool: Array = looks_cop if cop else looks_civ
	var lk: Dictionary = pool[Game.rng.randi_range(0, pool.size() - 1)]
	var sk := B.make_skeleton(lk["female"])
	var mi := MeshInstance3D.new()
	mi.mesh = lk["mesh_far"]
	mi.skin = lk["skin"]
	mi.material_override = MeshLib.atlas()
	mi.visibility_range_end = 70.0
	sk.add_child(mi)
	mi.skeleton = mi.get_path_to(sk)
	var q := func(x: float, y: float = 0.0, z: float = 0.0) -> Quaternion: return Quaternion.from_euler(Vector3(x, y, z))
	sk.set_bone_pose_rotation(B.B_CHEST, q.call(0.28))
	sk.set_bone_pose_rotation(B.B_HEAD, q.call(-0.25))
	sk.set_bone_pose_rotation(B.B_THIGH_L, q.call(1.45, 0.0, -0.08))
	sk.set_bone_pose_rotation(B.B_THIGH_R, q.call(1.45, 0.0, 0.08))
	sk.set_bone_pose_rotation(B.B_SHIN_L, q.call(-1.3))
	sk.set_bone_pose_rotation(B.B_SHIN_R, q.call(-1.3))
	sk.set_bone_pose_rotation(B.B_ARM_L, q.call(0.75, 0.0, 0.18))
	sk.set_bone_pose_rotation(B.B_ARM_R, q.call(0.75, 0.0, -0.18))
	sk.set_bone_pose_rotation(B.B_FORE_L, q.call(0.75))
	sk.set_bone_pose_rotation(B.B_FORE_R, q.call(0.75))
	return sk

func _ready() -> void:
	add_to_group("peds")
	if is_cop:
		add_to_group("cops")
	collision_layer = Game.bit(Game.L_NPC)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP])
	floor_max_angle = deg_to_rad(50)
	col = MeshLib.collider(MeshLib.capsule_shape(0.28, 1.72), Vector3(0, 0.88, 0), Vector3.ZERO, self)
	_build_body()
	walk_speed = Game.randf_range(1.2, 1.6)
	run_speed = Game.randf_range(3.8, 4.6) if not is_cop else Game.randf_range(4.6, 5.2)
	var n := Game.city.nearest_walk_node(global_position)
	target_node = n
	prev_node = n
	target_pos = Game.city.walk_pos(n.x, n.y)
	yaw = Game.randf_range(0, TAU)
	rotation.y = yaw
	last_pos = global_position
	idle_seed = Game.randf_range(0.0, 100.0)
	if Game.gore:
		Game.gore.register_blob(self, 0.8)

func _build_body() -> void:
	prebuild_looks()
	var pool: Array = looks_cop if is_cop else looks_civ
	look = pool[Game.rng.randi_range(0, pool.size() - 1)]
	female = look["female"]
	skel = B.make_skeleton(female)
	skel.name = "Skeleton"
	add_child(skel)
	# two levels of detail on the same skeleton
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = look["mesh"]
	body_mesh.skin = look["skin"]
	body_mesh.material_override = MeshLib.atlas()
	body_mesh.visibility_range_end = 14.0
	skel.add_child(body_mesh)
	body_mesh.skeleton = body_mesh.get_path_to(skel)
	body_far = MeshInstance3D.new()
	body_far.mesh = look["mesh_far"]
	body_far.skin = look["skin"]
	body_far.material_override = MeshLib.atlas()
	body_far.visibility_range_begin = 14.0
	body_far.visibility_range_end = 130.0
	skel.add_child(body_far)
	body_far.skeleton = body_far.get_path_to(skel)
	if is_cop:
		_give_weapon(has_gun)

func _give_weapon(gun: bool) -> void:
	weapon_holder = BoneAttachment3D.new()
	weapon_holder.bone_name = "forearm_r"
	skel.add_child(weapon_holder)
	var mi := MeshInstance3D.new()
	mi.mesh = Weapon.visual_mesh("pistol" if gun else "baton")
	mi.material_override = MeshLib.atlas()
	# held in the fist, pointing along the forearm
	mi.position = Vector3(0, -0.33, -0.01) * (0.95 if female else 1.0)
	mi.rotation_degrees = Vector3(-90, 0, 0)
	weapon_holder.add_child(mi)

func _drop_weapon_visual() -> void:
	if weapon_holder and is_instance_valid(weapon_holder):
		weapon_holder.queue_free()
	weapon_holder = null

# ---------------------------------------------------------------- AI
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		if ragdoll and is_instance_valid(ragdoll):
			_follow_ragdoll()
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
	aiming = false
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
			if has_gun and dist < 16.0 and sees_player:
				speed = 0.0 if dist < 9.0 else walk_speed
				aiming = true
			if dist < 1.8:
				state = State.ATTACK
		State.ATTACK:
			speed = 0.0
			aiming = has_gun
			if dist > 2.3:
				state = State.CHASE
			_attack(player, dist, to_player, delta)
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
	if aiming and dist > 0.1:
		yaw = lerp_angle(yaw, atan2(-to_player.x, -to_player.z), 10.0 * delta)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	rotation.y = yaw
	move_and_slide()
	if (global_position - last_pos).length() < 0.004 and speed > 0.0:
		stuck_time += delta
		if stuck_time > 1.5:
			stuck_time = 0.0
			_pick_next_node()
			global_position += Vector3(Game.randf_range(-0.5, 0.5), 0.1, Game.randf_range(-0.5, 0.5))
	else:
		stuck_time = 0.0
	last_pos = global_position
	if dist < Game.ANIM_RANGE:
		var hv := Vector2(velocity.x, velocity.z).length()
		_animate(delta, hv)

func _think(dist: float, to_player: Vector3) -> void:
	var player := Game.player
	if player == null:
		return
	if is_cop:
		sees_player = false
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
	var from := global_position + Vector3(0, 1.55, 0)
	var to := Game.player_pos() + Vector3(0, 1.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.bit(Game.L_WORLD))
	return space.intersect_ray(q).is_empty()

## Male or female voice: "scream", "pain" or "dead". Throttled per person.
var _last_voice := -10.0
func voice(kind: String, vol: float = 0.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_voice < 0.6:
		return
	_last_voice = now
	var head := global_position + Vector3(0, 1.6, 0)
	if ragdoll and is_instance_valid(ragdoll):
		head = ragdoll.bodies[B.B_HEAD].global_position
	var name := kind
	if female:
		name = {"scream": "scream_f", "pain": "pain_f", "dead": "scream_f"}.get(kind, "pain_f")
	elif kind == "pain" and Game.rng.randf() < 0.3:
		name = "grunt"
	Game.sfx.play(name, head, vol, 0.85 if kind == "dead" else 1.0)

func scare(from: Vector3) -> void:
	if state == State.RAGDOLL or state == State.DEAD or is_cop:
		return
	if state != State.FLEE and Game.rng.randf() < 0.5:
		voice("scream", -4.0)
	state = State.FLEE
	flee_time = Game.randf_range(7.0, 14.0)
	flee_from = from
	_pick_next_node()

func _pick_next_node() -> void:
	var city := Game.city
	var cur := city.nearest_walk_node(global_position)
	if state == State.FLEE:
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

func _attack(player: Node3D, dist: float, to_player: Vector3, _delta: float) -> void:
	if player == null or not is_cop or has_gun:
		return
	if attack_cd <= 0.0 and dist < 2.1:
		attack_cd = 1.0
		swing_anim = 1.0
		Game.sfx.play("whoosh", global_position, -8.0, 1.6)
		if player.has_method("take_damage"):
			player.take_damage(9.0, to_player.normalized() * 2.0)
			Game.sfx.play("punch", player.global_position, -2.0)
		Game.cop_saw_player()

func hand_pos() -> Vector3:
	var t := skel.global_transform * skel.get_bone_global_pose(B.B_FORE_R)
	return t * Vector3(0, -0.36, 0)

func _try_shoot(dist: float, to_player: Vector3) -> void:
	if attack_cd > 0.0 or dist < 2.5 or dist > 32.0:
		return
	if not _line_of_sight():
		return
	attack_cd = Game.randf_range(0.9, 1.5)
	var from := hand_pos()
	var target := Game.player_pos() + Vector3(0, 1.2, 0)
	var acc := clampf(0.8 - dist * 0.012, 0.25, 0.8)
	var hit := Game.rng.randf() < acc
	var aim := target
	if not hit:
		aim += Vector3(Game.randf_range(-1.5, 1.5), Game.randf_range(-0.8, 0.8), Game.randf_range(-1.5, 1.5))
	Game.gore.tracer(from, aim)
	Game.gore.muzzle_flash(from)
	Game.sfx.play("pistol", from, -4.0)
	if hit and Game.player and Game.player.has_method("take_damage"):
		Game.player.take_damage(8.0, to_player.normalized() * 1.0)
	Game.cop_saw_player()

# ---------------------------------------------------------------- animation
func _q(x: float, y: float = 0.0, z: float = 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))

func _animate(delta: float, speed: float) -> void:
	anim_time += delta
	anim_speed = lerpf(anim_speed, speed, 8.0 * delta)
	var sp := anim_speed
	var w := clampf(sp / 1.4, 0.0, 1.0)              # walk weight
	var r := clampf((sp - 2.0) / 2.2, 0.0, 1.0)       # run weight
	var cadence := lerpf(5.6, 8.6, r) if sp > 0.05 else 0.0
	var prev_phase := anim_phase
	anim_phase = fmod(anim_phase + delta * cadence * clampf(sp / 1.4, 0.6, 1.4), TAU)
	if sp > 0.5 and (prev_phase < PI and anim_phase >= PI or anim_phase < prev_phase):
		if global_position.distance_to(Game.player_pos()) < 14.0:
			Game.sfx.play("step", global_position + Vector3(0, 0.05, 0), -6.0 + clampf(sp - 1.5, 0.0, 3.0) * 2.0, 1.0 + (0.08 if female else 0.0))
	var ph := anim_phase
	var s := sin(ph)
	var c := cos(ph)
	var hip_a := w * 0.42 + r * 0.38
	var knee_a := w * 0.55 + r * 0.95
	var breathe := sin(anim_time * 1.6 + idle_seed) * 0.015 * (1.0 - w)
	var sway := sin(anim_time * 0.5 + idle_seed) * 0.04 * (1.0 - w)
	# legs
	skel.set_bone_pose_rotation(B.B_THIGH_L, _q(hip_a * s + 0.04 * r, 0, -0.02))
	skel.set_bone_pose_rotation(B.B_THIGH_R, _q(-hip_a * s + 0.04 * r, 0, 0.02))
	skel.set_bone_pose_rotation(B.B_SHIN_L, _q(-(0.04 + knee_a * maxf(0.0, c) + 0.15 * r)))
	skel.set_bone_pose_rotation(B.B_SHIN_R, _q(-(0.04 + knee_a * maxf(0.0, -c) + 0.15 * r)))
	# pelvis bob and twist, chest counter-rotation and lean
	var bob := -absf(s) * (0.025 * w + 0.04 * r)
	var pv: Vector3 = B.pivots(female)[B.B_PELVIS]
	skel.set_bone_pose_position(B.B_PELVIS, pv + Vector3(sway * 0.3, bob + breathe * 0.2, 0))
	skel.set_bone_pose_rotation(B.B_PELVIS, _q(0, 0.1 * s * w, sway * 0.3))
	var lean := -0.04 * w - 0.22 * r
	skel.set_bone_pose_rotation(B.B_CHEST, _q(lean + breathe, -0.16 * s * w, -sway * 0.3))
	# arms
	var arm_a := w * 0.4 + r * 0.55
	var elbow := 0.12 + 0.18 * w + 1.15 * r
	var al := _q(-arm_a * s * 0.8, 0, -0.07 - 0.05 * r)
	var ar := _q(arm_a * s * 0.8, 0, 0.07 + 0.05 * r)
	var fl := _q(elbow + 0.15 * maxf(0.0, -s) * w)
	var fr := _q(elbow + 0.15 * maxf(0.0, s) * w)
	if state == State.FLEE:
		# panicked running: arms flailing up
		al = _q(0.9 + 0.6 * sin(anim_time * 11.0), 0, -0.5)
		ar = _q(0.9 + 0.6 * cos(anim_time * 10.0), 0, 0.5)
		fl = _q(1.3)
		fr = _q(1.3)
	if aiming:
		ar = _q(1.5, 0, -0.12)
		fr = _q(0.05)
		al = _q(1.25, 0, 0.45)
		fl = _q(0.55)
	if swing_anim > 0.0:
		swing_anim = maxf(0.0, swing_anim - delta * 3.0)
		ar = _q(0.2 + 2.6 * swing_anim, 0, 0.1)
		fr = _q(0.4)
	skel.set_bone_pose_rotation(B.B_ARM_L, al)
	skel.set_bone_pose_rotation(B.B_ARM_R, ar)
	skel.set_bone_pose_rotation(B.B_FORE_L, fl)
	skel.set_bone_pose_rotation(B.B_FORE_R, fr)
	# head: look at the player when close or alerted
	var look_y := 0.0
	var look_x := 0.0
	var to_p := Game.player_pos() + Vector3(0, 1.6, 0) - (global_position + Vector3(0, 1.6, 0))
	if to_p.length() < 12.0 or state == State.CHASE or state == State.ATTACK:
		var local := global_transform.basis.inverse() * to_p
		look_y = clampf(atan2(-local.x, -local.z), -1.0, 1.0)
		look_x = clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.4, 0.4)
	skel.set_bone_pose_rotation(B.B_HEAD, _q(look_x - lean * 0.6, look_y + 0.16 * s * w, 0))

# ---------------------------------------------------------------- damage
func take_hit(dmg: float, impulse: Vector3, pos: Vector3, part: String, kind: String) -> void:
	if (state == State.DEAD or state == State.RAGDOLL) and ragdoll and is_instance_valid(ragdoll):
		ragdoll.take_hit(dmg, impulse, pos, part, kind)
		return
	if state == State.DEAD:
		return
	if part == "" or B.BONES.find(part) < 0:
		part = part_from_point(pos)
	if part == "head":
		dmg *= 2.2 if kind == "bullet" else 1.4
	health -= dmg
	Game.gore.spray(pos, impulse.normalized() + Vector3.UP * 0.4, clampf(dmg / 25.0, 0.6, 2.2))
	if kind == "punch":
		Game.sfx.play("punch", pos, 0.0)
	elif kind == "sharp":
		Game.sfx.play("slash", pos, 0.0)
	else:
		Game.sfx.play("squish", pos, -3.0)
	Game.crime("cop_assault" if is_cop else "assault")
	Game.panic(global_position, 14.0)
	if health <= 0.0:
		die(kind, impulse, pos, part)
		return
	voice("pain", -2.0)
	if kind in ["car", "throw", "explosion", "sharp"] or impulse.length() > 7.0:
		go_ragdoll(impulse, pos, part)
		if ragdoll:
			ragdoll.add_wound(ragdoll.body_of(part), pos)
	elif is_cop:
		state = State.CHASE
	else:
		scare(Game.player_pos())

func ragdoll_damage(dmg: float, _kind: String) -> void:
	if state == State.DEAD:
		return
	health -= dmg
	if health > 0.0 and dmg > 8.0:
		voice("pain", 0.0)
	elif health <= 0.0 and dmg < 500.0:
		voice("dead", 0.0)
	if health <= 0.0:
		state = State.DEAD
		alive = false
		if ragdoll and is_instance_valid(ragdoll):
			ragdoll.alive = false
		_on_killed()

## Nearest body part to a world point, using the live skeleton.
func part_from_point(pos: Vector3) -> String:
	var best := "chest"
	var bd := INF
	var segs := {B.B_PELVIS: [Vector3(0, -0.1, 0), Vector3(0, 0.08, 0)], B.B_CHEST: [Vector3(0, 0.0, 0), Vector3(0, 0.38, 0)],
		B.B_HEAD: [Vector3(0, 0.08, 0), Vector3(0, 0.26, 0)]}
	for b in B.BONES.size():
		var seg: Array = segs.get(b, [Vector3.ZERO, Vector3(0, -0.28 if b in [B.B_ARM_L, B.B_ARM_R] else -0.42, 0)])
		var t := skel.global_transform * skel.get_bone_global_pose(b)
		var a: Vector3 = t * (seg[0] as Vector3)
		var e: Vector3 = t * (seg[1] as Vector3)
		var p := Geometry3D.get_closest_point_to_segment(pos, a, e)
		var radius := 0.11 if b == B.B_HEAD else (0.15 if b in [B.B_CHEST, B.B_PELVIS] else 0.06)
		var d := p.distance_to(pos) - radius
		if d < bd:
			bd = d
			best = B.BONES[b]
	return best

func die(kind: String, impulse: Vector3, pos: Vector3, part: String) -> void:
	if state == State.DEAD:
		return
	alive = false
	var was_ragdoll := ragdoll != null and is_instance_valid(ragdoll)
	state = State.DEAD
	if not was_ragdoll:
		go_ragdoll(impulse, pos, part)
	else:
		ragdoll.alive = false
		ragdoll.apply_impulse_to(part, impulse, pos)
	if ragdoll and is_instance_valid(ragdoll):
		ragdoll.alive = false
		var bi := B.BONES.find(part)
		ragdoll.add_wound(ragdoll.body_of(part), pos)
		if kind == "explosion":
			ragdoll.gib()
		elif kind == "sharp" and part not in ["chest", "pelvis"]:
			ragdoll.dismember(bi, impulse * 0.5)
		elif kind == "bullet" and part == "head" and Game.rng.randf() < 0.5:
			ragdoll.pop_head(impulse)
		elif kind in ["punch", "melee"] and part == "head" and impulse.length() > 10.0:
			ragdoll.pop_head(impulse)
		elif kind == "car":
			if impulse.length() > 600.0 and Game.rng.randf() < 0.35:
				ragdoll.dismember(B.B_CHEST, impulse * 0.2)
			elif Game.rng.randf() < 0.5:
				ragdoll.dismember([B.B_ARM_L, B.B_ARM_R, B.B_THIGH_L, B.B_THIGH_R, B.B_FORE_L, B.B_SHIN_R][Game.randi_range(0, 5)], impulse * 0.3)
	voice("dead", -2.0)
	_on_killed()

func _on_killed() -> void:
	Game.crime("cop_murder" if is_cop else "murder")
	Game.panic(global_position, 20.0)
	if is_cop and weapon_holder and Game.main and Game.main.has_method("drop_weapon"):
		Game.main.drop_weapon("pistol" if has_gun else "baton", hand_pos())
	_drop_weapon_visual()
	remove_from_group("peds")
	remove_from_group("cops")
	add_to_group("corpses")

## Switch to physics ragdoll (alive or dead).
func go_ragdoll(impulse: Vector3, pos: Vector3 = Vector3.INF, part: String = "chest") -> void:
	if ragdoll and is_instance_valid(ragdoll):
		ragdoll.apply_impulse_to(part, impulse, pos)
		return
	if state != State.DEAD:
		state = State.RAGDOLL
	if B.BONES.find(part) < 0:
		part = "chest"
	ragdoll = Ragdoll.new()
	Game.main.add_child(ragdoll)
	ragdoll.setup(self, skel, female, alive)
	var v0 := Vector3(velocity.x, 0.0, velocity.z)
	collision_layer = 0
	collision_mask = 0
	col.disabled = true
	velocity = Vector3.ZERO
	body_mesh.custom_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50))
	body_far.custom_aabb = body_mesh.custom_aabb
	# carry the walking/running motion into the ragdoll
	for b in ragdoll.bodies:
		b.linear_velocity = v0
	ragdoll.apply_impulse_to(part, impulse, pos)
	ragdoll_rest = 0.0
	limit_ragdolls()

static func limit_ragdolls() -> void:
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

func _follow_ragdoll() -> void:
	var p := ragdoll.pelvis().global_position
	var old := global_position
	global_position = Vector3(p.x, global_position.y, p.z)
	if (global_position - old).length() > 0.0001:
		ragdoll._drive_skeleton()

func _ragdoll_follow(delta: float) -> void:
	if ragdoll == null or not is_instance_valid(ragdoll):
		state = State.DEAD
		return
	_follow_ragdoll()
	var t := ragdoll.pelvis()
	if ragdoll.held_count > 0 or t.linear_velocity.length() > 0.6:
		ragdoll_rest = 0.0
		return
	ragdoll_rest += delta
	if ragdoll_rest > 2.2 and alive and ragdoll.severed.is_empty():
		_stand_up()

func _stand_up() -> void:
	var chest := ragdoll.torso()
	var p := ragdoll.pelvis().global_position
	var fwd := -chest.global_transform.basis.z
	yaw = atan2(-fwd.x, -fwd.z)
	ragdoll.queue_free()
	ragdoll = null
	global_position = Vector3(p.x, Game.city.ground_height(p) + 0.05, p.z)
	rotation.y = yaw
	skel.reset_bone_poses()
	body_mesh.custom_aabb = AABB()
	body_far.custom_aabb = AABB()
	collision_layer = Game.bit(Game.L_NPC)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP])
	col.disabled = false
	velocity = Vector3.ZERO
	if is_cop:
		state = State.CHASE
	else:
		scare(Game.player_pos())
		state = State.FLEE
		flee_time = 12.0
