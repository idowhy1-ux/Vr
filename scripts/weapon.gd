class_name Weapon
extends RigidBody3D
## Grabbable melee and ranged weapons built from primitives.

const TYPES := {
	"bat": {"melee": true, "damage": 34.0, "sharp": false, "length": 0.85, "label": "BAT"},
	"machete": {"melee": true, "damage": 45.0, "sharp": true, "length": 0.6, "label": "MACHETE"},
	"knife": {"melee": true, "damage": 28.0, "sharp": true, "length": 0.3, "label": "KNIFE"},
	"axe": {"melee": true, "damage": 60.0, "sharp": true, "length": 0.75, "label": "AXE"},
	"baton": {"melee": true, "damage": 22.0, "sharp": false, "length": 0.55, "label": "BATON"},
	"pistol": {"melee": false, "damage": 34.0, "rate": 0.18, "auto": false, "pellets": 1, "spread": 0.012, "label": "PISTOL", "sound": "pistol", "kick": 0.03},
	"shotgun": {"melee": false, "damage": 22.0, "rate": 0.75, "auto": false, "pellets": 9, "spread": 0.07, "label": "SHOTGUN", "sound": "shotgun", "kick": 0.08},
	"smg": {"melee": false, "damage": 16.0, "rate": 0.075, "auto": true, "pellets": 1, "spread": 0.035, "label": "SMG", "sound": "smg", "kick": 0.015},
}

var type := "bat"
var cfg: Dictionary
var held_by: Node3D = null
var blade: Area3D
var muzzle: Node3D
var flash: MeshInstance3D
var fire_cd := 0.0
var trigger_held := false
var hit_cd: Dictionary = {}
var kick := 0.0
var visual: Node3D

static func create(weapon_type: String) -> Weapon:
	var w := Weapon.new()
	w.type = weapon_type
	return w

func _ready() -> void:
	cfg = TYPES[type]
	add_to_group("weapons")
	mass = 2.0
	collision_layer = Game.bit(Game.L_PROP)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP, Game.L_RAGDOLL])
	continuous_cd = true
	linear_damp = 0.3
	angular_damp = 1.0
	set_meta("weapon", true)
	visual = Node3D.new()
	add_child(visual)
	_build()
	if cfg["melee"]:
		blade = Area3D.new()
		blade.collision_layer = 0
		blade.collision_mask = Game.mask([Game.L_NPC, Game.L_RAGDOLL, Game.L_CAR, Game.L_PROP])
		blade.monitoring = false
		var len: float = cfg["length"]
		MeshLib.collider(MeshLib.box_shape(Vector3(0.12, 0.12, len)), Vector3(0, 0, -len * 0.5 - 0.05), Vector3.ZERO, blade)
		add_child(blade)
		blade.body_entered.connect(_on_blade_hit)

static var _mesh_cache: Dictionary = {}

const WOOD := Color(0.55, 0.36, 0.18)
const DARK_WOOD := Color(0.32, 0.18, 0.09)
const STEEL := Color(0.8, 0.81, 0.84)
const GUNMETAL := Color(0.13, 0.13, 0.14)
const POLYMER := Color(0.09, 0.09, 0.1)
const RUBBER := Color(0.05, 0.05, 0.05)

