class_name Ragdoll
extends Node3D
## Six-part physics ragdoll built from a pedestrian's mesh parts. Supports
## dismemberment (joint removal + stumps + blood), gibbing, freezing when at
## rest, and forwards hits to the owning pedestrian while it is still alive.

const PART_NAMES := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]
const MASSES := {"head": 4.0, "torso": 32.0, "arm_l": 4.0, "arm_r": 4.0, "leg_l": 9.0, "leg_r": 9.0}

var ped: Node3D                       # owning Ped (may be freed later)
var bodies: Dictionary = {}           # part -> RigidBody3D
var joints: Dictionary = {}           # part -> Joint3D (not for torso)
var meshes: Dictionary = {}           # part -> MeshInstance3D
var detached: Dictionary = {}         # part -> true
var drips: Array = []                 # [{node, time}]
var age := 0.0
var frozen := false
var held_count := 0                   # hands / telekinesis currently holding a part
var rest_time := 0.0
var alive := false
var last_blood := 0.0

static var count := 0

## Build the ragdoll from mesh instances currently placed in world space.
func setup(owner_ped: Node3D, part_meshes: Dictionary, shapes: Dictionary, is_alive: bool) -> void:
	ped = owner_ped
	alive = is_alive
	count += 1
	for part in PART_NAMES:
		var mi: MeshInstance3D = part_meshes[part]
		var body := RigidBody3D.new()
		body.name = part
		body.mass = MASSES[part]
		body.collision_layer = Game.bit(Game.L_RAGDOLL)
		body.collision_mask = Game.mask([Game.L_WORLD, Game.L_RAGDOLL, Game.L_CAR, Game.L_PROP])
		body.linear_damp = 0.25
		body.angular_damp = 2.5
		body.continuous_cd = true
		body.can_sleep = true
		body.set_meta("ragdoll", self)
		body.set_meta("part", part)
		var gt := mi.global_transform
		add_child(body)
		body.global_transform = gt
		var shape: Shape3D = shapes[part]
		MeshLib.collider(shape, Vector3.ZERO, Vector3.ZERO, body)
		mi.reparent(body, true)
		mi.transform = Transform3D.IDENTITY
		bodies[part] = body
		meshes[part] = mi
		if part == "head" or part == "torso":
			body.contact_monitor = true
			body.max_contacts_reported = 2
			body.body_entered.connect(_on_part_contact.bind(part))
	_make_joint("head", Vector3(0, 0.31, 0), 40.0)
	_make_joint("arm_l", Vector3(-0.25, 0.26, 0), 75.0)
	_make_joint("arm_r", Vector3(0.25, 0.26, 0), 75.0)
	_make_joint("leg_l", Vector3(-0.1, -0.29, 0), 55.0)
	_make_joint("leg_r", Vector3(0.1, -0.29, 0), 55.0)
	if Game.gore:
		Game.gore.register_blob(bodies["torso"], 1.4)

func _make_joint(part: String, torso_local: Vector3, swing_deg: float) -> void:
	var torso: RigidBody3D = bodies["torso"]
	var j := ConeTwistJoint3D.new()
	add_child(j)
	var basis := Basis(Vector3.BACK, -PI / 2.0)   # twist axis (X) points down the limb
	if part == "head":
		basis = Basis(Vector3.BACK, PI / 2.0)
	j.global_transform = Transform3D(torso.global_transform.basis * basis, torso.global_transform * torso_local)
	j.node_a = j.get_path_to(torso)
	j.node_b = j.get_path_to(bodies[part])
	j.swing_span = deg_to_rad(swing_deg)
	j.twist_span = deg_to_rad(35.0)
	j.exclude_nodes_from_collision = true
	joints[part] = j

func torso() -> RigidBody3D:
	return bodies["torso"]

func part_of(body: Node) -> String:
	if body and body.has_meta("part"):
		return body.get_meta("part")
	return "torso"

