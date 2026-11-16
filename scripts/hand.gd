class_name Hand
extends XRController3D
## One VR hand: punching, grabbing (weapons, people, cars, props),
## telekinesis (trigger with an empty hand) and the force push shockwave.

var side := "right"
var player: Node3D
var velocity := Vector3.ZERO
var ang_velocity := Vector3.ZERO
var last_pos := Vector3.ZERO
var last_basis := Basis()
var grab_area: Area3D
var held: Node3D = null          # Weapon (attached) or RigidBody3D (kinematic hold)
var held_ragdoll: Ragdoll = null
var tk_target: RigidBody3D = null
var tk_ragdoll: Ragdoll = null
var tk_dist := 3.0
var tk_pull := false
var tk_beam: MeshInstance3D
var tk_halo: MeshInstance3D
var tk_hum: AudioStreamPlayer3D
var punch_cd := 0.0
var push_cd := 0.0
var push_ring: MeshInstance3D
var push_t := -1.0
var grip_prev := false
var trigger_prev := false
var click_prev := false
var hand_mesh: Node3D
# desktop simulation inputs
var sim_trigger := 0.0
var sim_grip := false
var sim_click := false
var sim_stick := Vector2.ZERO

func _ready() -> void:
	tracker = "left_hand" if side == "left" else "right_hand"
	pose = "aim"
	_build_hand()
	grab_area = Area3D.new()
	grab_area.collision_layer = 0
	grab_area.collision_mask = Game.mask([Game.L_NPC, Game.L_RAGDOLL, Game.L_PROP, Game.L_CAR])
	grab_area.monitoring = true
	grab_area.monitorable = false
	MeshLib.collider(MeshLib.sphere_shape(0.1), Vector3(0, -0.02, -0.04), Vector3.ZERO, grab_area)
	add_child(grab_area)
	# telekinesis visuals
	tk_beam = MeshInstance3D.new()
	tk_beam.mesh = MeshLib.cylinder(0.01, 1.0, 5)
	tk_beam.material_override = MeshLib.mat_alpha(Color(0.4, 0.8, 1.0, 0.45))
	tk_beam.visible = false
	tk_beam.top_level = true
	add_child(tk_beam)
	tk_halo = MeshInstance3D.new()
	tk_halo.mesh = MeshLib.sphere(0.5, 10, 6)
	tk_halo.material_override = MeshLib.mat_alpha(Color(0.4, 0.8, 1.0, 0.18))
	tk_halo.visible = false
	tk_halo.top_level = true
	add_child(tk_halo)
	tk_hum = Game.sfx.make_loop_player("tk_hum", self, -10.0)
	push_ring = MeshInstance3D.new()
	push_ring.mesh = MeshLib.sphere(1.0, 12, 6)
	var ring_m := MeshLib.mat_alpha(Color(0.6, 0.9, 1.0, 0.3)).duplicate() as StandardMaterial3D
	push_ring.material_override = ring_m
	push_ring.visible = false
	push_ring.top_level = true
	add_child(push_ring)
	last_pos = global_position
	last_basis = global_transform.basis

# ---------------------------------------------------------------- hand model
# Skinned hand: bone 0 = palm, then 3 bones per finger (index, middle, ring,
# pinky) and 3 for the thumb. The palm faces the other hand (-X for the right
# hand), knuckles point forward (-Z), fingers curl towards the palm.
var hand_skel: Skeleton3D
var curl_index := 0.0
var curl_grip := 0.0
var curl_thumb := 0.0
const FINGERS := [
	# base (x, y, z), segment lengths, radius
	[Vector3(0.0, 0.03, -0.035), [0.044, 0.026, 0.022], 0.0095],
	[Vector3(0.0, 0.009, -0.038), [0.048, 0.03, 0.024], 0.0098],
	[Vector3(0.0, -0.012, -0.035), [0.044, 0.028, 0.022], 0.0092],
	[Vector3(0.0, -0.031, -0.028), [0.036, 0.022, 0.019], 0.0082],
]
static var _hand_cache: Dictionary = {}

