class_name Car
extends VehicleBody3D
## Drivable low-poly car. AI drives along the road graph (police chase the
## player), the player can carjack it, it damages anything it hits, and it
## explodes when destroyed.

enum Mode { AI, PLAYER, PARKED, WRECK }

var is_police := false
var mode: Mode = Mode.AI
var health := 100.0
var color: Color = Color.RED
var from_node: Vector2i
var to_node: Vector2i
var prev_node: Vector2i = Vector2i(-9, -9)
var target: Vector3
var cruise_speed := 11.0
var has_driver := true
var passengers := 0
var siren_on := false
var flash_t := 0.0
var engine_player: AudioStreamPlayer3D
var siren_player: AudioStreamPlayer3D
var body_meshes: Array[MeshInstance3D] = []
var light_red: MeshInstance3D
var light_blue: MeshInstance3D
var brake_l: MeshInstance3D
var brake_r: MeshInstance3D
var driver_meshes: Array[Node3D] = []
var wheels: Array[VehicleWheel3D] = []
var throttle_in := 0.0
var brake_in := 0.0
var steer_in := 0.0
var handbrake_in := false
var last_hit := 0.0
var unload_cops := false
var cops_unloaded := false
var stuck_t := 0.0
var far := false
var age := 0.0
var fire: CPUParticles3D
var steer_wheel: Node3D

var body_type := "sedan"
var dims: Dictionary
var body_mi: MeshInstance3D
var interior_mi: MeshInstance3D
var dent_arrays: Array = []
var last_dent := 0.0
var dent_total := 0.0

static func create(police: bool, col: Color = Color.RED, type: String = "") -> Car:
	var c := Car.new()
	c.is_police = police
	c.color = col
	if police:
		c.body_type = "police"
	elif type != "":
		c.body_type = type
	else:
		var r := Game.rng.randf()
		c.body_type = "sedan" if r < 0.38 else ("hatch" if r < 0.6 else ("suv" if r < 0.8 else ("taxi" if r < 0.9 else "van")))
	return c

## Driver eye position (car local).
func seat_local() -> Vector3:
	return Vector3(-0.38, dims["bot"] + 0.95, dims["ws"] + 0.95)

func door_local() -> Vector3:
	return Vector3(-(dims["hw"] + 0.75), 0.0, dims["ws"] + 0.85)

func _ready() -> void:
	add_to_group("cars")
	dims = CarGen.dims(body_type)
	mass = dims["mass"]
	collision_layer = Game.bit(Game.L_CAR)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_RAGDOLL, Game.L_PROP, Game.L_NPC, Game.L_PLAYER])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.05, 0)
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	linear_damp = 0.05
	angular_damp = 0.6
	can_sleep = true
	var d := dims
	var low_h: float = d["belt"] - d["bot"]
	MeshLib.collider(MeshLib.box_shape(Vector3(d["hw"] * 2.0, low_h, d["len"] * 0.97)), Vector3(0, d["bot"] + low_h * 0.5, 0), Vector3.ZERO, self)
	var cab_h: float = d["roof"] - d["belt"]
	var cab_l: float = d["rw"] - d["ws"]
	MeshLib.collider(MeshLib.box_shape(Vector3(d["hw"] * 1.7, cab_h, cab_l * 0.85)), Vector3(0, d["belt"] + cab_h * 0.5, (d["ws"] + d["rw"]) * 0.5), Vector3.ZERO, self)
	_build_visual()
	_build_wheels()
	body_entered.connect(_on_body_entered)
	engine_player = Game.sfx.make_loop_player("engine", self, -14.0)
	engine_player.play()
	if is_police:
		siren_player = Game.sfx.make_loop_player("siren", self, -4.0)
	if Game.gore:
		Game.gore.register_blob(self, 4.6)

