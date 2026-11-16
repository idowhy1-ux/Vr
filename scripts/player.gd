class_name Player
extends CharacterBody3D
## VR player body: XR origin + camera + two hands, smooth locomotion, snap
## turning, super jump, bullet time, health/death, and driving stolen cars.

var origin: XROrigin3D
var camera: XRCamera3D
var left: Hand
var right: Hand
var col: CollisionShape3D
var health := 100.0
var dead := false
var car: Car = null
var last_damage := 0.0
var snap_ready := true
var vel_est := Vector3.ZERO
var last_pos := Vector3.ZERO
var bullet_time := 0.0
var bullet_cd := 0.0
var knock := Vector3.ZERO
var a_prev := false
var b_prev := false
var x_prev := false
var y_prev := false
var respawn_t := 0.0
var fade: MeshInstance3D
var desk_yaw := 0.0
var desk_pitch := 0.0
var start_height := 1.7
# desktop sim
var sim_a := false
var sim_b := false
var sim_x := false
var sim_y := false
var sim_stick_r := Vector2.ZERO

func _ready() -> void:
	collision_layer = Game.bit(Game.L_PLAYER)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP])
	floor_max_angle = deg_to_rad(50)
	col = MeshLib.collider(MeshLib.capsule_shape(0.28, 1.6), Vector3(0, 0.85, 0), Vector3.ZERO, self)
	origin = XROrigin3D.new()
	origin.name = "Origin"
	add_child(origin)
	camera = XRCamera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 600.0
	origin.add_child(camera)
	camera.current = true
	left = Hand.new()
	left.side = "left"
	left.player = self
	left.name = "LeftHand"
	origin.add_child(left)
	right = Hand.new()
	right.side = "right"
	right.player = self
	right.name = "RightHand"
	origin.add_child(right)
	# death / damage fade quad in front of the camera
	fade = MeshInstance3D.new()
	fade.mesh = MeshLib.quad(Vector2(2.0, 2.0))
	fade.material_override = _fade_mat(0.0)
	fade.position = Vector3(0, 0, -0.3)
	fade.visible = false
	camera.add_child(fade)
	if Game.desktop_mode:
		camera.position = Vector3(0, 1.7, 0)
		_place_desktop_hands()
	last_pos = global_position