static func _hand_rest(side_s: float) -> Array:
	# returns [bone_global_rest_positions, parent indices]
	var pos: Array[Vector3] = [Vector3.ZERO]
	var parent: Array[int] = [-1]
	for f in FINGERS:
		var b: Vector3 = f[0]
		b.x *= side_s
		var seg: Array = f[1]
		var z := b.z
		for k in 3:
			pos.append(Vector3(b.x, b.y, z))
			parent.append(0 if k == 0 else pos.size() - 2)
			z -= seg[k]
	var tb := Vector3(-0.022 * side_s, 0.032, 0.022)
	var dirs := [Vector3(-0.012 * side_s, 0.006, -0.034), Vector3(-0.004 * side_s, 0.004, -0.03), Vector3(0.0, 0.002, -0.024)]
	var tp := tb
	for k in 3:
		pos.append(tp)
		parent.append(0 if k == 0 else pos.size() - 2)
		tp += dirs[k]
	return [pos, parent]

static func _hand_geo(side_s: float) -> Dictionary:
	var key := side_s
	if _hand_cache.has(key):
		return _hand_cache[key]
	var g := Geo.new()
	var skin := Color(0.86, 0.68, 0.55)
	var sleeve := Color(0.1, 0.1, 0.11)
	var rest := _hand_rest(side_s)
	var pos: Array[Vector3] = rest[0]
	g.bone = 0
	g.mat(skin, 0.55).rbox(Vector3(-0.002 * side_s, 0.0, 0.0), Vector3(0.03, 0.082, 0.085), 0.016, 2)
	g.mat(skin, 0.55).capsule(Vector3(0, -0.002, 0.04), Vector3(0, -0.002, 0.07), 0.026, 0.024, 10, 1)
	g.mat(sleeve, 0.85).capsule(Vector3(0, -0.002, 0.075), Vector3(0, -0.004, 0.17), 0.038, 0.042, 12, 2)
	var bi := 1
	for f in FINGERS:
		var seg: Array = f[1]
		var r: float = f[2]
		for k in 3:
			g.bone = bi
			var a: Vector3 = pos[bi]
			var b := a + Vector3(0, 0, -seg[k])
			g.mat(skin, 0.55).capsule(a, b, r * (1.0 - k * 0.08), r * (0.95 - k * 0.1), 8, 2)
			bi += 1
	for k in 3:
		g.bone = bi
		var a: Vector3 = pos[bi]
		var b: Vector3 = pos[bi + 1] if k < 2 else a + Vector3(0.0, 0.002, -0.024)
		g.mat(skin, 0.55).capsule(a, b, 0.012 - k * 0.0012, 0.0105 - k * 0.0012, 8, 2)
		bi += 1
	var mesh := g.mesh({}, true)
	var sk := Skin.new()
	for b in pos.size():
		sk.add_bind(b, Transform3D(Basis(), -pos[b]))
	var res := {"mesh": mesh, "skin": sk, "pos": pos, "parent": rest[1]}
	_hand_cache[key] = res
	return res

func _build_hand() -> void:
	var side_s := 1.0 if side == "right" else -1.0
	var hg := _hand_geo(side_s)
	hand_mesh = Node3D.new()
	hand_mesh.rotation_degrees = Vector3(-25, 0, 0)
	hand_mesh.position = Vector3(0, -0.035, 0.065)
	add_child(hand_mesh)
	hand_skel = Skeleton3D.new()
	var pos: Array[Vector3] = hg["pos"]
	var parent: Array[int] = hg["parent"]
	for b in pos.size():
		hand_skel.add_bone("b%d" % b)
	for b in pos.size():
		hand_skel.set_bone_parent(b, parent[b])
		var pp: Vector3 = pos[parent[b]] if parent[b] >= 0 else Vector3.ZERO
		hand_skel.set_bone_rest(b, Transform3D(Basis(), pos[b] - pp))
	hand_skel.reset_bone_poses()
	hand_mesh.add_child(hand_skel)
	var mi := MeshInstance3D.new()
	mi.mesh = hg["mesh"]
	mi.skin = hg["skin"]
	mi.material_override = MeshLib.atlas()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_skel.add_child(mi)
	mi.skeleton = mi.get_path_to(hand_skel)

