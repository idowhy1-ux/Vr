class_name Main
extends Node3D
## Entry point: initialises OpenXR for the Quest, builds the city, spawns the
## player and keeps the streets populated with pedestrians, police and cars.

var xr: XRInterface
var player: Player
var hud: Hud
var spawn_timer := 0.0
var weapon_timer := 0.0
var frame := 0
var autotest_step := 0
var shot_path := ""
var soak := false

func _ready() -> void:
	Game.main = self
	for a in OS.get_cmdline_user_args():
		if a == "--soak":
			soak = true
		if a.begins_with("--screenshot="):
			shot_path = a.substr(13)
			Game.screenshot = true
	_init_xr()
	var sfx := Sfx.new()
	add_child(sfx)
	Game.sfx = sfx
	var gore := Gore.new()
	add_child(gore)
	Game.gore = gore
	var city := City.new()
	add_child(city)
	Game.city = city
	player = Player.new()
	player.name = "Player"
	var start := city.walk_pos(city.walk_count() / 2, city.walk_count() / 2)
	player.position = start + Vector3(0, 0.1, 0)
	add_child(player)
	Game.player = player
	hud = Hud.new()
	add_child(hud)
	hud.setup(player)
	var t0 := Time.get_ticks_msec()
	Ped.prebuild_looks()
	var t1 := Time.get_ticks_msec()
	# build every car and weapon mesh now so nothing hitches during play
	for col in MeshLib.CAR_COLORS:
		for t in ["sedan", "hatch", "suv", "van"]:
			CarGen.meshes(t, col)
	CarGen.meshes("police", Color.WHITE)
	CarGen.meshes("taxi", Color.WHITE)
	for w in Weapon.TYPES.keys():
		Weapon.visual_mesh(w)
	print("startup: people %d ms, cars+weapons %d ms" % [t1 - t0, Time.get_ticks_msec() - t1])
	_spawn_props()
	_spawn_initial_weapons(start)
	_spawn_starter_car(start)
	_spawn_controls_sign(start)
	_populate(true)
	print("Police Chase VR ready. XR: %s" % ("on" if not Game.desktop_mode else "desktop fallback"))

func _init_xr() -> void:
	xr = XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Game.desktop_mode = false
		if xr.has_signal("session_begun"):
			xr.session_begun.connect(_on_session_begun)
		if xr.has_signal("pose_recentered"):
			xr.pose_recentered.connect(func(): XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true))
	else:
		Game.desktop_mode = true
		push_warning("OpenXR not initialised; running in desktop fallback mode.")

func _on_session_begun() -> void:
	# Ask the headset for 90 Hz and match physics to it.
	var oxr := xr as OpenXRInterface
	if oxr == null:
		return
	var rates: Array = oxr.get_available_display_refresh_rates()
	var want := 90.0
	if rates.size() > 0 and not (want in rates):
		want = float(rates[rates.size() - 1])
		for r in rates:
			if float(r) >= 90.0:
				want = float(r)
				break
	oxr.display_refresh_rate = want
	Game.base_physics_rate = int(round(want))
	Engine.physics_ticks_per_second = Game.base_physics_rate
	print("XR refresh rate set to %s (available %s)" % [want, rates])

# ---------------------------------------------------------------- spawning
func spawn_ped_at(pos: Vector3, is_cop: bool, has_gun: bool) -> Ped:
	var p := Ped.new()
	p.is_cop = is_cop
	p.has_gun = has_gun
	p.position = pos
	add_child(p)
	return p

func spawn_cop_at(pos: Vector3, has_gun: bool) -> Ped:
	var p := spawn_ped_at(pos, true, has_gun)
	p.state = Ped.State.CHASE
	return p