func apply_impulse_to(part: String, impulse: Vector3, pos: Vector3 = Vector3.INF) -> void:
	var b: RigidBody3D = bodies.get(part, null)
	if b == null or not is_instance_valid(b):
		b = bodies["torso"]
	unfreeze()
	if pos == Vector3.INF:
		b.apply_central_impulse(impulse)
	else:
		b.apply_impulse(impulse, pos - b.global_position)

func unfreeze() -> void:
	if not frozen:
		return
	frozen = false
	for b in bodies.values():
		if is_instance_valid(b):
			b.freeze = false
	age = minf(age, 2.0)
	rest_time = 0.0

func freeze_all() -> void:
	frozen = true
	for b in bodies.values():
		if is_instance_valid(b):
			b.freeze = true

## Called by hands / weapons / bullets. Forwards damage to the pedestrian.
func take_hit(dmg: float, impulse: Vector3, pos: Vector3, part: String, kind: String) -> void:
	if not bodies.has(part):
		part = "torso"
	apply_impulse_to(part, impulse, pos)
	Game.gore.spray(pos, impulse.normalized() + Vector3.UP * 0.5, clampf(dmg / 25.0, 0.6, 2.0))
	if kind == "sharp" and not detached.has(part) and part != "torso" and dmg >= 20.0:
		dismember(part, impulse * 0.6)
	elif part == "head" and dmg >= 55.0 and not detached.has("head"):
		pop_head(impulse)
	elif kind in ["punch", "melee"] and dmg >= 30.0 and Game.rng.randf() < 0.25 and part != "torso" and not detached.has(part):
		dismember(part, impulse * 0.5)
	Game.sfx.play("squish" if kind != "punch" else "punch", pos, -4.0)
	if alive and ped and is_instance_valid(ped):
		ped.ragdoll_damage(dmg, kind)

## Separate a limb or the head from the torso.
func dismember(part: String, impulse: Vector3 = Vector3.ZERO) -> void:
	if part == "torso" or detached.has(part) or not joints.has(part):
		return
	var j: Joint3D = joints[part]
	j.queue_free()
	joints.erase(part)
	detached[part] = true
	var b: RigidBody3D = bodies[part]
	unfreeze()
	b.apply_central_impulse(impulse + Vector3(Game.randf_range(-1, 1), 2.5, Game.randf_range(-1, 1)) * b.mass)
	b.angular_velocity = Vector3(Game.randf_range(-6, 6), Game.randf_range(-6, 6), Game.randf_range(-6, 6))
	# Stumps: bone + flesh disc on both ends.
	var torso_b: RigidBody3D = bodies["torso"]
	var socket := _socket_local(part)
	_add_stump(torso_b, socket, part != "head")
	_add_stump(b, _limb_top_local(part), true)
	Game.gore.burst(b.global_position, 0.8)
	Game.gore.spray(torso_b.global_transform * socket, Vector3.UP, 1.5)
	Game.sfx.play("crack", b.global_position, 2.0)
	Game.sfx.play("splat", b.global_position, 0.0)
	_add_drip(torso_b, socket, 6.0)
	_add_drip(b, _limb_top_local(part), 4.0)
	if alive and ped and is_instance_valid(ped):
		ped.ragdoll_damage(999.0, "sharp")
	Game.add_score(50)

## Head explodes into mist (shotgun / crushing blows).
func pop_head(impulse: Vector3 = Vector3.ZERO) -> void:
	if detached.has("head"):
		return
	var head: RigidBody3D = bodies["head"]
	var pos := head.global_position
	Game.gore.burst(pos, 1.4)
	Game.gore.burst(pos + Vector3(0, 0.2, 0), 1.0)
	Game.sfx.play("splat", pos, 3.0, 0.8)
	Game.sfx.play("crack", pos, 3.0)
	# Shrink the head to nothing and detach what's left.
	dismember("head", impulse)
	head.visible = false
	head.collision_layer = 0
	head.collision_mask = 0
	head.freeze = true
	_add_drip(bodies["torso"], _socket_local("head"), 8.0)
	Game.add_score(100)