## Smooth visual mesh for a weapon type (grip at the origin, pointing -Z).
static func visual_mesh(t: String) -> ArrayMesh:
	if _mesh_cache.has(t):
		return _mesh_cache[t]
	var g := Geo.new()
	var to_fwd := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0))   # lathe Y axis -> -Z
	match t:
		"bat":
			g.xf = to_fwd
			# knob behind the fist (+Z), barrel forward (-Z); lathe Y maps to -Z
			g.mat(RUBBER, 0.9).lathe([Vector2(0.0, -0.075), Vector2(0.024, -0.074), Vector2(0.027, -0.066), Vector2(0.017, -0.056), Vector2(0.0145, -0.03), Vector2(0.0145, 0.17)], 12, true, false)
			g.mat(WOOD, 0.55).lathe([Vector2(0.0145, 0.17), Vector2(0.015, 0.24), Vector2(0.02, 0.37), Vector2(0.029, 0.52), Vector2(0.0335, 0.66), Vector2(0.034, 0.74), Vector2(0.03, 0.765), Vector2(0.0, 0.775)], 14, false, true)
		"baton":
			g.xf = to_fwd
			g.mat(RUBBER, 0.7).lathe([Vector2(0.0, -0.07), Vector2(0.019, -0.068), Vector2(0.019, 0.09), Vector2(0.0, 0.092)], 10)
			g.mat(POLYMER, 0.35, 0.2).lathe([Vector2(0.0, 0.09), Vector2(0.015, 0.09), Vector2(0.014, 0.5), Vector2(0.016, 0.52), Vector2(0.0, 0.53)], 10)
			g.xf = Transform3D.IDENTITY
			g.mat(POLYMER, 0.4).capsule(Vector3(0, 0, -0.07), Vector3(0, -0.13, -0.07), 0.012, 0.012, 8, 2)
		"knife":
			g.mat(POLYMER, 0.6).rbox(Vector3(0, -0.005, -0.04), Vector3(0.024, 0.03, 0.12), 0.01, 2)
			g.mat(STEEL, 0.3, 1.0).rbox(Vector3(0, 0.0, -0.105), Vector3(0.03, 0.045, 0.012), 0.004, 1)
			_blade(g, -0.11, 0.2, 0.034, 0.0035, 0.0)
		"machete":
			g.mat(DARK_WOOD, 0.6).rbox(Vector3(0, -0.005, -0.06), Vector3(0.026, 0.034, 0.14), 0.011, 2)
			g.mat(STEEL, 0.3, 1.0).rbox(Vector3(0, -0.0, -0.13), Vector3(0.022, 0.05, 0.012), 0.004, 1)
			_blade(g, -0.135, 0.48, 0.055, 0.003, 0.02)
		"axe":
			var curve := []
			for i in 8:
				var tt := float(i) / 7.0
				curve.append(Geo.ring_axis(Vector3(0, 0.012 * sin(tt * PI), -0.03 - tt * 0.68), Vector3.FORWARD, 0.016 + 0.004 * sin(tt * PI * 0.5), 0.02 + 0.004 * sin(tt * PI * 0.5), 10))
			g.mat(WOOD, 0.6).loft(curve, true, true)
			# axe head: wedge lofted along +Y (blade edge thin)
			var head := []
			for k in 5:
				var y := -0.03 + k * 0.045
				var th := lerpf(0.022, 0.003, clampf(float(k - 1) / 3.0, 0.0, 1.0))
				var ln := lerpf(0.06, 0.13, float(k) / 4.0)
				head.append(Geo.ring(y, th, ln * 0.5, ln * 0.5, 10, 4.0, Vector2(0, -0.69)))
			g.mat(GUNMETAL, 0.4, 0.9).loft(head, true, true)
			g.mat(STEEL, 0.18, 1.0).rbox(Vector3(0, 0.152, -0.69), Vector3(0.004, 0.012, 0.13), 0.002, 1)
		"pistol":
			g.mat(GUNMETAL, 0.35, 0.8).rbox(Vector3(0, 0.032, -0.085), Vector3(0.029, 0.033, 0.19), 0.006, 2)
			g.mat(POLYMER, 0.55).rbox(Vector3(0, 0.006, -0.075), Vector3(0.027, 0.022, 0.16), 0.006, 2)
			g.xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(16)), Vector3(0, -0.03, 0.0))
			g.mat(POLYMER, 0.75).rbox(Vector3.ZERO, Vector3(0.029, 0.105, 0.046), 0.01, 2)
			g.xf = Transform3D.IDENTITY
			g.mat(POLYMER, 0.5).capsule(Vector3(0, -0.012, -0.03), Vector3(0, -0.012, -0.075), 0.004, 0.004, 6, 1)
			g.mat(POLYMER, 0.5).capsule(Vector3(0, -0.012, -0.075), Vector3(0, 0.0, -0.08), 0.004, 0.004, 6, 1)
			g.mat(GUNMETAL, 0.4, 0.8).rbox(Vector3(0, -0.006, -0.052), Vector3(0.006, 0.018, 0.006), 0.002, 1)
			g.mat(RUBBER, 0.3).rbox(Vector3(0, 0.051, -0.172), Vector3(0.006, 0.008, 0.006), 0.001, 1)
			g.mat(RUBBER, 0.3).rbox(Vector3(0, 0.051, 0.0), Vector3(0.016, 0.008, 0.006), 0.001, 1)
			g.xf = to_fwd
			g.mat(RUBBER, 0.3).lathe([Vector2(0.0072, 0.17), Vector2(0.0072, 0.181), Vector2(0.0, 0.181)], 10, false, true)
		"shotgun":
			g.xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.04, 0))
			g.mat(GUNMETAL, 0.3, 0.85).lathe([Vector2(0.0, 0.0), Vector2(0.0125, 0.0), Vector2(0.0125, 0.72), Vector2(0.0, 0.72)], 12)
			g.xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.014, 0))
			g.mat(GUNMETAL, 0.4, 0.7).lathe([Vector2(0.0, 0.1), Vector2(0.011, 0.1), Vector2(0.011, 0.66), Vector2(0.0, 0.66)], 10)
			g.xf = Transform3D.IDENTITY
			g.mat(DARK_WOOD, 0.55).rbox(Vector3(0, 0.018, -0.36), Vector3(0.042, 0.04, 0.2), 0.016, 2)
			g.mat(GUNMETAL, 0.35, 0.8).rbox(Vector3(0, 0.03, -0.03), Vector3(0.04, 0.06, 0.24), 0.008, 2)
			g.mat(GUNMETAL, 0.35, 0.8).capsule(Vector3(0, -0.005, 0.0), Vector3(0, -0.005, -0.05), 0.004, 0.004, 6, 1)
			g.xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12)), Vector3(0, 0.0, 0.22))
			var stock := []
			for k in 6:
				var z := -0.2 + k * 0.074
				var h := lerpf(0.045, 0.072, float(k) / 5.0)
				stock.append(Geo.ring_axis(Vector3(0, -0.012 - h * 0.3, z), Vector3.BACK, 0.019, h, 10))
			g.mat(DARK_WOOD, 0.5).loft(stock, true, true)
			g.xf = Transform3D.IDENTITY
			g.mat(RUBBER, 0.8).rbox(Vector3(0, -0.04, 0.395), Vector3(0.04, 0.14, 0.02), 0.008, 1)
		"smg":
			g.mat(POLYMER, 0.45, 0.2).rbox(Vector3(0, 0.03, -0.12), Vector3(0.045, 0.06, 0.3), 0.01, 2)
			g.mat(GUNMETAL, 0.35, 0.8).rbox(Vector3(0, 0.067, -0.12), Vector3(0.022, 0.015, 0.24), 0.004, 1)
			g.xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.035, -0.27))
			g.mat(GUNMETAL, 0.4, 0.8).lathe([Vector2(0.0, 0.0), Vector2(0.016, 0.0), Vector2(0.016, 0.1), Vector2(0.009, 0.1), Vector2(0.009, 0.19), Vector2(0.0, 0.19)], 10)
			g.xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(12)), Vector3(0, -0.035, 0.0))
			g.mat(POLYMER, 0.75).rbox(Vector3.ZERO, Vector3(0.03, 0.1, 0.042), 0.01, 2)
			g.xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(6)), Vector3(0, -0.06, -0.14))
			g.mat(GUNMETAL, 0.5, 0.6).rbox(Vector3.ZERO, Vector3(0.026, 0.15, 0.034), 0.006, 1)
			g.xf = Transform3D.IDENTITY
			g.mat(POLYMER, 0.6).rbox(Vector3(0, -0.02, -0.235), Vector3(0.026, 0.07, 0.03), 0.01, 1)
			g.mat(GUNMETAL, 0.4, 0.8).capsule(Vector3(0, 0.03, 0.03), Vector3(0, 0.03, 0.2), 0.007, 0.007, 6, 1)
			g.mat(GUNMETAL, 0.4, 0.8).capsule(Vector3(0, -0.02, 0.06), Vector3(0, -0.02, 0.2), 0.006, 0.006, 6, 1)
			g.mat(RUBBER, 0.8).rbox(Vector3(0, 0.005, 0.205), Vector3(0.03, 0.08, 0.016), 0.006, 1)
	var m := g.mesh()
	_mesh_cache[t] = m
	return m