func _build_visual() -> void:
	var m := CarGen.meshes(body_type, color)
	body_mi = MeshInstance3D.new()
	body_mi.mesh = m["body"]
	body_mi.material_override = MeshLib.atlas()
	body_mi.visibility_range_end = 220.0
	add_child(body_mi)
	body_meshes = [body_mi]
	interior_mi = MeshInstance3D.new()
	interior_mi.mesh = m["interior"]
	interior_mi.material_override = MeshLib.atlas()
	interior_mi.visibility_range_end = 14.0
	interior_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(interior_mi)
	brake_l = MeshInstance3D.new()
	brake_l.mesh = m["tail"]
	brake_l.material_override = MeshLib.mat(Color(0.6, 0.05, 0.05), 0.4)
	brake_l.visibility_range_end = 90.0
	brake_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(brake_l)
	brake_r = brake_l
	var d := dims
	if is_police:
		var lz: float = lerpf(d["rf"], d["rr"], 0.35)
		light_red = MeshLib.inst(MeshLib.box(Vector3(0.5, 0.11, 0.24)), MeshLib.mat(Color(0.6, 0.05, 0.05), 0.4), Vector3(-0.3, d["roof"] + 0.1, lz), Vector3.ZERO, self)
		light_blue = MeshLib.inst(MeshLib.box(Vector3(0.5, 0.11, 0.24)), MeshLib.mat(Color(0.05, 0.1, 0.6), 0.4), Vector3(0.3, d["roof"] + 0.1, lz), Vector3.ZERO, self)
		light_red.visibility_range_end = 0.0
		light_blue.visibility_range_end = 0.0
	# steering wheel: tilted mount + spinning wheel
	var tilt := Node3D.new()
	tilt.position = Vector3(-0.38, d["belt"] - 0.02, d["ws"] + 0.48)
	tilt.rotation_degrees = Vector3(62, 0, 0)
	add_child(tilt)
	steer_wheel = MeshLib.inst_built(_steer_mesh(), Vector3.ZERO, Vector3.ZERO, tilt, 25.0)
	# occupants: real people sitting in the seats
	driver_meshes = []
	var occupants := 2 if is_police else 1
	for i in occupants:
		var person := Ped.make_seated(is_police)
		person.position = Vector3(-0.38 if i == 0 else 0.38, d["bot"] + 0.36 - 0.98, d["ws"] + 0.98)
		add_child(person)
		driver_meshes.append(person)
	if is_police:
		passengers = 1
	if fire == null:
		fire = CPUParticles3D.new()
		fire.emitting = false
		fire.amount = 40
		fire.lifetime = 1.1
		fire.mesh = MeshLib.sphere(0.25, 5, 3)
		fire.material_override = MeshLib.mat(Color(1.0, 0.5, 0.1), 1.0, 0.0, Color(1.0, 0.4, 0.05), 2.0)
		fire.direction = Vector3.UP
		fire.spread = 30.0
		fire.initial_velocity_min = 2.0
		fire.initial_velocity_max = 5.0
		fire.gravity = Vector3(0, 2.0, 0)
		fire.scale_amount_min = 0.4
		fire.scale_amount_max = 1.5
		fire.position = Vector3(0, d["hood"], d["ws"] - 0.6)
		add_child(fire)

static var _steer: ArrayMesh
static func _steer_mesh() -> ArrayMesh:
	if _steer:
		return _steer
	var g := Geo.new()
	var dark := Color(0.06, 0.06, 0.065)
	var rings := []
	for k in 16:
		var a := TAU * k / 16.0
		rings.append(Geo.ring_axis(Vector3(cos(a) * 0.18, 0, sin(a) * 0.18), Vector3(-sin(a), 0, cos(a)), 0.016, 0.016, 8))
	rings.append(rings[0])
	g.mat(dark, 0.55).loft(rings, false, false)
	g.mat(dark, 0.6).rbox(Vector3.ZERO, Vector3(0.12, 0.05, 0.1), 0.02, 1)
	g.mat(dark, 0.6).rbox(Vector3(0, 0, 0.08), Vector3(0.03, 0.02, 0.16), 0.008, 1)
	g.mat(dark, 0.6).rbox(Vector3(0.09, 0, 0), Vector3(0.18, 0.02, 0.03), 0.008, 1)
	g.mat(dark, 0.6).rbox(Vector3(-0.09, 0, 0), Vector3(0.18, 0.02, 0.03), 0.008, 1)
	_steer = g.mesh()
	return _steer