## Everything comes apart (explosions, high-speed car impacts).
func gib() -> void:
	var pos: Vector3 = bodies["torso"].global_position
	Game.gore.burst(pos, 2.0)
	Game.gore.burst(pos + Vector3(0, 0.5, 0), 1.5)
	for part in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		if not detached.has(part):
			dismember(part, Vector3(Game.randf_range(-6, 6), Game.randf_range(3, 9), Game.randf_range(-6, 6)) * 3.0)
	pop_head(Vector3(0, 8, 0))
	Game.sfx.play("explosion", pos, -12.0, 1.6)
	Game.add_score(150)

func _socket_local(part: String) -> Vector3:
	match part:
		"head":
			return Vector3(0, 0.28, 0)
		"arm_l":
			return Vector3(-0.2, 0.22, 0)
		"arm_r":
			return Vector3(0.2, 0.22, 0)
		"leg_l":
			return Vector3(-0.1, -0.28, 0)
		"leg_r":
			return Vector3(0.1, -0.28, 0)
	return Vector3.ZERO

func _limb_top_local(part: String) -> Vector3:
	match part:
		"head":
			return Vector3(0, -0.1, 0)
		"arm_l", "arm_r":
			return Vector3(0, 0.3, 0)
		"leg_l", "leg_r":
			return Vector3(0, 0.42, 0)
	return Vector3.ZERO

func _add_stump(body: RigidBody3D, local: Vector3, with_bone: bool) -> void:
	var flesh := MeshLib.inst(MeshLib.sphere(0.075, 6, 4), MeshLib.mat(MeshLib.BLOOD, 0.3), local, Vector3.ZERO, body)
	flesh.scale = Vector3(1.0, 0.5, 1.0)
	if with_bone:
		MeshLib.inst(MeshLib.cylinder(0.02, 0.1, 5), MeshLib.mat(MeshLib.BONE, 0.6), local, Vector3.ZERO, body)

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
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, -9.8, 0)
	p.position = local
	p.local_coords = false
	body.add_child(p)
	drips.append({"node": p, "time": seconds, "body": body})

func _on_part_contact(other: Node, part: String) -> void:
	var b: RigidBody3D = bodies[part]
	var speed := b.linear_velocity.length()
	if other is RigidBody3D:
		speed = (b.linear_velocity - (other as RigidBody3D).linear_velocity).length()
	if speed < 6.0 or age < 0.05:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_blood < 0.15:
		return
	last_blood = now
	var pos := b.global_position
	Game.gore.spray(pos, Vector3.UP, clampf(speed / 10.0, 0.6, 2.0))
	if speed > 12.0:
		Game.sfx.play("crack", pos, 0.0)
		if part == "head" and speed > 16.0:
			pop_head(b.linear_velocity * 0.2)
	else:
		Game.sfx.play("thud", pos, -3.0)
	if alive and ped and is_instance_valid(ped):
		ped.ragdoll_damage(speed * 4.0, "throw")
	if other is Node3D and other.has_method("take_hit") and other != ped and speed > 8.0:
		other.take_hit(speed * 2.0, b.linear_velocity * 0.3, pos, "torso", "throw")

func _physics_process(delta: float) -> void:
	age += delta
	# blood drips expire
	for i in range(drips.size() - 1, -1, -1):
		drips[i]["time"] -= delta
		if drips[i]["time"] <= 0.0:
			var n: CPUParticles3D = drips[i]["node"]
			n.emitting = false
			n.queue_free()
			drips.remove_at(i)
	if frozen or held_count > 0:
		rest_time = 0.0
		return
	var t: RigidBody3D = bodies["torso"]
	if t.linear_velocity.length() < 0.35:
		rest_time += delta
	else:
		rest_time = 0.0
	if not alive and ((rest_time > 3.0 and age > 4.0) or age > 25.0):
		freeze_all()
		Game.gore.decal(t.global_position, 2.2)

func _exit_tree() -> void:
	count -= 1

## Returns parts to the pedestrian (used when a living ragdoll stands up).
func release_parts() -> Dictionary:
	var out: Dictionary = {}
	for part in PART_NAMES:
		var mi: MeshInstance3D = meshes[part]
		if is_instance_valid(mi):
			out[part] = mi
	return out