## Flat tapered blade lofted forward from z0, with a sharpened edge on the
## bottom and an optional upward curve near the tip.
static func _blade(g: Geo, z0: float, length: float, height: float, thick: float, curve: float) -> void:
	var rings := []
	var n := 7
	for k in n + 1:
		var tt := float(k) / n
		var z := z0 - tt * length
		var h := height * (1.0 - pow(tt, 3.0) * 0.85) if k < n else 0.004
		var yc := curve * tt * tt + (height * 0.5 * pow(tt, 2.5) if curve == 0.0 else 0.0)
		var ring := PackedVector3Array()
		# diamond-ish cross-section: thick spine on top, sharp edge at the bottom
		ring.append(Vector3(0, yc + h * 0.5, z))
		ring.append(Vector3(thick * 0.5, yc + h * 0.38, z))
		ring.append(Vector3(thick * 0.35, yc - h * 0.1, z))
		ring.append(Vector3(0, yc - h * 0.5, z))
		ring.append(Vector3(-thick * 0.35, yc - h * 0.1, z))
		ring.append(Vector3(-thick * 0.5, yc + h * 0.38, z))
		rings.append(ring)
	g.mat(STEEL, 0.22, 1.0).loft(rings, true, true)

func _build() -> void:
	match type:
		"bat":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.07, 0.07, 0.85)), Vector3(0, 0, -0.35), Vector3.ZERO, self)
		"baton":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.05, 0.05, 0.6)), Vector3(0, 0, -0.23), Vector3.ZERO, self)
		"machete":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.04, 0.07, 0.66)), Vector3(0, 0, -0.3), Vector3.ZERO, self)
		"knife":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.035, 0.05, 0.33)), Vector3(0, 0, -0.14), Vector3.ZERO, self)
		"axe":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.05, 0.2, 0.78)), Vector3(0, 0.05, -0.36), Vector3.ZERO, self)
		"pistol":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.04, 0.14, 0.2)), Vector3(0, 0, -0.07), Vector3.ZERO, self)
			_muzzle(Vector3(0, 0.032, -0.19))
		"shotgun":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.05, 0.12, 1.1)), Vector3(0, 0.01, -0.2), Vector3.ZERO, self)
			_muzzle(Vector3(0, 0.04, -0.73))
		"smg":
			MeshLib.collider(MeshLib.box_shape(Vector3(0.05, 0.2, 0.55)), Vector3(0, 0, -0.08), Vector3.ZERO, self)
			_muzzle(Vector3(0, 0.035, -0.47))
	var mi := MeshInstance3D.new()
	mi.mesh = visual_mesh(type)
	mi.material_override = MeshLib.atlas()
	mi.visibility_range_end = 60.0
	visual.add_child(mi)