func _build_wheels() -> void:
	var d := dims
	var wr: float = d["wr"]
	var wx: float = d["hw"] - 0.11
	var wz: float = d["wb"] * 0.5
	for p in [Vector3(-wx, wr, -wz), Vector3(wx, wr, -wz), Vector3(-wx, wr, wz), Vector3(wx, wr, wz)]:
		var w := VehicleWheel3D.new()
		w.position = p + Vector3(0, 0.08, 0)
		w.use_as_steering = p.z < 0.0
		w.use_as_traction = true
		w.wheel_radius = wr
		w.wheel_rest_length = 0.22
		w.suspension_travel = 0.2
		w.suspension_stiffness = 40.0 if body_type != "van" else 50.0
		w.suspension_max_force = mass * 11.0
		w.damping_compression = 0.6
		w.damping_relaxation = 0.8
		w.wheel_friction_slip = 3.2
		w.wheel_roll_influence = 0.05
		add_child(w)
		MeshLib.inst_built(d.get("wheel_mesh", CarGen.wheel_mesh(wr)), Vector3.ZERO, Vector3.ZERO, w, 90.0)
		wheels.append(w)

## Crumple the body around a local point (crash damage you can see).
func dent(world_pos: Vector3, dir_world: Vector3, amount: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_dent < 0.25 or dent_total > 1.2 or amount < 0.01:
		return
	last_dent = now
	amount = minf(amount, 0.18)
	dent_total += amount
	if dent_arrays.is_empty():
		dent_arrays = body_mi.mesh.surface_get_arrays(0)
	var lp := to_local(world_pos)
	var ld := (global_transform.basis.inverse() * dir_world).normalized()
	var verts: PackedVector3Array = dent_arrays[Mesh.ARRAY_VERTEX]
	var radius := 0.7
	var moved := false
	for i in verts.size():
		var dd := verts[i].distance_to(lp)
		if dd < radius:
			var f := 1.0 - dd / radius
			verts[i] += ld * amount * f * f + Vector3(Game.randf_range(-1, 1), Game.randf_range(-1, 1), Game.randf_range(-1, 1)) * 0.012 * f
			moved = true
	if not moved:
		return
	dent_arrays[Mesh.ARRAY_VERTEX] = verts
	# recompute normals so the dent catches the light
	var idx: PackedInt32Array = dent_arrays[Mesh.ARRAY_INDEX]
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	var i := 0
	while i + 2 < idx.size():
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var n := (verts[c] - verts[a]).cross(verts[b] - verts[a])
		nrm[a] += n
		nrm[b] += n
		nrm[c] += n
		i += 3
	for k in nrm.size():
		nrm[k] = nrm[k].normalized() if nrm[k].length() > 0.0 else Vector3.UP
	dent_arrays[Mesh.ARRAY_NORMAL] = nrm
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, dent_arrays)
	body_mi.mesh = am

## Point on the car's skin in the direction of `toward` (world).
func hull_point(toward: Vector3) -> Vector3:
	var l := to_local(toward)
	var d := dims
	var ext := Vector3(d["hw"], (d["belt"] - d["bot"]) * 0.5, d["len"] * 0.5)
	var c := Vector3(0, (d["belt"] + d["bot"]) * 0.5, 0)
	var dir := l - c
	if dir.length() < 0.001:
		return global_position
	var t := INF
	for ax in 3:
		if absf(dir[ax]) > 0.0001:
			t = minf(t, ext[ax] / absf(dir[ax]))
	return to_global(c + dir * t)

## Place the car on a lane heading from node a to node b.
func place_on_road(a: Vector2i, b: Vector2i, t: float) -> void:
	from_node = a
	to_node = b
	prev_node = Vector2i(-9, -9)
	var city := Game.city
	var p := city.lane_point(a, b, t)
	var dir := (city.road_pos(b.x, b.y) - city.road_pos(a.x, a.y)).normalized()
	global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p + Vector3(0, 0.3, 0))
	target = city.lane_point(a, b, 1.0)