## Curl the fingers from the controller (index = trigger, others = grip).
func _pose_fingers(delta: float) -> void:
	var holding := held != null
	var t_index := trig() if not (held is Weapon and not (held as Weapon).is_gun()) else 1.0
	var t_grip := 1.0 if (grip() or holding) else (0.15 if tk_target else 0.0)
	if tk_target != null:
		t_index = 0.2
		t_grip = 0.25
	if held is Weapon and (held as Weapon).is_gun():
		t_index = 0.35 + trig() * 0.5
	curl_index = lerpf(curl_index, t_index, 18.0 * delta)
	curl_grip = lerpf(curl_grip, t_grip, 18.0 * delta)
	curl_thumb = lerpf(curl_thumb, maxf(t_grip, t_index * 0.5), 18.0 * delta)
	var side_s := 1.0 if side == "right" else -1.0
	var b := 1
	for f in 4:
		var c := curl_index if f == 0 else curl_grip
		for k in 3:
			var ang: float = c * [1.35, 1.6, 1.0][k] + 0.08
			hand_skel.set_bone_pose_rotation(b, Quaternion(Vector3.UP, ang * side_s))
			b += 1
	for k in 3:
		var ang: float = curl_thumb * [0.5, 0.7, 0.6][k]
		hand_skel.set_bone_pose_rotation(b, Quaternion(Vector3(0.3, 1.0, 0.0).normalized(), ang * side_s))
		b += 1

func haptic(amplitude: float, duration: float) -> void:
	if not Game.desktop_mode:
		trigger_haptic_pulse("haptic", 0.0, clampf(amplitude, 0.0, 1.0), duration, 0.0)

# ---------------------------------------------------------------- inputs
func trig() -> float:
	return sim_trigger if Game.desktop_mode else get_float("trigger")

func grip() -> bool:
	return sim_grip if Game.desktop_mode else (get_float("grip") > 0.6 or is_button_pressed("grip_click"))

func click() -> bool:
	return sim_click if Game.desktop_mode else is_button_pressed("primary_click")

func stick() -> Vector2:
	return sim_stick if Game.desktop_mode else get_vector2("primary")

func aim_dir() -> Vector3:
	return -global_transform.basis.z

func is_holding_gun() -> bool:
	return held is Weapon and (held as Weapon).is_gun()

func is_holding_weapon() -> bool:
	return held is Weapon

func is_tk_active() -> bool:
	return tk_target != null

# ---------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	# track hand velocity
	var dt := maxf(delta, 0.0001)
	var v := (global_position - last_pos) / dt
	velocity = velocity.lerp(v, 0.55)
	var db := global_transform.basis * last_basis.inverse()
	var q := db.get_rotation_quaternion()
	var ang := q.get_angle()
	var axis := q.get_axis() if ang > 0.0001 else Vector3.ZERO
	if ang > PI:
		ang -= TAU
	ang_velocity = ang_velocity.lerp(axis * ang / dt, 0.55)
	last_pos = global_position
	last_basis = global_transform.basis
	punch_cd -= delta
	push_cd -= delta
	if push_t >= 0.0:
		push_t += delta
		var s := 0.3 + push_t * 14.0
		push_ring.scale = Vector3(s, s, s)
		(push_ring.material_override as StandardMaterial3D).albedo_color = Color(0.6, 0.9, 1.0, clampf(0.35 - push_t * 1.2, 0.0, 0.35))
		if push_t > 0.3:
			push_t = -1.0
			push_ring.visible = false
	if player and player.get("dead"):
		return
	var in_car: bool = player != null and player.get("car") != null
	var g := grip()
	var t := trig()
	var c := click()
	# --- grip: grab / release
	if g and not grip_prev:
		if held == null:
			if tk_target != null:
				tk_pull = true
			elif not (in_car and side == "right"):
				try_grab()
	elif not g and grip_prev:
		if held != null:
			release()
		tk_pull = false
	grip_prev = g
	# --- trigger: fire or telekinesis
	if held is Weapon:
		(held as Weapon).set_trigger(t > 0.5 and not (in_car and side == "right"))
	elif held == null and not in_car:
		if t > 0.6 and tk_target == null and not trigger_prev:
			tk_try_grab()
		elif t < 0.4 and tk_target != null:
			tk_release()
	elif in_car and tk_target != null:
		tk_release()
	trigger_prev = t > 0.6
	# --- stick click: force push
	if c and not click_prev and push_cd <= 0.0:
		force_push()
	click_prev = c
	# --- holding / telekinesis update
	if held is RigidBody3D:
		_update_hold(delta)
	if tk_target != null:
		_update_tk(delta)
	# --- punching
	if held == null and tk_target == null and velocity.length() > 2.6 and punch_cd <= 0.0:
		_try_punch()
	_pose_fingers(delta)