func spawn_car(police: bool, near: Vector3, min_r: float, max_r: float) -> Car:
	var city := Game.city
	var info := city.random_road_point_near(near, min_r, max_r)
	# don't spawn on top of another car
	for c2 in get_tree().get_nodes_in_group("cars"):
		if (c2 as Node3D).global_position.distance_to(info["pos"]) < 7.0:
			info = city.random_road_point_near(near, min_r, max_r)
			break
	var c := Car.create(police, MeshLib.CAR_COLORS[Game.randi_range(0, MeshLib.CAR_COLORS.size() - 1)])
	add_child(c)
	c.place_on_road(info["from"], info["to"], 0.5)
	c.cruise_speed = Game.randf_range(9.0, 13.0)
	return c

func spawn_weapon(type: String, pos: Vector3) -> Weapon:
	var w := Weapon.create(type)
	w.position = pos
	add_child(w)
	w.rotation = Vector3(0, Game.randf_range(0, TAU), 0)
	return w

func drop_weapon(type: String, pos: Vector3) -> void:
	var w := spawn_weapon(type, pos)
	w.linear_velocity = Vector3(Game.randf_range(-1, 1), 2.0, Game.randf_range(-1, 1))

func _spawn_initial_weapons(center: Vector3) -> void:
	var types := ["bat", "machete", "pistol", "shotgun", "smg", "axe", "knife", "pistol", "bat", "shotgun"]
	for i in types.size():
		var ang := float(i) / types.size() * TAU
		var pos := center + Vector3(cos(ang) * (2.0 + i * 0.4), 0.3, sin(ang) * (2.0 + i * 0.4))
		spawn_weapon(types[i], pos)

## A parked car with a driver right next to the spawn: walk up and press B to carjack it.
func _spawn_starter_car(center: Vector3) -> void:
	var city := Game.city
	var node := city.nearest_road_node(center)
	var next := city.next_road_node(node, Vector2i(-9, -9), center + Vector3(1, 0, 0))
	var c := Car.create(false, Color(0.85, 0.1, 0.1))
	add_child(c)
	c.place_on_road(node, next, 0.3)
	c.mode = Car.Mode.PARKED

func _spawn_controls_sign(center: Vector3) -> void:
	var sign := Label3D.new()
	sign.text = """POLICE CHASE VR
LEFT STICK  move        RIGHT STICK  snap turn
FIST  swing to punch (super strength)
GRIP  grab weapons, people, cars - release to throw
TRIGGER (empty hand)  telekinesis - stick pushes/pulls, grip yanks it to you, flick to throw
TRIGGER (gun)  shoot          STICK CLICK  force push
A  super jump     B  steal car / exit     X  bullet time     Y  recenter
DRIVING  R trigger gas   L trigger brake/reverse   L stick steer"""
	sign.font_size = 48
	sign.pixel_size = 0.0025
	sign.outline_size = 10
	sign.modulate = Color(1.0, 0.95, 0.85)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.visibility_range_end = 30.0
	sign.position = center + Vector3(0, 2.4, -5.0)
	add_child(sign)
	var board := MeshLib.inst(MeshLib.box(Vector3(5.6, 2.1, 0.08)), MeshLib.mat(Color(0.08, 0.09, 0.12), 0.6), center + Vector3(0, 2.4, -5.08), Vector3.ZERO, self)
	board.visibility_range_end = 0.0
	MeshLib.inst(MeshLib.cylinder(0.06, 1.5, 6), MeshLib.mat(Color(0.25, 0.26, 0.28), 0.5, 0.6), center + Vector3(-2.4, 0.75, -5.1), Vector3.ZERO, self)
	MeshLib.inst(MeshLib.cylinder(0.06, 1.5, 6), MeshLib.mat(Color(0.25, 0.26, 0.28), 0.5, 0.6), center + Vector3(2.4, 0.75, -5.1), Vector3.ZERO, self)

static var _prop_meshes: Array = []

