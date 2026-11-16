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
	pose = "grip"
	_build_hand()
	grab_area = Area3D.new()
	grab_area.collision_layer = 0
	grab_area.collision_mask = Game.mask([Game.L_NPC, Game.L_RAGDOLL, Game.L_PROP, Game.L_CAR])
	grab_area.monitoring = true
	grab_area.monitorable = false
	MeshLib.collider(MeshLib.sphere_shape(0.09), Vector3(0.015 * (1.0 if side == "right" else -1.0), -0.045, 0.0), Vector3.ZERO, grab_area)
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
# The node follows the controller's OpenXR *grip* pose: origin in the middle of
# the controller handle (where your palm closes), -Z running from pinky to
# thumb along the handle, -Y pointing out of the knuckles, palm facing +X on
# the left hand and -X on the right. The hand model is built in its own frame
# (palm facing -X for the right hand, fingers along -Z, index on +Y, wrist +Z)
# and rotated into grip space, so it wraps around the real controller.
#
# Skinned hand: bone 0 = palm, 1-12 = index/middle/ring/pinky (3 bones each),
# 13-15 = thumb (metacarpal, proximal, distal). Fingers follow the Touch
# controller: index = trigger (+ capacitive touch), the other three = grip,
# thumb = touching the stick or buttons.

var hand_skel: Skeleton3D
var curls := PackedFloat32Array([0.15, 0.15, 0.15, 0.15, 0.2])   # index, middle, ring, pinky, thumb
const FINGERS := [
	# knuckle position (model space), segment lengths, base radius, tip radius, splay
	[Vector3(0.0, 0.027, -0.046), [0.043, 0.025, 0.021], 0.0098, 0.0078, 0.07],
	[Vector3(0.0, 0.009, -0.049), [0.047, 0.029, 0.023], 0.0102, 0.008, 0.0],
	[Vector3(0.0, -0.009, -0.047), [0.044, 0.027, 0.022], 0.0096, 0.0076, -0.06],
	[Vector3(0.0, -0.026, -0.041), [0.035, 0.021, 0.019], 0.0085, 0.0068, -0.14],
]
const THUMB_BASE := Vector3(-0.007, 0.021, 0.036)
const THUMB_LEN := [0.044, 0.032, 0.027]
const THUMB_DIR := [Vector3(-0.33, 0.5, -0.8), Vector3(-0.28, 0.22, -0.93), Vector3(-0.22, 0.1, -0.97)]
const SKIN := Color(0.84, 0.66, 0.54)
const SKIN_PALM := Color(0.9, 0.73, 0.63)
const KNUCKLE := Color(0.83, 0.6, 0.52)
const NAIL := Color(0.94, 0.82, 0.78)
const SLEEVE := Color(0.11, 0.1, 0.1)
static var _hand_cache: Dictionary = {}