# ---------------------------------------------------------------- punching
func _try_punch() -> void:
	var own_car: Node = player.get("car") if player else null
	for body in grab_area.get_overlapping_bodies():
		if body == player or body == own_car:
			continue
		var target := Game.hittable_of(body)
		var speed := velocity.length()
		var pos := global_position + aim_dir() * 0.05
		if target != null:
			var part := ""
			if body.has_meta("part"):
				part = body.get_meta("part")
			var dmg := speed * 9.0            # super strength
			target.take_hit(dmg, velocity * 16.0 + Vector3.UP * 20.0, pos, part, "punch")
			punch_cd = 0.28
			haptic(1.0, 0.1)
			Game.sfx.play("punch", pos, 2.0)
			return
		elif body is RigidBody3D:
			body.apply_central_impulse(velocity * 4.0)
			punch_cd = 0.2
			haptic(0.5, 0.06)
			Game.sfx.play("thud", pos, -6.0)
			return

# ---------------------------------------------------------------- grabbing
func try_grab() -> void:
	var best: Node = null
	var best_d := INF
	var own_car: Node = player.get("car") if player else null
	for body in grab_area.get_overlapping_bodies():
		if body == player or body == own_car:
			continue
		var d := body.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = body
	if best == null:
		return
	grab_body(best)

func grab_body(body: Node) -> void:
	if body is Weapon:
		_grab_weapon(body as Weapon)
	elif body is Ped:
		var ped := body as Ped
		if ped.state == Ped.State.DEAD and ped.ragdoll == null:
			return
		ped.go_ragdoll(Vector3.ZERO)
		if ped.ragdoll and is_instance_valid(ped.ragdoll):
			_hold_rigid(ped.ragdoll.nearest_body(global_position))
	elif body is Car:
		var car := body as Car
		if car.mode == Car.Mode.PLAYER:
			return
		if car.mode == Car.Mode.AI:
			car.mode = Car.Mode.PARKED
		_hold_rigid(car)
	elif body is RigidBody3D:
		_hold_rigid(body as RigidBody3D)

func _grab_weapon(w: Weapon) -> void:
	if w.held_by != null:
		var other := w.held_by
		if other is Hand:
			(other as Hand).release(false)
	held = w
	w.on_grab(self)
	haptic(0.4, 0.05)

func _hold_rigid(rb: RigidBody3D) -> void:
	held = rb
	rb.freeze = false
	rb.sleeping = false
	if rb.has_meta("ragdoll"):
		held_ragdoll = rb.get_meta("ragdoll")
		if is_instance_valid(held_ragdoll):
			held_ragdoll.held_count += 1
			held_ragdoll.unfreeze()
			if held_ragdoll.alive:
				Game.sfx.play("scream", rb.global_position, -4.0, Game.randf_range(0.9, 1.2))
	haptic(0.5, 0.08)
	Game.sfx.play("tk_grab", global_position, -10.0, 0.6)

