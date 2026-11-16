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

func _ready() -> void:
	Game.main = self
	for a in OS.get_cmdline_user_args():
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

func _spawn_props() -> void:
	var city := Game.city
	var mats := [MeshLib.mat(Color(0.3, 0.32, 0.35), 0.6, 0.5), MeshLib.mat(Color(0.6, 0.45, 0.25), 0.9), MeshLib.mat(Color(0.2, 0.5, 0.2), 0.7, 0.3), MeshLib.mat(Color(0.95, 0.4, 0.1), 0.8)]
	for i in 44:
		var n := city.random_walk_node()
		var pos := city.walk_pos(n.x, n.y) + Vector3(Game.randf_range(-1.0, 1.0), 0.5, Game.randf_range(-1.0, 1.0))
		var rb := RigidBody3D.new()
		rb.collision_layer = Game.bit(Game.L_PROP)
		rb.collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP, Game.L_RAGDOLL, Game.L_PLAYER])
		rb.mass = 12.0
		rb.can_sleep = true
		var kind := i % 4
		if kind == 0:
			MeshLib.inst(MeshLib.cylinder(0.35, 0.9, 8), mats[0], Vector3.ZERO, Vector3.ZERO, rb)
			MeshLib.collider(MeshLib.capsule_shape(0.35, 1.0), Vector3.ZERO, Vector3.ZERO, rb)
		elif kind == 1:
			MeshLib.inst(MeshLib.box(Vector3(0.8, 0.8, 0.8)), mats[1], Vector3.ZERO, Vector3.ZERO, rb)
			MeshLib.collider(MeshLib.box_shape(Vector3(0.8, 0.8, 0.8)), Vector3.ZERO, Vector3.ZERO, rb)
		elif kind == 2:
			MeshLib.inst(MeshLib.cylinder(0.3, 0.95, 8), mats[2], Vector3.ZERO, Vector3.ZERO, rb)
			MeshLib.collider(MeshLib.capsule_shape(0.3, 1.05), Vector3.ZERO, Vector3.ZERO, rb)
		else:
			MeshLib.inst(MeshLib.cone(0.25, 0.7, 7), mats[3], Vector3.ZERO, Vector3.ZERO, rb)
			MeshLib.collider(MeshLib.box_shape(Vector3(0.4, 0.7, 0.4)), Vector3.ZERO, Vector3.ZERO, rb)
			rb.mass = 3.0
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
			var car := spawn_car(true, player.global_position, 0.0, 30.0)
			await get_tree().physics_frame
			car.global_position = player.global_position + Vector3(2.5, 0.4, 0)
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
		260:
			player.right.release()
			player.take_damage(500.0, Vector3.ZERO)
		330:
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
			shot_car = spawn_car(true, base, 0.0, 30.0)
			var node := Game.city.nearest_road_node(base)
			var nxt := Game.city.next_road_node(node, Vector2i(-9, -9), base)
			shot_car.place_on_road(node, nxt, 0.55)
			shot_car.mode = Car.Mode.PARKED
			shot_car.set_siren(true)
			for i in 6:
				var p := spawn_ped_at(shot_car.global_position + Vector3(Game.randf_range(-5, 5), 0, Game.randf_range(-5, 5)), i % 2 == 0, true)
		20:
			var i := 0
			for p in get_tree().get_nodes_in_group("peds"):
				if p.global_position.distance_to(shot_car.global_position) < 8.0 and i < 4:
					var part: String = ["head", "arm_l", "torso", "leg_r"][i]
					var kind: String = ["bullet", "sharp", "explosion", "sharp"][i]
					p.take_hit(400.0, Vector3(Game.randf_range(-40, 40), 60, Game.randf_range(-40, 40)), p.global_position + Vector3(0, 1.2, 0), part, kind)
					i += 1
		140:
			var target := shot_car.global_position
			player.camera.top_level = true
			cam.global_transform = Transform3D(Basis(), target + Vector3(7.5, 3.2, 7.5)).looking_at(target + Vector3(0, 0.6, 0), Vector3.UP)
		150:
			_save_shot("_street")
		151:
			var target := shot_car.global_position
			cam.global_transform = Transform3D(Basis(), target + Vector3(-30, 28, 40)).looking_at(target + Vector3(0, 4, -20), Vector3.UP)
		160:
			_save_shot("_city")
		161:
			cam.global_transform = Transform3D(Basis(), player.global_position + Vector3(0, 1.7, 0)).looking_at(player.global_position + Vector3(0, 1.6, -5), Vector3.UP)
		170:
			_save_shot("_spawn")
		171:
			var focus := shot_car.global_position
			for r in get_children():
				if r is Ragdoll:
					focus = (r as Ragdoll).torso().global_position
					break
			cam.global_transform = Transform3D(Basis(), focus + Vector3(2.6, 1.9, 2.6)).looking_at(focus, Vector3.UP)
		180:
			_save_shot("_gore")
			get_tree().quit()

func _save_shot(suffix: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := shot_path.replace(".png", suffix + ".png")
	img.save_png(path)
	print("[screenshot] saved %s  draw_calls=%d objects=%d primitives=%d" % [path,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