static func _thumb_dirs(side_s: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for d in THUMB_DIR:
		var v: Vector3 = d
		out.append(Vector3(v.x * side_s, v.y, v.z).normalized())
	return out

static func _hand_rest(side_s: float) -> Array:
	var pos: Array[Vector3] = [Vector3.ZERO]
	var parent: Array[int] = [-1]
	for f in FINGERS:
		var b: Vector3 = f[0]
		var seg: Array = f[1]
		var z := b.z
		for k in 3:
			pos.append(Vector3(b.x * side_s, b.y, z))
			parent.append(0 if k == 0 else pos.size() - 2)
			z -= seg[k]
	var dirs := _thumb_dirs(side_s)
	var tp := Vector3(THUMB_BASE.x * side_s, THUMB_BASE.y, THUMB_BASE.z)
	for k in 3:
		pos.append(tp)
		parent.append(0 if k == 0 else pos.size() - 2)
		tp += dirs[k] * THUMB_LEN[k]
	return [pos, parent]

## Tints the palm-facing side of the vertices added since `start`.
static func _palm_tint(g: Geo, start: int, side_s: float, palm_col: Color) -> void:
	var lc := palm_col.srgb_to_linear()
	for i in range(start, g.verts.size()):
		var x := g.verts[i].x * side_s
		if x < -0.004:
			var f := clampf((-x - 0.004) / 0.006, 0.0, 1.0)
			var c := g.cols[i]
			g.cols[i] = Color(lerpf(c.r, lc.r, f), lerpf(c.g, lc.g, f), lerpf(c.b, lc.b, f), c.a)

static func _hand_geo(side_s: float) -> Dictionary:
	var key := side_s
	if _hand_cache.has(key):
		return _hand_cache[key]
	var g := Geo.new()
	var rest := _hand_rest(side_s)
	var pos: Array[Vector3] = rest[0]
	var s := side_s
	# ---- palm: lofted from the wrist to the knuckles, thicker at the heel
	g.bone = 0
	var st := g.verts.size()
	var palm := [
		Geo.ring_xy(0.062, 0.0, 0.0175, 0.0255, 14, 2.3),
		Geo.ring_xy(0.045, 0.001, 0.0172, 0.03, 14, 2.4),
		Geo.ring_xy(0.02, 0.001, 0.0165, 0.037, 14, 2.5),
		Geo.ring_xy(-0.012, 0.0, 0.0152, 0.042, 14, 2.6),
		Geo.ring_xy(-0.036, -0.001, 0.0138, 0.0435, 14, 2.6),
		Geo.ring_xy(-0.05, -0.001, 0.0105, 0.039, 14, 2.3),
		Geo.ring_xy(-0.056, -0.001, 0.005, 0.03, 14, 2.0),
	]
	for r in palm:
		for i in (r as PackedVector3Array).size():
			r[i].x += 0.0015 * s   # slight cup: palm side flatter
	g.mat(SKIN, 0.55).loft(palm, true, true)
	# hypothenar (heel on the pinky side)
	g.mat(SKIN, 0.55).ellipsoid(Vector3(-0.006 * s, -0.026, 0.026), Vector3(0.011, 0.013, 0.03), 10, 6)
	_palm_tint(g, st, s, SKIN_PALM)
	# knuckles on the back of the hand
	for f in FINGERS:
		var b: Vector3 = f[0]
		g.mat(KNUCKLE, 0.5).ellipsoid(Vector3(0.0085 * s, b.y, b.z + 0.007), Vector3(0.0075, 0.0085, 0.009), 8, 5)
	# ---- fingers
	var bi := 1
	for f in FINGERS:
		var seg: Array = f[1]
		var r0: float = f[2]
		var r1: float = f[3]
		for k in 3:
			g.bone = bi
			var a: Vector3 = pos[bi]
			var b := a + Vector3(0, 0, -seg[k])
			var ra := lerpf(r0, r1, k / 3.0)
			var rb := lerpf(r0, r1, (k + 1) / 3.0)
			st = g.verts.size()
			g.mat(SKIN, 0.55).capsule(a, b, ra * (1.04 if k > 0 else 1.0), rb, 9, 2 if k == 2 else 1, 1.0, 0.85 if k == 2 else 1.0)
			_palm_tint(g, st, s, SKIN_PALM)
			if k == 2:
				# fingernail on the back of the fingertip
				g.mat(NAIL, 0.3).ellipsoid(Vector3(b.x + rb * 0.82 * s, b.y, b.z + 0.0075), Vector3(0.0022, rb * 0.72, 0.0078), 8, 4)
			else:
				# joint crease bulge
				g.mat(KNUCKLE, 0.55).ellipsoid(Vector3(b.x + rb * 0.35 * s, b.y, b.z), Vector3(rb * 0.85, rb * 1.02, rb * 0.75), 8, 4)
			bi += 1
	# ---- thumb (the thenar mound moves with the metacarpal)
	var dirs := _thumb_dirs(s)
	var tr := [0.0135, 0.0118, 0.0106, 0.0088]
	for k in 3:
		g.bone = bi
		var a: Vector3 = pos[bi]
		var b: Vector3 = a + dirs[k] * THUMB_LEN[k]
		st = g.verts.size()
		g.mat(SKIN, 0.55).capsule(a, b, tr[k], tr[k + 1], 9, 2 if k == 2 else 1, 1.0, 0.85 if k == 2 else 1.0)
		if k == 0:
			g.mat(SKIN, 0.55).ellipsoid(a.lerp(b, 0.45) + Vector3(-0.004 * s, -0.008, 0.004), Vector3(0.012, 0.016, 0.026), 10, 6)
		_palm_tint(g, st, s, SKIN_PALM)
		if k == 2:
			var back := dirs[k].cross(Vector3(0, 0, 1)).normalized() * -s
			if back.x * s < 0.0:
				back = -back
			g.mat(NAIL, 0.3).ellipsoid(b - dirs[k] * 0.0075 + back * tr[3] * 0.8, Vector3(0.0045, 0.0045, 0.008), 8, 4)
		bi += 1
	# ---- wrist and jacket sleeve (palm bone)
	g.bone = 0
	g.mat(SKIN, 0.55).loft([Geo.ring_xy(0.05, 0.0, 0.0185, 0.026, 12, 2.2), Geo.ring_xy(0.075, 0.0, 0.0195, 0.0255, 12, 2.2), Geo.ring_xy(0.095, 0.0, 0.021, 0.027, 12, 2.2)], false, true)
	g.mat(SLEEVE.lightened(0.05), 0.6).loft([Geo.ring_xy(0.08, 0.0, 0.026, 0.032, 14, 2.2), Geo.ring_xy(0.084, 0.0, 0.03, 0.036, 14, 2.2), Geo.ring_xy(0.098, 0.0, 0.031, 0.037, 14, 2.2)], true, false)
	g.mat(SLEEVE, 0.55).loft([Geo.ring_xy(0.098, 0.0, 0.031, 0.037, 14, 2.2), Geo.ring_xy(0.13, 0.0, 0.033, 0.039, 14, 2.2), Geo.ring_xy(0.17, 0.0, 0.035, 0.041, 14, 2.2)], false, true)
	var mesh := g.mesh({}, true)
	var sk := Skin.new()
	for b in pos.size():
		sk.add_bind(b, Transform3D(Basis(), -pos[b]))
	var res := {"mesh": mesh, "skin": sk, "pos": pos, "parent": rest[1]}
	_hand_cache[key] = res
	return res

## Hand model frame -> grip pose frame (see the comment above). A real fist
## holds the handle diagonally across the palm (from the heel of the hand to
## the base of the index finger), so the hand is tilted 45 degrees around the
## palm normal relative to the handle; the wrist then points back and down.
static func model_to_grip(side_s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-45.0)), Vector3(0.033 * side_s, 0.012, 0.004))