static func _build_prop_meshes() -> void:
	if not _prop_meshes.is_empty():
		return
	# oil drum with ribs
	var g := Geo.new()
	var blue := Color(0.12, 0.25, 0.5)
	var prof := [Vector2(0.0, -0.45), Vector2(0.29, -0.45), Vector2(0.3, -0.43)]
	for y in [-0.25, 0.0, 0.25]:
		prof.append_array([Vector2(0.3, y - 0.03), Vector2(0.315, y - 0.015), Vector2(0.315, y + 0.015), Vector2(0.3, y + 0.03)])
	prof.append_array([Vector2(0.3, 0.43), Vector2(0.29, 0.45), Vector2(0.0, 0.45)])
	g.mat(blue, 0.45, 0.6).lathe(prof, 16)
	g.mat(Color(0.2, 0.2, 0.2), 0.4, 0.8).ellipsoid(Vector3(0.15, 0.455, 0.0), Vector3(0.03, 0.008, 0.03), 8, 3)
	_prop_meshes.append(g.mesh())
	# wooden crate with planks and frame
	g = Geo.new()
	var wood := Color(0.62, 0.46, 0.27)
	g.mat(wood.darkened(0.15), 0.85).rbox(Vector3.ZERO, Vector3(0.76, 0.76, 0.76), 0.02, 1)
	for ax in 3:
		for e in [-1.0, 1.0]:
			for e2 in [-1.0, 1.0]:
				var c := Vector3.ZERO
				var sz := Vector3(0.82, 0.82, 0.82)
				var o := (ax + 1) % 3
				var o2 := (ax + 2) % 3
				c[o] = e * 0.37
				c[o2] = e2 * 0.37
				sz[o] = 0.09
				sz[o2] = 0.09
				g.mat(wood, 0.8).rbox(c, sz, 0.012, 1)
	for k in 3:
		for f in [-1.0, 1.0]:
			g.mat(wood.lightened(0.05), 0.8).rbox(Vector3(0, -0.2 + k * 0.2, f * 0.385), Vector3(0.66, 0.15, 0.02), 0.006, 1)
	_prop_meshes.append(g.mesh())
	# traffic cone with reflective stripes
	g = Geo.new()
	g.mat(Color(0.95, 0.38, 0.06), 0.6).lathe([Vector2(0.0, -0.33), Vector2(0.03, 0.35), Vector2(0.0, 0.36)], 14, false, true)
	g.mat(Color(0.95, 0.38, 0.06), 0.6).lathe([Vector2(0.0, -0.35), Vector2(0.22, -0.35), Vector2(0.22, -0.32), Vector2(0.15, -0.31), Vector2(0.0, -0.31)], 4)
	for y in [-0.05, 0.12]:
		var r0 := lerpf(0.15, 0.03, (y + 0.33) / 0.68)
		var r1 := lerpf(0.15, 0.03, (y + 0.08 + 0.33) / 0.68)
		g.mat(Color(0.95, 0.95, 0.95), 0.3, 0.0, 0.1).lathe([Vector2(r0 + 0.003, y), Vector2(r1 + 0.003, y + 0.08)], 14, false, false)
	g.mat(Color(0.95, 0.38, 0.06), 0.6).lathe([Vector2(0.0, -0.31), Vector2(0.15, -0.31), Vector2(0.03, 0.35), Vector2(0.0, 0.35)], 14)
	_prop_meshes.append(g.mesh())
	# trash bag
	g = Geo.new()
	g.mat(Color(0.05, 0.05, 0.06), 0.25, 0.1).ellipsoid(Vector3(0, -0.05, 0), Vector3(0.3, 0.32, 0.27), 12, 8)
	g.mat(Color(0.05, 0.05, 0.06), 0.25, 0.1).capsule(Vector3(0, 0.25, 0), Vector3(0.02, 0.4, 0.0), 0.05, 0.03, 8, 1)
	_prop_meshes.append(g.mesh())