func _fade_mat(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.0, 0.0, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = 100
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ---------------------------------------------------------------- inputs
func btn(name: String, hand: Hand) -> bool:
	if Game.desktop_mode:
		match name:
			"ax_button":
				return sim_a if hand == right else sim_x
			"by_button":
				return sim_b if hand == right else sim_y
		return false
	return hand.is_button_pressed(name)

func is_armed() -> bool:
	return left.is_holding_weapon() or right.is_holding_weapon() or left.is_tk_active() or right.is_tk_active()

func get_velocity_estimate() -> Vector3:
	return vel_est

func head_yaw() -> float:
	return camera.global_transform.basis.get_euler().y

# ---------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	vel_est = vel_est.lerp((global_position - last_pos) / maxf(delta, 0.0001), 0.3)
	last_pos = global_position
	_update_bullet_time(delta)
	if dead:
		respawn_t -= delta
		if respawn_t <= 0.0:
			respawn()
		return
	if health < 100.0 and Time.get_ticks_msec() / 1000.0 - last_damage > 6.0:
		health = minf(100.0, health + 5.0 * delta)
	_update_fade()
	var a := btn("ax_button", right)
	var b := btn("by_button", right)
	var x := btn("ax_button", left)
	var y := btn("by_button", left)
	if b and not b_prev:
		if car:
			exit_car()
		else:
			_try_enter_car()
	if x and not x_prev and bullet_cd <= 0.0 and bullet_time <= 0.0:
		start_bullet_time()
	if y and not y_prev:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	if car and is_instance_valid(car):
		_drive(delta, a)
	else:
		_walk(delta, a)
	a_prev = a
	b_prev = b
	x_prev = x
	y_prev = y

func _process(_delta: float) -> void:
	# Re-seat after the physics step so the view never lags one step behind the car.
	if car and is_instance_valid(car) and not dead:
		_sync_car()

func start_bullet_time() -> void:
	bullet_time = 4.0
	bullet_cd = 12.0
	Engine.time_scale = 0.35
	# Keep ~90 physics steps per real second so hands and held objects stay smooth.
	Engine.physics_ticks_per_second = int(round(Game.base_physics_rate / 0.35))
	Game.sfx.play("tk_grab", global_position, -4.0, 0.5)
	Game.show_message("BULLET TIME")

func end_bullet_time() -> void:
	bullet_time = 0.0
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = Game.base_physics_rate

func _update_bullet_time(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	bullet_cd = maxf(0.0, bullet_cd - real)
	if bullet_time > 0.0:
		bullet_time -= real
		if bullet_time <= 0.0:
			end_bullet_time()

func _walk(delta: float, jump: bool) -> void:
	# keep the physics capsule under the headset
	var cam_local := camera.position
	var head_global := camera.global_position
	var off := Vector3(head_global.x - global_position.x, 0.0, head_global.z - global_position.z)
	if off.length() > 0.001:
		global_position += off
		origin.global_position -= off
	var h := clampf(cam_local.y, 0.6, 2.3)
	(col.shape as CapsuleShape3D).height = h
	col.position.y = h * 0.5
	# locomotion relative to the head
	var stick := left.stick() if not left.is_tk_active() else Vector2.ZERO
	var yaw := head_yaw()
	var dir := Vector3(stick.x, 0.0, -stick.y).rotated(Vector3.UP, yaw)
	var speed := 5.2 / maxf(Engine.time_scale, 0.05)
	velocity.x = dir.x * speed + knock.x
	velocity.z = dir.z * speed + knock.z
	knock = knock.lerp(Vector3.ZERO, 6.0 * delta)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
		if jump and not a_prev:
			velocity.y = 8.5
			Game.sfx.play("jump", global_position, -8.0)
	else:
		velocity.y -= 14.0 * delta
	move_and_slide()
	# snap turn with the right stick
	var rs := right.stick() if not right.is_tk_active() else Vector2.ZERO
	if absf(rs.x) > 0.65:
		if snap_ready:
			snap_turn(-signf(rs.x) * deg_to_rad(40.0))
			snap_ready = false
	elif absf(rs.x) < 0.3:
		snap_ready = true
	if Game.desktop_mode:
		_desktop_update()

func snap_turn(angle: float) -> void:
	var cam_pos := camera.global_position
	origin.global_rotate(Vector3.UP, angle)
	origin.global_position += cam_pos - camera.global_position

# ---------------------------------------------------------------- cars
func _try_enter_car() -> void:
	var best: Car = null
	var bd := 3.2
	for c in get_tree().get_nodes_in_group("cars"):
		var car_n := c as Car
		if car_n.mode == Car.Mode.WRECK:
			continue
		var d := Game.flat(car_n.global_position - global_position).length()
		if d < bd:
			bd = d
			best = car_n
	if best:
		enter_car(best)

func enter_car(c: Car) -> void:
	car = c
	if c.has_driver:
		var impulse := -c.global_transform.basis.x * 180.0 + Vector3.UP * 60.0
		c.eject_driver(impulse)
	c.enter_player()
	collision_layer = 0
	collision_mask = 0
	col.disabled = true
	velocity = Vector3.ZERO
	# seat the head: rotate the origin so the user faces the windshield
	var cam_local := camera.position
	var cam_yaw := camera.transform.basis.get_euler().y
	origin.transform = Transform3D(Basis(Vector3.UP, -cam_yaw), Vector3.ZERO)
	origin.position = -(origin.transform.basis * Vector3(cam_local.x, cam_local.y - 0.0, cam_local.z))
	Game.sfx.play("enter_car", global_position, -4.0)
	Game.show_message("B = EXIT   R TRIGGER = GAS   L TRIGGER = BRAKE")
	_sync_car()

func exit_car() -> void:
	if car == null:
		return
	var c := car
	car = null
	c.exit_player()
	var yaw := c.global_transform.basis.get_euler().y
	var door := c.door_global()
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(door.x, Game.city.ground_height(door) + 0.05, door.z))
	collision_layer = Game.bit(Game.L_PLAYER)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP])
	col.disabled = false
	var cam_local := camera.position
	origin.position = -(origin.transform.basis * Vector3(cam_local.x, 0.0, cam_local.z))
	origin.position.y = 0.0