## Godot's VehicleBody3D pushes toward +Z for positive engine force; our cars face -Z.
func _engine(force: float) -> void:
	engine_force = -force

func forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z)

func seat_global() -> Transform3D:
	return global_transform * Transform3D(Basis(), seat_local())

func door_global() -> Vector3:
	return global_transform * door_local()

# ---------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	age += delta
	var dist := Game.flat(global_position - Game.player_pos()).length()
	if mode != Mode.PLAYER:
		var should_far := dist > 95.0
		if should_far != far:
			far = should_far
			freeze = far and mode != Mode.WRECK
			if engine_player:
				engine_player.stream_paused = far
		if far:
			return
	match mode:
		Mode.AI:
			_drive_ai(delta, dist)
		Mode.PLAYER:
			_drive_player(delta)
		Mode.PARKED:
			_engine(0.0)
			brake = 8.0
			steering = 0.0
		Mode.WRECK:
			_engine(0.0)
			brake = 20.0
	_update_lights(delta)
	if steer_wheel and not far:
		steer_wheel.rotation.y = steering * 4.0
	if engine_player:
		var sp := absf(forward_speed())
		engine_player.pitch_scale = 0.6 + clampf(sp / 28.0, 0.0, 1.2) + (0.25 if absf(engine_force) > 100.0 else 0.0)
	# upside down for a while -> flip back up (keeps the game playable)
	if global_transform.basis.y.y < 0.1 and linear_velocity.length() < 1.0:
		stuck_t += delta
		if stuck_t > 2.5:
			stuck_t = 0.0
			var t := global_transform
			t.basis = Basis(Vector3.UP, t.basis.get_euler().y)
			t.origin.y += 1.0
			global_transform = t
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		stuck_t = 0.0

func _drive_player(delta: float) -> void:
	var sp := forward_speed()
	var max_speed := 38.0
	var f := throttle_in * 7000.0
	if sp > max_speed:
		f = 0.0
	if brake_in > 0.05:
		if sp > 1.0:
			brake = brake_in * 45.0
			f = 0.0
		else:
			brake = 0.0
			f = -brake_in * 4000.0
	else:
		brake = 0.0
	if handbrake_in:
		brake = 60.0
		f = 0.0
	_engine(f)
	var max_steer := lerpf(0.55, 0.18, clampf(absf(sp) / 30.0, 0.0, 1.0))
	steering = lerpf(steering, -steer_in * max_steer, 8.0 * delta)
	if absf(sp) > 1.0:
		Game.cop_saw_player()