## Builds the visual hand (a Node3D holding the skeleton and skinned mesh).
static func make_visual(side_s: float) -> Node3D:
	var hg := _hand_geo(side_s)
	var root := Node3D.new()
	root.transform = model_to_grip(side_s)
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	var pos: Array[Vector3] = hg["pos"]
	var parent: Array[int] = hg["parent"]
	for b in pos.size():
		sk.add_bone("b%d" % b)
	for b in pos.size():
		sk.set_bone_parent(b, parent[b])
		var pp: Vector3 = pos[parent[b]] if parent[b] >= 0 else Vector3.ZERO
		sk.set_bone_rest(b, Transform3D(Basis(), pos[b] - pp))
	sk.reset_bone_poses()
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.mesh = hg["mesh"]
	mi.skin = hg["skin"]
	mi.material_override = MeshLib.atlas()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.5))
	sk.add_child(mi)
	mi.skeleton = mi.get_path_to(sk)
	return root

## Poses the fingers. c = [index, middle, ring, pinky, thumb] curl 0..1.
static func apply_pose(sk: Skeleton3D, side_s: float, c: PackedFloat32Array) -> void:
	var b := 1
	for f in 4:
		var curl: float = c[f]
		var splay: float = FINGERS[f][4] * (1.0 - curl * 0.8)
		var w := [1.35, 1.6, 1.0]
		var relax := [0.12, 0.2, 0.12]
		for k in 3:
			var ang: float = relax[k] + curl * w[k]
			var q := Quaternion(Vector3.UP, ang * side_s)
			if k == 0:
				q = q * Quaternion(Vector3.RIGHT, splay)
			sk.set_bone_pose_rotation(b, q)
			b += 1
	var dirs := _thumb_dirs(side_s)
	var ct: float = c[4]
	# metacarpal swings across the palm, the two joints curl
	var across := Vector3(-0.15 * side_s, -1.0, 0.25).normalized()
	for k in 3:
		var axis := dirs[k].cross(across).normalized()
		var ang: float = [0.35, 0.55, 0.7][k] * ct + [0.05, 0.1, 0.12][k]
		sk.set_bone_pose_rotation(b, Quaternion(axis, ang))
		b += 1

func _build_hand() -> void:
	var side_s := 1.0 if side == "right" else -1.0
	hand_mesh = make_visual(side_s)
	add_child(hand_mesh)
	hand_skel = hand_mesh.get_node("Skeleton")