func _spawn_props() -> void:
	var city := Game.city
	_build_prop_meshes()
	for i in 48:
		var n := city.random_walk_node()
		var pos := city.walk_pos(n.x, n.y) + Vector3(Game.randf_range(-1.0, 1.0), 0.55, Game.randf_range(-1.0, 1.0))
		var rb := RigidBody3D.new()
		rb.collision_layer = Game.bit(Game.L_PROP)
		rb.collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP, Game.L_RAGDOLL, Game.L_PLAYER])
		rb.mass = 12.0
		rb.can_sleep = true
		var kind := i % 4
		var mi := MeshInstance3D.new()
		mi.mesh = _prop_meshes[kind]
		mi.material_override = MeshLib.atlas()
		mi.visibility_range_end = 80.0
		rb.add_child(mi)
		if kind == 0:
			MeshLib.collider(MeshLib.cylinder_shape(0.31, 0.9), Vector3.ZERO, Vector3.ZERO, rb)
			rb.mass = 30.0
		elif kind == 1:
			MeshLib.collider(MeshLib.box_shape(Vector3(0.8, 0.8, 0.8)), Vector3.ZERO, Vector3.ZERO, rb)
			rb.mass = 18.0
		elif kind == 2:
			MeshLib.collider(MeshLib.cylinder_shape(0.15, 0.68), Vector3.ZERO, Vector3.ZERO, rb)
			rb.mass = 3.0
		else:
			MeshLib.collider(MeshLib.sphere_shape(0.3), Vector3(0, -0.05, 0), Vector3.ZERO, rb)
			rb.mass = 6.0
		rb.position = pos
		add_child(rb)

func _populate(initial: bool) -> void:
	var ppos := Game.player_pos()
	var city := Game.city
	var peds := 0
	var cops := 0
	var civ_cars := 0
	var cop_cars := 0
	for p in get_tree().get_nodes_in_group("peds"):
		if p is Ped:
			if (p as Ped).is_cop:
				cops += 1
			else:
				peds += 1
	for c in get_tree().get_nodes_in_group("cars"):
		var car := c as Car
		if car.mode == Car.Mode.WRECK:
			continue
		if car.is_police:
			cop_cars += 1
		else:
			civ_cars += 1
	var want_cops := mini(Game.MAX_COPS_BASE + Game.wanted_stars * 2, 10)
	var want_cop_cars := mini(1 + Game.wanted_stars, 5)
	var min_r := 12.0 if initial else 28.0
	var batch := 20 if initial else 2
	var n := 0
	while peds < Game.MAX_PEDS and n < batch:
		var pos := city.random_walk_point_near(ppos, min_r, Game.SPAWN_RADIUS)
		spawn_ped_at(pos, false, false)
		peds += 1
		n += 1
	n = 0
	while cops < want_cops and n < batch:
		var pos := city.random_walk_point_near(ppos, 30.0, Game.SPAWN_RADIUS)
		spawn_ped_at(pos, true, Game.wanted_stars >= 2 or Game.rng.randf() < 0.3)
		cops += 1
		n += 1
	n = 0
	while civ_cars < Game.MAX_CARS - want_cop_cars and n < batch:
		spawn_car(false, ppos, 30.0 if initial else 60.0, 110.0)
		civ_cars += 1
		n += 1
	n = 0
	while cop_cars < want_cop_cars and n < batch:
		spawn_car(true, ppos, 50.0 if initial else 80.0, 130.0)
		cop_cars += 1
		n += 1

func _despawn() -> void:
	var ppos := Game.player_pos()
	for p in get_tree().get_nodes_in_group("peds"):
		var ped := p as Ped
		if ped == null:
			continue
		var d := Game.flat(ped.global_position - ppos).length()
		if d > Game.DESPAWN_RADIUS and ped.ragdoll == null:
			ped.queue_free()
	for p in get_tree().get_nodes_in_group("corpses"):
		var ped := p as Ped
		if ped == null:
			continue
		var d := Game.flat(ped.global_position - ppos).length()
		var rd := ped.ragdoll
		var held := rd != null and is_instance_valid(rd) and rd.held_count > 0
		if not held and (d > 130.0 or (rd != null and is_instance_valid(rd) and rd.age > 75.0)):
			if rd and is_instance_valid(rd):
				rd.queue_free()
			ped.queue_free()
	for c in get_tree().get_nodes_in_group("cars"):
		var car := c as Car
		if car.mode == Car.Mode.PLAYER:
			continue
		var d := Game.flat(car.global_position - ppos).length()
		if d > 170.0 or (car.mode == Car.Mode.WRECK and car.age > 40.0 and d > 50.0):
			car.queue_free()
	for w in get_tree().get_nodes_in_group("weapons"):
		var wp := w as Weapon
		if wp.held_by == null and Game.flat(wp.global_position - ppos).length() > 150.0:
			wp.queue_free()