func _muzzle(pos: Vector3) -> void:
	muzzle = Node3D.new()
	muzzle.position = pos
	visual.add_child(muzzle)
	flash = MeshLib.inst(MeshLib.sphere(0.06, 6, 4), MeshLib.mat(Color(1, 0.9, 0.5), 1.0, 0.0, Color(1.0, 0.8, 0.3), 4.0), Vector3(0, 0, -0.04), Vector3.ZERO, muzzle)
	flash.visible = false

func label() -> String:
	return cfg["label"]

func is_gun() -> bool:
	return not cfg["melee"]

# ---------------------------------------------------------------- grabbing
func on_grab(hand: Node3D) -> void:
	held_by = hand
	freeze = true
	collision_layer = 0
	collision_mask = 0
	hit_cd.clear()
	reparent(hand, false)
	if hand.has_method("weapon_hold"):
		transform = hand.weapon_hold(self)
	else:
		transform = Transform3D(Basis(), Vector3(0, -0.03, 0.015))
	if blade:
		blade.monitoring = true
	Game.sfx.play("pickup", global_position, -8.0)

func on_release(velocity: Vector3, ang: Vector3) -> void:
	var gt := global_transform
	held_by = null
	trigger_held = false
	reparent(Game.main, true)
	global_transform = gt
	freeze = false
	collision_layer = Game.bit(Game.L_PROP)
	collision_mask = Game.mask([Game.L_WORLD, Game.L_CAR, Game.L_PROP, Game.L_RAGDOLL])
	linear_velocity = velocity
	angular_velocity = ang
	if blade:
		blade.monitoring = false

