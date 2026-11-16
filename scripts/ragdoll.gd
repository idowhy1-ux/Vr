class_name Ragdoll
extends Node3D
## 11-body physics ragdoll that drives a pedestrian's skinned mesh. Any joint can
## be severed (head, shoulders, elbows, hips, knees, waist), heads can be popped
## and bodies gibbed. Bodies freeze when at rest. Hits are forwarded to the
## owning pedestrian while it is still alive.

const B = preload("res://scripts/body_gen.gd")

var ped: Node3D
var skel: Skeleton3D
var female := false
var bodies: Array[RigidBody3D] = []
var joints: Array = []                # per bone: Joint3D to its parent (or null)
var severed: Dictionary = {}          # bone -> true (joint to parent broken)
var hidden: Dictionary = {}           # bone -> true (mesh collapsed, e.g. popped head)
var drips: Array = []
var age := 0.0
var frozen := false
var held_count := 0
var rest_time := 0.0
var alive := false
var last_blood := 0.0
var wounds := 0

static var count := 0

func setup(owner_ped: Node3D, skeleton: Skeleton3D, is_female: bool, is_alive: bool) -> void:
	ped = owner_ped
	skel = skeleton
	female = is_female
	alive = is_alive
	count += 1
	joints.resize(B.BONES.size())
	for b in B.BONES.size():
		var body := RigidBody3D.new()
		body.name = B.BONES[b]
		body.mass = B.MASS[b]
		body.collision_layer = Game.bit(Game.L_RAGDOLL)
		body.collision_mask = Game.mask([Game.L_WORLD, Game.L_RAGDOLL, Game.L_CAR, Game.L_PROP])
		body.linear_damp = 0.2
		body.angular_damp = 2.0
		body.continuous_cd = b == B.B_HEAD or b == B.B_CHEST
		body.can_sleep = true
		body.set_meta("ragdoll", self)
		body.set_meta("part", B.BONES[b])
		body.set_meta("bone", b)
		var sh: Array = B.part_shape(b, female)
		MeshLib.collider(sh[0], sh[1], Vector3.ZERO, body)
		if b == B.B_SHIN_L or b == B.B_SHIN_R:
			MeshLib.collider(MeshLib.box_shape(Vector3(0.1, 0.07, 0.25)), Vector3(0, -0.45, -0.05), Vector3.ZERO, body)
		add_child(body)
		body.global_transform = skel.global_transform * skel.get_bone_global_pose(b)
		bodies.append(body)
		if b in [B.B_HEAD, B.B_CHEST, B.B_PELVIS]:
			body.contact_monitor = true
			body.max_contacts_reported = 2
			body.body_entered.connect(_on_part_contact.bind(b))
	for b in B.BONES.size():
		var p: int = B.PARENT[b]
		if p < 0:
			joints[b] = null
			continue
		joints[b] = _make_joint(p, b)
	if Game.gore:
		Game.gore.register_blob(bodies[B.B_PELVIS], 1.2)

func _make_joint(p: int, c: int) -> Joint3D:
	var parent := bodies[p]
	var child := bodies[c]
	var at := child.global_position
	var j: Joint3D
	var pb := parent.global_transform.basis
	if c in [B.B_FORE_L, B.B_FORE_R, B.B_SHIN_L, B.B_SHIN_R]:
		# hinge around the body's sideways axis (local X); hinge axis = joint local Z
		var h := HingeJoint3D.new()
		h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		if c == B.B_FORE_L or c == B.B_FORE_R:
			h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-145.0))
			h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(2.0))
		else:
			h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-2.0))
			h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(140.0))
		j = h
		add_child(j)
		j.global_transform = Transform3D(pb * Basis(Vector3.UP, PI / 2.0), at)
	else:
		var ct := ConeTwistJoint3D.new()
		var swing := 30.0
		var twist := 20.0
		var basis := pb * Basis(Vector3.BACK, -PI / 2.0)   # twist axis (X) points down
		match c:
			B.B_CHEST:
				swing = 25.0
				twist = 20.0
				basis = pb * Basis(Vector3.BACK, PI / 2.0)
			B.B_HEAD:
				swing = 40.0
				twist = 45.0
				basis = pb * Basis(Vector3.BACK, PI / 2.0)
			B.B_ARM_L, B.B_ARM_R:
				swing = 80.0
				twist = 40.0
			B.B_THIGH_L, B.B_THIGH_R:
				swing = 55.0
				twist = 20.0
		ct.swing_span = deg_to_rad(swing)
		ct.twist_span = deg_to_rad(twist)
		j = ct
		add_child(j)
		j.global_transform = Transform3D(basis, at)
	j.node_a = j.get_path_to(parent)
	j.node_b = j.get_path_to(child)
	j.exclude_nodes_from_collision = true
	return j