func _process(delta: float) -> void:
	frame += 1
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = 0.6
		_populate(false)
		_despawn()
	weapon_timer -= delta
	if weapon_timer <= 0.0:
		weapon_timer = 20.0
		var near := 0
		for w in get_tree().get_nodes_in_group("weapons"):
			if Game.flat(w.global_position - Game.player_pos()).length() < 60.0:
				near += 1
		if near < 6:
			var types := ["bat", "machete", "pistol", "shotgun", "smg", "axe", "knife"]
			var pos := Game.city.random_walk_point_near(Game.player_pos(), 8.0, 35.0)
			spawn_weapon(types[Game.randi_range(0, types.size() - 1)], pos + Vector3(0, 0.4, 0))
	if Game.autotest:
		_autotest()
	if shot_path != "":
		_screenshot_mode()
	if soak:
		_soak()

# ---------------------------------------------------------------- headless self-test
func _autotest() -> void:
	# Exercises the main code paths without a headset; used in CI / headless runs.
	match frame:
		30:
			print("[autotest] spawn & hit")
			var ped := spawn_ped_at(player.global_position + Vector3(0, 0, -2), false, false)
			var cop := spawn_ped_at(player.global_position + Vector3(2, 0, -2), true, true)
			await get_tree().physics_frame
			ped.take_hit(10.0, Vector3(0, 0, -50), ped.global_position + Vector3(0, 1.2, 0), "", "punch")
			cop.take_hit(80.0, Vector3(0, 0, -50), cop.global_position + Vector3(0, 1.6, 0), "", "sharp")
		60:
			print("[autotest] weapons")
			var w := spawn_weapon("shotgun", player.global_position + Vector3(0.3, 1.0, -0.3))
			await get_tree().physics_frame
			player.right.grab_body(w)
			player.right.held.set_trigger(true)
			player.right.held.set_trigger(false)
			var m := spawn_weapon("machete", player.global_position + Vector3(-0.3, 1.0, -0.3))
			await get_tree().physics_frame
			player.left.grab_body(m)
		90:
			print("[autotest] telekinesis + force push")
			player.right.release()
			var ped := spawn_ped_at(player.global_position + player.right.aim_dir() * 4.0, false, false)
			await get_tree().physics_frame
			player.right.tk_try_grab()
			player.right.tk_pull = true
			player.right.force_push()
		150:
			print("[autotest] tk release + car")
			player.right.velocity = Vector3(0, 0, -5)
			player.right.tk_release()
			var car := spawn_car(true, player.global_position, 0.0, 40.0)
			await get_tree().physics_frame
			player.global_position = car.door_global() + Vector3(0, 0.2, 0)
			player.enter_car(car)
			player.right.sim_trigger = 1.0
		215:
			if player.car:
				print("[autotest] driving: forward speed %.1f m/s (must be > 2)" % player.car.forward_speed())
		220:
			print("[autotest] explode + exit")
			player.right.sim_trigger = 0.0
			var c := player.car
			player.exit_car()
			if c:
				c.explode()
			player.take_damage(30.0, Vector3.ZERO)
			var ped := spawn_ped_at(player.global_position + Vector3(0, 0, -1.5), false, false)
			await get_tree().physics_frame
			player.right.grab_body(ped)
		240:
			print("[autotest] ragdoll joints + gore")
			player.right.release()
			var p1 := spawn_ped_at(player.global_position + Vector3(3, 0.2, 0), false, false)
			var p2 := spawn_ped_at(player.global_position + Vector3(-3, 0.2, 0), true, true)
			await get_tree().physics_frame
			p1.go_ragdoll(Vector3(0, 0, 0))
			var p3 := spawn_ped_at(player.global_position + Vector3(0, 0.2, 3), false, false)
			await get_tree().physics_frame
			p3.go_ragdoll(Vector3.ZERO)
			for rp in [p1, p3]:
				var rr: Ragdoll = rp.ragdoll
				for b in rr.bodies:
					b.freeze = true
				rr.bodies[BodyGen.B_FORE_R].freeze = false
				rr.bodies[BodyGen.B_SHIN_R].freeze = false
			# p1: push forearm + shin forward (-Z); p3: push them backward (+Z)
			var r1: Ragdoll = p1.ragdoll
			var r3: Ragdoll = p3.ragdoll
			for pair in [[r1, -1.0], [r3, 1.0]]:
				var rr: Ragdoll = pair[0]
				for bi in [BodyGen.B_FORE_R, BodyGen.B_SHIN_R]:
					var body: RigidBody3D = rr.bodies[bi]
					body.apply_impulse(body.global_transform.basis.z * pair[1] * 6.0, body.global_transform.basis * Vector3(0, -0.3, 0))
			test_ped3 = p3
			p2.take_hit(500.0, Vector3(0, 50, 0), p2.global_position + Vector3(0, 1.1, 0), "pelvis", "sharp")
			if p2.ragdoll:
				p2.ragdoll.dismember(BodyGen.B_CHEST, Vector3(0, 30, 0))
				p2.ragdoll.pop_head()
			test_ped = p1
		300:
			for pair in [[test_ped, "pushed forward"], [test_ped3, "pushed backward"]]:
				var tp: Ped = pair[0]
				if is_instance_valid(tp) and tp.ragdoll:
					var r := tp.ragdoll
					var elbow := _hinge_angle(r.bodies[BodyGen.B_ARM_R], r.bodies[BodyGen.B_FORE_R])
					var knee := _hinge_angle(r.bodies[BodyGen.B_THIGH_R], r.bodies[BodyGen.B_SHIN_R])
					print("[autotest] joints %s: elbow %.0f deg, knee %.0f deg (positive = forward)" % [pair[1], rad_to_deg(elbow), rad_to_deg(knee)])
		310:
			player.take_damage(500.0, Vector3.ZERO)
		335:
			print("[autotest] stats: peds=%d cars=%d ragdolls=%d score=%d wanted=%d" % [get_tree().get_nodes_in_group("peds").size(), get_tree().get_nodes_in_group("cars").size(), Ragdoll.count, Game.score, Game.wanted_stars])
		360:
			print("[autotest] done")
			get_tree().quit()