func _update_hold(delta: float) -> void:
	var rb := held as RigidBody3D
	if not is_instance_valid(rb):
		held = null
		held_ragdoll = null
		return
	var target := global_position + aim_dir() * (0.9 if rb is Car else 0.08)
	var diff := target - rb.global_position
	var want := diff * 18.0
	if want.length() > 28.0:
		want = want.normalized() * 28.0
	rb.linear_velocity = want
	rb.angular_velocity *= 0.75
	if rb is Car:
		rb.angular_velocity = rb.angular_velocity.lerp(ang_velocity, 0.3)
	if diff.length() > 3.5:
		release()

func release(throw: bool = true) -> void:
	if held == null:
		return
	if held is Weapon:
		var w := held as Weapon
		w.on_release(velocity * 1.2, ang_velocity)
	elif held is RigidBody3D:
		var rb := held as RigidBody3D
		if is_instance_valid(rb):
			rb.linear_velocity = velocity * (2.6 if throw else 1.0)   # super strength throw
			if velocity.length() > 2.0 and throw:
				Game.sfx.play("whoosh", global_position, -6.0)
		if held_ragdoll and is_instance_valid(held_ragdoll):
			held_ragdoll.held_count = maxi(0, held_ragdoll.held_count - 1)
		held_ragdoll = null
	held = null

# ---------------------------------------------------------------- telekinesis
func tk_try_grab() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from + aim_dir() * 45.0
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.mask([Game.L_NPC, Game.L_RAGDOLL, Game.L_PROP, Game.L_CAR, Game.L_WORLD]), exclude)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return
	var col: Node = r["collider"]
	var rb: RigidBody3D = null
	if col is Ped:
		var ped := col as Ped
		if ped.state == Ped.State.DEAD and ped.ragdoll == null:
			return
		ped.go_ragdoll(Vector3(0, 40, 0))
		if ped.ragdoll and is_instance_valid(ped.ragdoll):
			rb = ped.ragdoll.nearest_body(r["position"])
	elif col is Car:
		var car := col as Car
		if car.mode == Car.Mode.PLAYER:
			return
		if car.mode == Car.Mode.AI:
			car.mode = Car.Mode.PARKED
		rb = car
	elif col is RigidBody3D:
		rb = col
	if rb == null:
		return
	tk_target = rb
	tk_dist = clampf(from.distance_to(rb.global_position), 1.2, 9.0)
	tk_pull = false
	rb.freeze = false
	rb.sleeping = false
	if rb.has_meta("ragdoll"):
		tk_ragdoll = rb.get_meta("ragdoll")
		if is_instance_valid(tk_ragdoll):
			tk_ragdoll.held_count += 1
			tk_ragdoll.unfreeze()
			if tk_ragdoll.alive:
				Game.sfx.play("scream", rb.global_position, -2.0, Game.randf_range(0.9, 1.25))
	tk_beam.visible = true
	tk_halo.visible = true
	tk_hum.play()
	Game.sfx.play("tk_grab", global_position, -6.0)
	haptic(0.6, 0.1)

func _update_tk(delta: float) -> void:
	var rb := tk_target
	if not is_instance_valid(rb):
		tk_release(false)
		return
	# stick adjusts distance; grip pulls it into the hand
	var s := stick()
	tk_dist = clampf(tk_dist + s.y * delta * 6.0, 0.6, 12.0)
	if tk_pull:
		tk_dist = maxf(0.3, tk_dist - delta * 10.0)
	var target := global_position + aim_dir() * tk_dist + Vector3(0, 0.1, 0)
	var diff := target - rb.global_position
	var want := diff * 10.0
	if want.length() > 30.0:
		want = want.normalized() * 30.0
	rb.linear_velocity = rb.linear_velocity.lerp(want, 0.6)
	rb.angular_velocity *= 0.9
	if rb is Car:
		rb.angular_velocity = rb.angular_velocity.lerp(Vector3(0, 0.6, 0), 0.05)
	# visuals
	var a := global_position + aim_dir() * 0.05
	var b := rb.global_position
	var d := b - a
	var len := d.length()
	if len > 0.05:
		var up := d / len
		var axis := Vector3.UP.cross(up)
		var basis := Basis()
		if axis.length() > 0.001:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
		tk_beam.global_transform = Transform3D(basis.scaled(Vector3(1, len, 1)), (a + b) * 0.5)
	var r := 1.1 if not (rb is Car) else 2.8
	tk_halo.global_transform = Transform3D(Basis().scaled(Vector3(r, r, r)), b)
	if Engine.get_physics_frames() % 12 == 0:
		haptic(0.15, 0.05)
	# pulled into the hand: convert to a hand hold / weapon grab
	if tk_pull and diff.length() < 0.7 and tk_dist <= 0.35:
		var body := rb
		tk_release(false)
		if body is Weapon:
			_grab_weapon(body as Weapon)
		elif not (body is Car):
			_hold_rigid(body)
		else:
			_hold_rigid(body)