func torso() -> RigidBody3D:
	return bodies[B.B_CHEST]

func pelvis() -> RigidBody3D:
	return bodies[B.B_PELVIS]

func body_of(part: String) -> RigidBody3D:
	var b := B.BONES.find(part)
	if b < 0:
		return bodies[B.B_CHEST]
	return bodies[b]

func nearest_body(pos: Vector3) -> RigidBody3D:
	var best := bodies[B.B_CHEST]
	var bd := INF
	for b in bodies.size():
		if hidden.has(b):
			continue
		var body := bodies[b]
		var sh: Array = B.part_shape(b, female)
		var d := (body.global_transform * (sh[1] as Vector3)).distance_to(pos)
		if d < bd:
			bd = d
			best = body
	return best

func apply_impulse_to(part: String, impulse: Vector3, pos: Vector3 = Vector3.INF) -> void:
	var body := body_of(part)
	unfreeze()
	if pos == Vector3.INF:
		body.apply_central_impulse(impulse)
	else:
		body.apply_impulse(impulse, pos - body.global_position)

func unfreeze() -> void:
	if not frozen:
		return
	frozen = false
	for b in bodies:
		b.freeze = false
	age = minf(age, 2.0)
	rest_time = 0.0

func freeze_all() -> void:
	frozen = true
	for b in bodies:
		b.freeze = true

# ---------------------------------------------------------------- damage
func take_hit(dmg: float, impulse: Vector3, pos: Vector3, part: String, kind: String) -> void:
	var b := B.BONES.find(part)
	if b < 0:
		b = B.BONES.find(_part_near(pos))
		part = B.BONES[b]
	apply_impulse_to(part, impulse, pos)
	Game.gore.spray(pos, impulse.normalized() + Vector3.UP * 0.5, clampf(dmg / 25.0, 0.6, 2.0))
	add_wound(bodies[b], pos)
	var limb := b not in [B.B_CHEST, B.B_PELVIS, B.B_HEAD]
	if kind == "sharp" and dmg >= 20.0 and (limb or b == B.B_HEAD) and Game.rng.randf() < 0.75:
		dismember(b, impulse * 0.6)
	elif kind == "sharp" and dmg >= 55.0 and b == B.B_PELVIS:
		dismember(B.B_CHEST, impulse * 0.4)
	elif b == B.B_HEAD and dmg >= 55.0:
		pop_head(impulse)
	elif kind in ["punch", "melee", "bullet"] and dmg >= 30.0 and limb and Game.rng.randf() < 0.2:
		dismember(b, impulse * 0.5)
	Game.sfx.play("squish" if kind != "punch" else "punch", pos, -4.0)
	if alive and ped and is_instance_valid(ped):
		ped.ragdoll_damage(dmg, kind)

func _part_near(pos: Vector3) -> String:
	return String(nearest_body(pos).get_meta("part"))

## Small blood wound stuck to a body part at the hit point.
func add_wound(body: RigidBody3D, pos: Vector3) -> void:
	if wounds >= 10 or not is_instance_valid(body):
		return
	wounds += 1
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.sphere(0.035, 6, 4)
	mi.material_override = Game.gore.wound_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(1.0, 1.0, 0.45)
	var inward := body.global_position - pos
	if inward.length() > 0.01 and absf(inward.normalized().dot(Vector3.UP)) < 0.98:
		mi.look_at(body.global_position, Vector3.UP, true)