# ---------------------------------------------------------------- screenshot mode (desktop review)
var shot_car: Car
func _screenshot_mode() -> void:
	var cam := player.camera
	match frame:
		5:
			var base := player.global_position
			for c in get_tree().get_nodes_in_group("cars"):
				if c.global_position.distance_to(base) < 60.0:
					c.queue_free()
			for p in get_tree().get_nodes_in_group("peds"):
				if p.global_position.distance_to(base) < 25.0:
					p.queue_free()
			var node := Game.city.nearest_road_node(base)
			var nxt := Game.city.next_road_node(node, Vector2i(-9, -9), base + Vector3(30, 0, 0))
			shot_car = Car.create(true)
			add_child(shot_car)
			shot_car.place_on_road(node, nxt, 0.42)
			shot_car.mode = Car.Mode.PARKED
			shot_car.set_siren(true)
			var c2 := Car.create(false, Color(0.75, 0.75, 0.78), "suv")
			add_child(c2)
			c2.place_on_road(node, nxt, 0.62)
			c2.mode = Car.Mode.PARKED
		8:
			var door := shot_car.door_global()
			for i in 5:
				var p := spawn_ped_at(door + Vector3(Game.randf_range(-4, 4), 0.2, Game.randf_range(-5, 5)), i < 2, true)
				p.state = Ped.State.WANDER
			shot_cop = spawn_ped_at(player.global_position + Vector3(0.5, 0.0, -3.2), true, true)
			shot_cop.rotation.y = 0.0
		20:
			var i := 0
			for p in get_tree().get_nodes_in_group("peds"):
				if p != shot_cop and p.global_position.distance_to(shot_car.global_position) < 9.0 and i < 4:
					var part: String = ["head", "arm_l", "chest", "shin_r"][i]
					var kind: String = ["bullet", "sharp", "explosion", "sharp"][i]
					p.take_hit(400.0, Vector3(Game.randf_range(-40, 40), 60, Game.randf_range(-40, 40)), p.global_position + Vector3(0, 1.2, 0), part, kind)
					i += 1
		60:
			Game.wanted = 3.0
			Game._update_stars()
		140:
			var target := shot_car.global_position
			player.camera.top_level = true
			var side := shot_car.global_transform.basis.x
			cam.global_transform = Transform3D(Basis(), target + side * -6.5 + Vector3(0, 1.7, 0) + shot_car.global_transform.basis.z * 4.0).looking_at(target + Vector3(0, 0.7, 0), Vector3.UP)
		150:
			_save_shot("_street")
		151:
			var target := shot_car.global_position
			cam.global_transform = Transform3D(Basis(), target + Vector3(-30, 28, 40)).looking_at(target + Vector3(0, 4, -20), Vector3.UP)
		160:
			_save_shot("_city")
		161:
			if is_instance_valid(shot_cop):
				var h := shot_cop.global_position + Vector3(0, 1.6, 0)
				cam.global_transform = Transform3D(Basis(), h + shot_cop.global_transform.basis.z * -2.3 + Vector3(0.6, 0.05, 0)).looking_at(h - Vector3(0, 0.25, 0), Vector3.UP)
		170:
			_save_shot("_cop")
		171:
			var focus := shot_car.global_position
			for r in get_children():
				if r is Ragdoll:
					focus = (r as Ragdoll).torso().global_position
					break
			cam.global_transform = Transform3D(Basis(), focus + Vector3(2.4, 1.8, 2.4)).looking_at(focus, Vector3.UP)
		180:
			_save_shot("_gore")
		181:
			cam.top_level = false
			cam.transform = Transform3D.IDENTITY
			cam.position = Vector3(0, 1.7, 0)
			player.origin.rotation.y = PI * 0.5
		190:
			_save_shot("_eye")
			get_tree().quit()