func _drive_ai(delta: float, dist_to_player: float) -> void:
	var city := Game.city
	var chase := is_police and Game.wanted_stars > 0 and dist_to_player < 140.0
	if chase and not siren_on:
		set_siren(true)
	elif not chase and siren_on and Game.wanted_stars == 0:
		set_siren(false)
	var ppos := Game.player_pos()
	var goal := target
	var desired := cruise_speed
	if chase:
		desired = 17.0 + Game.wanted_stars * 2.0
		Game.cop_saw_player()
		if dist_to_player < 40.0:
			# direct pursuit: aim at the player, ram if driving, stop and unload cops if on foot
			var pv := Vector3.ZERO
			if Game.player and Game.player.has_method("get_velocity_estimate"):
				pv = Game.player.get_velocity_estimate()
			goal = ppos + pv * 0.6
			var player_in_car: bool = Game.player != null and Game.player.get("car") != null
			if not player_in_car and dist_to_player < 14.0:
				desired = 0.0
				if forward_speed() < 1.5 and not cops_unloaded:
					_unload_cops()
		# re-plan road target toward the player
		if (global_position - target).length() < 6.0:
			_advance_node(ppos)
	else:
		if (global_position - target).length() < 5.0 or (target - global_position).dot(-global_transform.basis.z) < -2.0:
			_advance_node()
	# obstacle check: another car directly ahead
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.6, 0) - global_transform.basis.z * 2.3
	var to := from - global_transform.basis.z * 9.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.mask([Game.L_CAR, Game.L_WORLD]), [get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and not chase:
		desired = minf(desired, 2.0)
	elif not hit.is_empty():
		desired = minf(desired, 8.0)
	var local := global_transform.affine_inverse() * goal
	var ang := atan2(-local.x, -local.z)
	var sp := forward_speed()
	var max_steer := lerpf(0.5, 0.2, clampf(absf(sp) / 25.0, 0.0, 1.0))
	steering = lerpf(steering, clampf(ang * 1.4, -max_steer, max_steer), 6.0 * delta)
	if absf(ang) > 2.2 and sp < 2.0 and chase:
		# target behind us: reverse a little
		_engine(-2500.0)
		brake = 0.0
		steering = -steering
	elif sp < desired - 0.5:
		_engine(3800.0 if not chase else 6000.0)
		brake = 0.0
	elif sp > desired + 1.5:
		_engine(0.0)
		brake = 12.0 if desired > 0.5 else 30.0
	else:
		_engine(0.0)
		brake = 0.0
	if desired < 0.5 and sp < 0.5:
		brake = 30.0
	if not city.in_bounds(global_position):
		_advance_node(Vector3.ZERO)

func _advance_node(toward: Vector3 = Vector3.INF) -> void:
	var city := Game.city
	var cur := city.nearest_road_node(global_position)
	if cur == to_node or (global_position - city.road_pos(to_node.x, to_node.y)).length() < 7.0:
		prev_node = from_node
		from_node = to_node
	else:
		prev_node = from_node
		from_node = cur
	to_node = city.next_road_node(from_node, prev_node, toward)
	if to_node == from_node:
		to_node = city.next_road_node(from_node, Vector2i(-9, -9), toward)
	target = city.lane_point(from_node, to_node, 1.0)

func _unload_cops() -> void:
	cops_unloaded = true
	mode = Mode.PARKED
	for m in driver_meshes:
		m.visible = false
	has_driver = false
	if Game.main and Game.main.has_method("spawn_cop_at"):
		Game.main.spawn_cop_at(door_global() + Vector3(0, 0.1, 0), true)
		Game.main.spawn_cop_at(global_transform * Vector3(1.7, 0.1, 0.15), Game.wanted_stars >= 2)
	# the car reactivates as a parked car the player may steal
	var t := get_tree().create_timer(25.0)
	t.timeout.connect(func():
		if is_instance_valid(self) and mode == Mode.PARKED:
			set_siren(false))

func set_siren(on: bool) -> void:
	siren_on = on
	if siren_player:
		if on and not siren_player.playing:
			siren_player.play()
		elif not on:
			siren_player.stop()

static var _m_red_on: Material
static var _m_red_off: Material
static var _m_blue_on: Material
static var _m_blue_off: Material
static var _m_tail_on: Material
static var _m_tail_off: Material

static func _light_mats() -> void:
	if _m_red_on:
		return
	_m_red_on = MeshLib.mat(Color(1, 0.1, 0.1), 0.4, 0.0, Color(1, 0, 0), 3.0)
	_m_red_off = MeshLib.mat(Color(0.6, 0.05, 0.05), 0.4)
	_m_blue_on = MeshLib.mat(Color(0.2, 0.3, 1), 0.4, 0.0, Color(0.1, 0.2, 1), 3.0)
	_m_blue_off = MeshLib.mat(Color(0.05, 0.1, 0.6), 0.4)
	_m_tail_on = MeshLib.mat(Color(1, 0.1, 0.1), 0.4, 0.0, Color(1, 0, 0), 2.0)
	_m_tail_off = _m_red_off

func _update_lights(delta: float) -> void:
	if mode == Mode.WRECK:
		return
	_light_mats()
	if is_police and light_red:
		var red := _m_red_off
		var blue := _m_blue_off
		if siren_on:
			flash_t += delta
			var phase := fmod(flash_t, 0.3) < 0.15
			red = _m_red_on if phase else _m_red_off
			blue = _m_blue_off if phase else _m_blue_on
		if light_red.material_override != red:
			light_red.material_override = red
		if light_blue.material_override != blue:
			light_blue.material_override = blue
	var braking := brake > 1.0 and mode != Mode.PARKED
	var tail := _m_tail_on if braking else _m_tail_off
	if brake_l.material_override != tail:
		brake_l.material_override = tail

# ---------------------------------------------------------------- player
func enter_player() -> void:
	mode = Mode.PLAYER
	freeze = false
	far = false
	for m in driver_meshes:
		m.visible = false
	has_driver = false
	throttle_in = 0.0
	brake_in = 0.0
	steer_in = 0.0
	set_siren(false)
	if engine_player:
		engine_player.stream_paused = false

func exit_player() -> void:
	mode = Mode.PARKED
	_engine(0.0)
	brake = 10.0

func player_control(throttle: float, brk: float, steer: float, handbrake: bool) -> void:
	throttle_in = throttle
	brake_in = brk
	steer_in = steer
	handbrake_in = handbrake

## Pull the driver out: spawn a pedestrian ragdoll flying out of the door.
func eject_driver(impulse: Vector3) -> void:
	if not has_driver:
		return
	has_driver = false
	for m in driver_meshes:
		m.visible = false
	if Game.main and Game.main.has_method("spawn_ped_at"):
		var p: Ped = Game.main.spawn_ped_at(door_global() + Vector3(0, 0.2, 0), is_police, is_police)
		if p:
			p.rotation.y = global_transform.basis.get_euler().y
			p.call_deferred("go_ragdoll", impulse + Vector3(0, 60, 0), Vector3.INF, "torso")
			Game.gore.spray(door_global() + Vector3(0, 1.0, 0), -global_transform.basis.x, 1.2)
			Game.sfx.play("yell", global_position, -2.0, 0.9)
	if is_police and passengers > 0:
		passengers = 0
		if Game.main and Game.main.has_method("spawn_cop_at"):
			Game.main.spawn_cop_at(global_transform * Vector3(1.7, 0.1, 0.15), true)
	Game.crime("carjack")

# ---------------------------------------------------------------- damage
func take_hit(dmg: float, impulse: Vector3, pos: Vector3, part: String, kind: String) -> void:
	if mode == Mode.WRECK:
		return
	if kind == "punch" or kind == "melee" or kind == "sharp":
		dmg *= 0.6
		apply_impulse(impulse * 25.0, pos - global_position)
		Game.sfx.play("clank", pos, -2.0)
		dent(pos, impulse, clampf(impulse.length() / 900.0, 0.02, 0.12))
	elif kind == "bullet":
		Game.sfx.play("clank", pos, -6.0, 1.4)
	elif kind == "throw":
		Game.sfx.play("clank", pos, 0.0)
		dent(pos, impulse, clampf(dmg / 300.0, 0.02, 0.14))
	health -= dmg
	last_hit = Time.get_ticks_msec() / 1000.0
	if is_police:
		Game.crime("cop_assault")
	if health <= 0.0:
		explode()

func _on_body_entered(body: Node) -> void:
	if mode == Mode.WRECK and linear_velocity.length() < 2.0:
		return
	var v := linear_velocity
	var speed := v.length()
	if body is RigidBody3D:
		speed = (v - (body as RigidBody3D).linear_velocity).length()
	if speed < 2.5:
		return
	var contact := global_position + v.normalized() * 2.0 + Vector3(0, 0.6, 0)
	if body is Ped:
		var ped := body as Ped
		var impulse := v * 30.0 + Vector3.UP * 90.0
		if speed > 16.0:
			ped.take_hit(999.0, impulse, contact, "torso", "explosion")
		else:
			ped.take_hit(speed * 9.0, impulse, contact, "torso", "car")
		Game.sfx.play("thud", contact, 2.0)
		if mode == Mode.PLAYER:
			Game.add_score(25)
	elif body is RigidBody3D and body.has_meta("ragdoll"):
		var rd: Ragdoll = body.get_meta("ragdoll")
		if is_instance_valid(rd) and speed > 4.0:
			var part: String = body.get_meta("part")
			rd.take_hit(speed * 6.0, v * 8.0, body.global_position, part, "car")
			if speed > 12.0 and part not in ["chest", "pelvis"]:
				rd.dismember(int(body.get_meta("bone")), v * 3.0)
	elif body is Car:
		if speed > 5.0:
			var hp := hull_point((body as Car).global_position)
			dent(hp, (global_position - (body as Car).global_position), speed * 0.008)
			(body as Car).dent((body as Car).hull_point(global_position), ((body as Car).global_position - global_position), speed * 0.008)
		if speed > 7.0:
			health -= speed * 1.5
			(body as Car).health -= speed * 1.5
			Game.sfx.play("clank", contact, 2.0, 0.8)
			if (body as Car).health <= 0.0:
				(body as Car).explode()
			if health <= 0.0:
				explode()
			if mode == Mode.PLAYER and (body as Car).is_police:
				Game.crime("cop_assault")
	elif body is CharacterBody3D and body.has_method("take_damage"):
		body.take_damage(speed * 6.0, v * 0.8 + Vector3.UP * 3.0)
		Game.sfx.play("thud", contact, 2.0)
	elif body is StaticBody3D:
		if speed > 6.0:
			var fwd := v.normalized()
			dent(global_position + fwd * dims["len"] * 0.5 + Vector3(0, dims["hood"] - 0.25, 0), -fwd, speed * 0.008)
		if speed > 9.0:
			health -= speed * 1.2
			Game.sfx.play("clank", contact, 0.0, 0.7)
			if health <= 0.0:
				explode()
	elif body is RigidBody3D:
		Game.sfx.play("thud", contact, -4.0)

func explode() -> void:
	if mode == Mode.WRECK:
		return
	var was_player := mode == Mode.PLAYER
	mode = Mode.WRECK
	set_siren(false)
	health = 0.0
	var pos := global_position + Vector3(0, 0.8, 0)
	Game.sfx.play("explosion", pos, 6.0)
	fire.emitting = true
	fire.one_shot = false
	var burnt := MeshLib.mat(Color(0.07, 0.06, 0.06), 0.95)
	for m in body_meshes:
		m.material_override = burnt
	brake_l.material_override = burnt
	for m in driver_meshes:
		m.visible = false
	apply_central_impulse(Vector3(Game.randf_range(-2, 2), 9.0, Game.randf_range(-2, 2)) * mass)
	apply_torque_impulse(Vector3(Game.randf_range(-1, 1), Game.randf_range(-1, 1), Game.randf_range(-1, 1)) * mass * 2.0)
	Game.panic(pos, 40.0)
	# blast damage
	for p in get_tree().get_nodes_in_group("peds"):
		var d: float = p.global_position.distance_to(pos)
		if d < 7.0:
			var dir: Vector3 = (p.global_position - pos).normalized() + Vector3.UP
			p.take_hit(300.0, dir * 400.0, p.global_position + Vector3(0, 1, 0), "torso", "explosion")
	for c in get_tree().get_nodes_in_group("cars"):
		if c != self and c.global_position.distance_to(pos) < 6.0:
			c.health -= 60.0
			if c.health <= 0.0:
				c.call_deferred("explode")
	if Game.player:
		var pd: float = Game.player.global_position.distance_to(pos)
		if was_player:
			Game.player.take_damage(999.0, Vector3.UP)
		elif pd < 8.0:
			Game.player.take_damage(80.0 * (1.0 - pd / 8.0), (Game.player.global_position - pos).normalized() * 6.0 + Vector3.UP * 4.0)
	if was_player or (last_hit > 0.0 and Time.get_ticks_msec() / 1000.0 - last_hit < 5.0):
		Game.crime("car_destroy")
	Game.gore.decal(global_position, 2.5)
	if engine_player:
		engine_player.stop()
	# stop burning after a while
	var t := get_tree().create_timer(9.0)
	t.timeout.connect(func():
		if is_instance_valid(self):
			fire.emitting = false)