## Break the joint between bone b and its parent.
func dismember(b: int, impulse: Vector3 = Vector3.ZERO) -> void:
	if b == B.B_PELVIS or severed.has(b) or joints[b] == null:
		return
	var j: Joint3D = joints[b]
	j.queue_free()
	joints[b] = null
	severed[b] = true
	var body := bodies[b]
	var parent := bodies[B.PARENT[b]]
	unfreeze()
	body.apply_central_impulse(impulse + Vector3(Game.randf_range(-1, 1), 2.5, Game.randf_range(-1, 1)) * body.mass)
	body.angular_velocity += Vector3(Game.randf_range(-6, 6), Game.randf_range(-6, 6), Game.randf_range(-6, 6))
	var at := body.global_position
	# stumps: flesh + bone on both sides of the cut
	_add_stump(parent, parent.to_local(at), b != B.B_HEAD)
	_add_stump(body, Vector3.ZERO, true)
	Game.gore.burst(at, 0.8)
	Game.gore.spray(at, Vector3.UP, 1.6)
	Game.sfx.play("crack", at, 2.0)
	Game.sfx.play("splat", at, 0.0)
	_add_drip(parent, parent.to_local(at), 7.0)
	_add_drip(body, Vector3.ZERO, 4.0)
	if b == B.B_CHEST:
		Game.gore.burst(at, 1.6)
		_add_guts(parent, parent.to_local(at))
		_add_guts(body, Vector3.ZERO)
	if alive and ped and is_instance_valid(ped):
		ped.ragdoll_damage(999.0 if b in [B.B_HEAD, B.B_CHEST] else 60.0, "sharp")
	Game.add_score(50)

## Head bursts: the head mesh collapses and a bloody neck stump remains.
func pop_head(impulse: Vector3 = Vector3.ZERO) -> void:
	if hidden.has(B.B_HEAD):
		return
	var head := bodies[B.B_HEAD]
	var pos := head.global_transform * Vector3(0, 0.17, 0)
	Game.gore.burst(pos, 1.4)
	Game.gore.burst(pos + Vector3(0, 0.15, 0), 1.0)
	Game.sfx.play("splat", pos, 3.0, 0.8)
	Game.sfx.play("crack", pos, 3.0)
	hidden[B.B_HEAD] = true
	if not severed.has(B.B_HEAD) and joints[B.B_HEAD]:
		joints[B.B_HEAD].queue_free()
		joints[B.B_HEAD] = null
		severed[B.B_HEAD] = true
	head.collision_layer = 0
	head.collision_mask = 0
	head.freeze = true
	var chest := bodies[B.B_CHEST]
	var neck := chest.to_local(head.global_position)
	_add_stump(chest, neck, true)
	_add_drip(chest, neck, 9.0)
	_drive_skeleton()
	if alive and ped and is_instance_valid(ped):
		ped.ragdoll_damage(999.0, "sharp")
	Game.add_score(100)

## Everything comes apart (explosions, very fast car impacts).
func gib() -> void:
	var pos := bodies[B.B_CHEST].global_position
	Game.gore.burst(pos, 2.0)
	Game.gore.burst(pos + Vector3(0, 0.5, 0), 1.5)
	for b in [B.B_ARM_L, B.B_ARM_R, B.B_THIGH_L, B.B_THIGH_R, B.B_FORE_L, B.B_SHIN_R, B.B_CHEST]:
		if not severed.has(b):
			dismember(b, Vector3(Game.randf_range(-6, 6), Game.randf_range(3, 9), Game.randf_range(-6, 6)) * 3.0)
	pop_head(Vector3(0, 8, 0))
	Game.sfx.play("explosion", pos, -12.0, 1.6)
	Game.add_score(150)