## Curl the fingers from the controller (trigger, grip and touch sensors).
func _pose_fingers(delta: float) -> void:
	var target := PackedFloat32Array([0.15, 0.15, 0.15, 0.15, 0.2])
	var g := grip_amount()
	var t := trig()
	var t_touch := t > 0.04 or (not Game.desktop_mode and is_button_pressed("trigger_touch"))
	var th_touch := Game.desktop_mode or is_button_pressed("primary_touch") or is_button_pressed("ax_touch") or is_button_pressed("by_touch")
	if held is Weapon:
		var w := held as Weapon
		target = PackedFloat32Array([0.45 + 0.35 * t if w.is_gun() else 0.92, 0.92, 0.95, 0.97, 0.75])
	elif held != null:
		target = PackedFloat32Array([0.9, 0.95, 0.97, 1.0, 0.8])
	elif tk_target != null:
		target = PackedFloat32Array([0.32, 0.35, 0.38, 0.42, 0.3])
	else:
		target[0] = (0.2 + 0.8 * t) if t_touch else 0.0
		for f in [1, 2, 3]:
			target[f] = 0.1 + 0.9 * g
		target[4] = (0.55 if th_touch else 0.08) + 0.3 * g
	for i in 5:
		curls[i] = lerpf(curls[i], target[i], minf(1.0, 20.0 * delta))
	apply_pose(hand_skel, 1.0 if side == "right" else -1.0, curls)

# ---------------------------------------------------------------- aim pose
## Typical aim pose relative to the grip pose (used on desktop or if the
## runtime does not report an aim pose).
static func grip_to_aim() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-58.0)), Vector3(0.0, -0.035, -0.045))

## The controller's pointing ray (guns, telekinesis, force push).
func aim_xform() -> Transform3D:
	if not Game.desktop_mode:
		var tr := XRServer.get_tracker(tracker) as XRPositionalTracker
		if tr:
			var p := tr.get_pose(&"aim")
			if p and p.has_tracking_data:
				return (get_parent() as Node3D).global_transform * p.get_adjusted_transform()
	return global_transform * grip_to_aim()

func aim_origin() -> Vector3:
	return aim_xform().origin

## Where held things sit: just in front of the closed fingers.
func hold_point() -> Vector3:
	return global_transform * Vector3(0.012 * (1.0 if side == "right" else -1.0), -0.05, 0.0)

## Transform (in this node's space) for a held weapon.
func weapon_hold(w: Weapon) -> Transform3D:
	if w.is_gun():
		# barrel along the aim ray, grip handle in the palm
		var rel := global_transform.affine_inverse() * aim_xform()
		var b := rel.basis.orthonormalized()
		return Transform3D(b, -(b * Vector3(0, -0.045, 0.0)) + Vector3(0, 0.0, 0.0))
	# melee: handle through the fist, blade out of the thumb side, edge forward;
	# each weapon's handle centre (weapon space, along -Z) sits in the palm
	var hold_z: float = {"bat": 0.02, "baton": -0.01, "machete": -0.065, "knife": -0.045, "axe": -0.07}.get(w.type, 0.0)
	return Transform3D(Basis(), Vector3(0.0, 0.0, -hold_z))

func haptic(amplitude: float, duration: float) -> void:
	if not Game.desktop_mode:
		trigger_haptic_pulse("haptic", 0.0, clampf(amplitude, 0.0, 1.0), duration, 0.0)

# ---------------------------------------------------------------- inputs
func trig() -> float:
	return sim_trigger if Game.desktop_mode else get_float("trigger")

func grip() -> bool:
	return sim_grip if Game.desktop_mode else (get_float("grip") > 0.6 or is_button_pressed("grip_click"))

func grip_amount() -> float:
	return (1.0 if sim_grip else 0.0) if Game.desktop_mode else get_float("grip")

func click() -> bool:
	return sim_click if Game.desktop_mode else is_button_pressed("primary_click")

func stick() -> Vector2:
	return sim_stick if Game.desktop_mode else get_vector2("primary")

func aim_dir() -> Vector3:
	return -aim_xform().basis.z

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
		var pos := hold_point()
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
			_hold_rigid(ped.ragdoll.nearest_body(hold_point()))
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
	var target := (aim_origin() + aim_dir() * 0.9) if rb is Car else hold_point()
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
	var from := aim_origin()
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
	var target := aim_origin() + aim_dir() * tk_dist + Vector3(0, 0.1, 0)
	var diff := target - rb.global_position
	var want := diff * 10.0
	if want.length() > 30.0:
		want = want.normalized() * 30.0
	rb.linear_velocity = rb.linear_velocity.lerp(want, 0.6)
	rb.angular_velocity *= 0.9
	if rb is Car:
		rb.angular_velocity = rb.angular_velocity.lerp(Vector3(0, 0.6, 0), 0.05)
	# visuals
	var a := aim_origin() + aim_dir() * 0.03
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
	push_ring.global_position = aim_origin() + aim_dir() * 1.0
	var dir := aim_dir()
	var center := aim_origin() + dir * 2.8
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
		var to_col: Vector3 = col.global_position - aim_origin()
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