var shot_cop: Ped

## Long unattended run with a high wanted level (catches runtime errors).
func _soak() -> void:
	player.health = 100.0
	if frame % 300 == 1:
		Game.wanted = 4.0
		Game._update_stars()
		print("[soak] t=%ds peds=%d cops=%d cars=%d ragdolls=%d fps=%d" % [frame / 60, get_tree().get_nodes_in_group("peds").size(), get_tree().get_nodes_in_group("cops").size(), get_tree().get_nodes_in_group("cars").size(), Ragdoll.count, Engine.get_frames_per_second()])
		# stir things up: push and hit people around the player
		player.right.force_push()
		for p in get_tree().get_nodes_in_group("peds"):
			if p.global_position.distance_to(player.global_position) < 20.0 and Game.rng.randf() < 0.3:
				p.take_hit(60.0, Vector3(0, 30, 0), p.global_position + Vector3(0, 1.0, 0), "", ["punch", "sharp", "bullet", "throw"][Game.randi_range(0, 3)])
	if frame > 2400:
		print("[soak] done")
		get_tree().quit()

var test_ped: Ped
var test_ped3: Ped

## Signed bend of child relative to parent around the parent's X axis.
## Positive = the child swung towards the parent's -Z (forward).
func _hinge_angle(parent: RigidBody3D, child: RigidBody3D) -> float:
	var rel := parent.global_transform.basis.inverse() * child.global_transform.basis
	var down := rel * Vector3.DOWN
	return atan2(-down.z, -down.y)

func _save_shot(suffix: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := shot_path.replace(".png", suffix + ".png")
	img.save_png(path)
	print("[screenshot] saved %s  draw_calls=%d objects=%d primitives=%d" % [path,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