func _add_stump(body: RigidBody3D, local: Vector3, with_bone: bool) -> void:
	var flesh := MeshLib.inst(MeshLib.sphere(0.06, 8, 5), Game.gore.flesh_mat, local, Vector3.ZERO, body)
	flesh.scale = Vector3(1.0, 0.55, 1.0)
	if with_bone:
		MeshLib.inst(MeshLib.cylinder(0.016, 0.09, 6), MeshLib.mat(MeshLib.BONE, 0.5), local, Vector3.ZERO, body)

func _add_guts(body: RigidBody3D, local: Vector3) -> void:
	for i in 4:
		var g := MeshLib.inst(MeshLib.capsule(0.03, 0.14, 6, 2), Game.gore.guts_mat, local + Vector3(Game.randf_range(-0.07, 0.07), Game.randf_range(-0.05, 0.05), Game.randf_range(-0.05, 0.05)), Vector3(Game.randf_range(0, 180), Game.randf_range(0, 180), 0), body)

func _add_drip(body: RigidBody3D, local: Vector3, seconds: float) -> void:
	var p := CPUParticles3D.new()
	p.mesh = MeshLib.sphere(0.025, 4, 3)
	p.material_override = Game.gore.blood_mat
	p.amount = 14
	p.lifetime = 0.8
	p.emitting = true
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -9.8, 0)
	p.position = local
	p.local_coords = false
	body.add_child(p)
	drips.append({"node": p, "time": seconds, "body": body, "next_decal": 0.3})

func _on_part_contact(other: Node, b: int) -> void:
	var body := bodies[b]
	var speed := body.linear_velocity.length()
	if other is RigidBody3D:
		speed = (body.linear_velocity - (other as RigidBody3D).linear_velocity).length()
	if speed < 6.0 or age < 0.05:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_blood < 0.15:
		return
	last_blood = now
	var pos := body.global_position
	Game.gore.spray(pos, Vector3.UP, clampf(speed / 10.0, 0.6, 2.0))
	Game.gore.decal(pos, clampf(speed / 8.0, 0.6, 2.0))
	if speed > 12.0:
		Game.sfx.play("crack", pos, 0.0)
		if b == B.B_HEAD and speed > 16.0:
			pop_head(body.linear_velocity * 0.2)
	else:
		Game.sfx.play("thud", pos, -3.0)
	if alive and ped and is_instance_valid(ped):
		ped.ragdoll_damage(speed * 4.0, "throw")
	if other is Node3D and other.has_method("take_hit") and other != ped and speed > 8.0:
		other.take_hit(speed * 2.0, body.linear_velocity * 0.3, pos, "", "throw")

# ---------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	age += delta
	for i in range(drips.size() - 1, -1, -1):
		var d: Dictionary = drips[i]
		d["time"] -= delta
		d["next_decal"] -= delta
		var n: CPUParticles3D = d["node"]
		if d["next_decal"] <= 0.0 and is_instance_valid(n):
			d["next_decal"] = 0.35
			Game.gore.decal(n.global_position, 0.35)
		if d["time"] <= 0.0:
			if is_instance_valid(n):
				n.emitting = false
				n.queue_free()
			drips.remove_at(i)
	if not frozen:
		_drive_skeleton()
	if frozen or held_count > 0:
		rest_time = 0.0
		return
	var t := bodies[B.B_PELVIS]
	if t.linear_velocity.length() < 0.35 and bodies[B.B_CHEST].linear_velocity.length() < 0.35:
		rest_time += delta
	else:
		rest_time = 0.0
	if not alive and ((rest_time > 3.0 and age > 4.0) or age > 25.0):
		_drive_skeleton()
		freeze_all()
		Game.gore.pool(t.global_position)

## Copies body transforms onto the skeleton bones (parents first).
func _drive_skeleton() -> void:
	if not is_instance_valid(skel):
		return
	var inv := skel.global_transform.affine_inverse()
	for b in bodies.size():
		var t := inv * bodies[b].global_transform
		if hidden.has(b):
			t.basis = t.basis.scaled(Vector3(0.001, 0.001, 0.001))
		skel.set_bone_global_pose(b, t)

func _exit_tree() -> void:
	count -= 1