# ---------------------------------------------------------------- melee
func _on_blade_hit(body: Node) -> void:
	if held_by == null:
		return
	var h := held_by
	var hand_v: Vector3 = h.get("velocity") if h.get("velocity") != null else Vector3.ZERO
	var ang_v: Vector3 = h.get("ang_velocity") if h.get("ang_velocity") != null else Vector3.ZERO
	var tip := global_transform * Vector3(0, 0, -cfg["length"])
	var v: Vector3 = hand_v + ang_v.cross(tip - h.global_position)
	var speed := v.length()
	if speed < 2.2:
		return
	if Game.player and body == Game.player.car:
		return
	var id := body.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if hit_cd.has(id) and now - hit_cd[id] < 0.35:
		return
	hit_cd[id] = now
	var target := Game.hittable_of(body)
	if target == null:
		if body is RigidBody3D:
			body.apply_central_impulse(v * 3.0)
		return
	var mult := clampf(speed / 4.0, 0.6, 2.5)
	var dmg: float = cfg["damage"] * mult
	var kind := "sharp" if cfg["sharp"] else "melee"
	var part := ""
	if body.has_meta("part"):
		part = body.get_meta("part")
	var pos := tip.lerp(body.global_position, 0.3)
	target.take_hit(dmg, v * 9.0 * (1.0 if kind == "melee" else 0.6), pos, part, kind)
	if h.has_method("haptic"):
		h.haptic(0.8, 0.12)
	Game.sfx.play("slash" if cfg["sharp"] else "thud", pos, 0.0)

# ---------------------------------------------------------------- guns
func set_trigger(pressed: bool) -> void:
	if not is_gun():
		return
	if pressed and not trigger_held:
		trigger_held = true
		if fire_cd <= 0.0:
			fire()
	elif not pressed:
		trigger_held = false

func _physics_process(delta: float) -> void:
	fire_cd -= delta
	if kick > 0.0:
		kick = maxf(0.0, kick - delta * 0.4)
		visual.position.z = kick
	if is_gun() and trigger_held and cfg["auto"] and fire_cd <= 0.0 and held_by:
		fire()

func fire() -> void:
	fire_cd = cfg["rate"]
	kick = cfg["kick"]
	var from := muzzle.global_position
	var fwd := -muzzle.global_transform.basis.z
	flash.visible = true
	get_tree().create_timer(0.045).timeout.connect(func(): flash.visible = false)
	Game.sfx.play(cfg["sound"], from, 2.0)
	if held_by and held_by.has_method("haptic"):
		held_by.haptic(0.5 if type == "smg" else 1.0, 0.06 if type == "smg" else 0.12)
	Game.panic(from, 25.0)
	Game.cop_saw_player()
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if Game.player:
		exclude.append(Game.player.get_rid())
		if Game.player.car and is_instance_valid(Game.player.car):
			exclude.append(Game.player.car.get_rid())
	for i in int(cfg["pellets"]):
		var sp: float = cfg["spread"]
		var dir := (fwd + Vector3(Game.randf_range(-sp, sp), Game.randf_range(-sp, sp), Game.randf_range(-sp, sp))).normalized()
		var to := from + dir * 140.0
		var q := PhysicsRayQueryParameters3D.create(from, to, Game.mask([Game.L_WORLD, Game.L_NPC, Game.L_RAGDOLL, Game.L_CAR, Game.L_PROP]), exclude)
		q.collide_with_areas = false
		var r := space.intersect_ray(q)
		if r.is_empty():
			Game.gore.tracer(from, to)
			continue
		var hit_pos: Vector3 = r["position"]
		Game.gore.tracer(from, hit_pos)
		var col: Node = r["collider"]
		var target := Game.hittable_of(col)
		if target:
			var part := ""
			if col.has_meta("part"):
				part = col.get_meta("part")
			target.take_hit(cfg["damage"], dir * 90.0, hit_pos, part, "bullet")
		elif col is RigidBody3D:
			(col as RigidBody3D).apply_impulse(dir * 6.0, hit_pos - col.global_position)