func _sync_car() -> void:
	var seat := car.seat_global()
	var yaw := car.global_transform.basis.get_euler().y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), seat.origin)

func _drive(delta: float, _a: bool) -> void:
	if car.mode == Car.Mode.WRECK:
		exit_car()
		return
	_sync_car()
	var gas := right.trig()
	var brk := left.trig() if not left.is_holding_gun() else 0.0
	if right.grip():
		brk = maxf(brk, 1.0)
	var steer := left.stick().x
	car.player_control(gas, brk, steer, false)
	if Game.desktop_mode:
		_desktop_update()

# ---------------------------------------------------------------- damage
func take_damage(dmg: float, knockback: Vector3 = Vector3.ZERO) -> void:
	if dead or Game.screenshot:
		return
	health -= dmg
	last_damage = Time.get_ticks_msec() / 1000.0
	knock += knockback
	if right:
		right.haptic(0.7, 0.15)
		left.haptic(0.7, 0.15)
	Game.sfx.play("grunt", global_position, -4.0, 0.7)
	if health <= 0.0:
		die()

func _update_fade() -> void:
	var a := clampf((45.0 - health) / 45.0, 0.0, 0.55)
	var since := Time.get_ticks_msec() / 1000.0 - last_damage
	if since < 0.25:
		a = maxf(a, 0.45)
	fade.visible = a > 0.01
	if fade.visible:
		fade.material_override.albedo_color = Color(0.5, 0.0, 0.0, a)

func die() -> void:
	dead = true
	health = 0.0
	respawn_t = 4.0
	end_bullet_time()
	left.release(false)
	right.release(false)
	left.tk_release(false)
	right.tk_release(false)
	if car:
		exit_car()
	fade.visible = true
	fade.material_override.albedo_color = Color(0.4, 0.0, 0.0, 0.85)
	Game.sfx.play("dead", global_position, 2.0, 0.6)
	Game.show_message("WASTED")

func respawn() -> void:
	dead = false
	health = 100.0
	Game.wanted = 0.0
	Game._update_stars()
	for c in get_tree().get_nodes_in_group("cops"):
		if c is Ped:
			c.state = Ped.State.WANDER
	var p := Game.city.random_walk_point_near(global_position, 25.0, 60.0)
	global_position = Vector3(p.x, p.y + 0.1, p.z)
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	fade.visible = false
	Game.show_message("BACK ON THE STREET")

# ---------------------------------------------------------------- desktop test controls
func _desktop_update() -> void:
	if Game.autotest or Game.screenshot:
		return
	var s := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		s.y += 1.0
	if Input.is_key_pressed(KEY_S):
		s.y -= 1.0
	if Input.is_key_pressed(KEY_D):
		s.x += 1.0
	if Input.is_key_pressed(KEY_A):
		s.x -= 1.0
	left.sim_stick = s
	right.sim_stick = Vector2(0, 0)
	right.sim_trigger = 1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.0
	right.sim_grip = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	left.sim_trigger = 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0
	left.sim_grip = Input.is_key_pressed(KEY_Q)
	right.sim_click = Input.is_key_pressed(KEY_F)
	sim_a = Input.is_key_pressed(KEY_SPACE)
	sim_b = Input.is_key_pressed(KEY_E)
	sim_x = Input.is_key_pressed(KEY_T)
	camera.position = Vector3(0, 1.7, 0)
	camera.rotation = Vector3(desk_pitch, 0, 0)
	origin.rotation.y = desk_yaw
	_place_desktop_hands()

## Without a headset: hold both hands in front of the camera, aimed forward.
func _place_desktop_hands() -> void:
	var inv := Hand.grip_to_aim().affine_inverse()
	for h in [left, right]:
		var x := -0.22 if h == left else 0.22
		var aim := Transform3D(Basis(Vector3.RIGHT, desk_pitch), Vector3(x, 1.4, -0.38).rotated(Vector3.RIGHT, desk_pitch))
		(h as Node3D).transform = aim * inv

func _unhandled_input(event: InputEvent) -> void:
	if not Game.desktop_mode:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		desk_yaw -= event.relative.x * 0.003
		desk_pitch = clampf(desk_pitch - event.relative.y * 0.003, -1.4, 1.4)
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