func tk_release(throw: bool = true) -> void:
	var rb := tk_target
	tk_target = null
	tk_beam.visible = false
	tk_halo.visible = false
	tk_hum.stop()
	if is_instance_valid(rb) and throw:
		var hv := velocity.length()
		if hv > 1.6:
			rb.linear_velocity = velocity * 6.0 + aim_dir() * 6.0
			Game.sfx.play("whoosh", global_position, -2.0, 0.8)
			haptic(0.9, 0.15)
			if rb is Car:
				Game.add_score(10)
	if tk_ragdoll and is_instance_valid(tk_ragdoll):
		tk_ragdoll.held_count = maxi(0, tk_ragdoll.held_count - 1)
	tk_ragdoll = null
	tk_pull = false

# ---------------------------------------------------------------- force push
func force_push() -> void:
	push_cd = 1.3
	push_t = 0.0
	push_ring.visible = true
	push_ring.global_position = global_position + aim_dir() * 1.0
	var dir := aim_dir()
	var center := global_position + dir * 2.8
	Game.sfx.play("whoosh", global_position, 4.0, 0.6)
	haptic(1.0, 0.25)
	Game.cop_saw_player()
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = MeshLib.sphere_shape(4.5)
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = Game.mask([Game.L_NPC, Game.L_RAGDOLL, Game.L_PROP, Game.L_CAR])
	var hits := space.intersect_shape(q, 24)
	var seen: Dictionary = {}
	for h in hits:
		var col: Node = h["collider"]
		if col == null or col == player:
			continue
		var to_col: Vector3 = col.global_position - global_position
		if to_col.normalized().dot(dir) < 0.25:
			continue
		var falloff := clampf(1.0 - to_col.length() / 7.5, 0.25, 1.0)
		var push := (to_col.normalized() + dir).normalized() * 1.0 + Vector3.UP * 0.45
		if col is Ped:
			var ped := col as Ped
			if seen.has(ped.get_instance_id()):
				continue
			seen[ped.get_instance_id()] = true
			ped.take_hit(22.0 * falloff, push * 260.0 * falloff, ped.global_position + Vector3(0, 1.0, 0), "torso", "throw")
		elif col is Car:
			var car := col as Car
			if car.mode == Car.Mode.PLAYER:
				continue
			if car.mode == Car.Mode.AI:
				car.mode = Car.Mode.PARKED
			car.freeze = false
			car.apply_central_impulse(push * car.mass * 7.0 * falloff)
			car.apply_torque_impulse(Vector3(Game.randf_range(-1, 1), 0, Game.randf_range(-1, 1)) * car.mass * 2.0 * falloff)
			Game.sfx.play("clank", car.global_position, -2.0)
		elif col is RigidBody3D:
			var rb := col as RigidBody3D
			rb.freeze = false
			if rb.has_meta("ragdoll"):
				var rd: Ragdoll = rb.get_meta("ragdoll")
				if is_instance_valid(rd):
					rd.unfreeze()
			rb.apply_central_impulse(push * rb.mass * 9.0 * falloff)
	Game.panic(global_position, 25.0)
