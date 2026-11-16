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

func _build() -> void:
	var WOOD := Color(0.6, 0.42, 0.22)
	var STEEL := Color(0.78, 0.79, 0.83)
	var GUN := Color(0.12, 0.12, 0.13)
	var GRIP := Color(0.2, 0.15, 0.1)
	var BLACK := Color(0.05, 0.05, 0.05)
	var P: Array = []
	match type:
		"bat":
			P.append(MeshLib.part(MeshLib.taper(0.042, 0.02, 0.7, 8), Vector3(0, 0, -0.45), Vector3(-90, 0, 0), WOOD, 0.6))
			P.append(MeshLib.part(MeshLib.cylinder(0.02, 0.22, 7), Vector3(0, 0, -0.05), Vector3(90, 0, 0), BLACK, 0.8))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.08, 0.08, 0.85)), Vector3(0, 0, -0.4), Vector3.ZERO, self)
		"baton":
			P.append(MeshLib.part(MeshLib.cylinder(0.018, 0.5, 6), Vector3(0, 0, -0.3), Vector3(90, 0, 0), BLACK, 0.5))
			P.append(MeshLib.part(MeshLib.cylinder(0.024, 0.14, 6), Vector3(0, 0, -0.03), Vector3(90, 0, 0), GRIP, 0.8))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.06, 0.06, 0.55)), Vector3(0, 0, -0.25), Vector3.ZERO, self)
		"machete":
			P.append(MeshLib.part(MeshLib.box(Vector3(0.006, 0.07, 0.5)), Vector3(0, 0.0, -0.4), Vector3.ZERO, STEEL, 0.2, 0.9))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.008, 0.02, 0.5)), Vector3(0, 0.03, -0.4), Vector3.ZERO, STEEL.darkened(0.3), 0.3, 0.9))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.03, 0.04, 0.16)), Vector3(0, 0, -0.06), Vector3.ZERO, GRIP, 0.8))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.05, 0.08, 0.62)), Vector3(0, 0, -0.3), Vector3.ZERO, self)
		"knife":
			P.append(MeshLib.part(MeshLib.box(Vector3(0.005, 0.035, 0.24)), Vector3(0, 0, -0.24), Vector3.ZERO, STEEL, 0.2, 0.9))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.04, 0.05, 0.015)), Vector3(0, 0, -0.12), Vector3.ZERO, BLACK, 0.4, 0.6))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.026, 0.03, 0.12)), Vector3(0, 0, -0.06), Vector3.ZERO, GRIP, 0.8))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.04, 0.05, 0.36)), Vector3(0, 0, -0.18), Vector3.ZERO, self)
		"axe":
			P.append(MeshLib.part(MeshLib.cylinder(0.022, 0.7, 7), Vector3(0, 0, -0.38), Vector3(90, 0, 0), WOOD, 0.7))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.025, 0.2, 0.16)), Vector3(0, 0.1, -0.66), Vector3.ZERO, STEEL, 0.25, 0.9))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.012, 0.22, 0.03)), Vector3(0, 0.1, -0.74), Vector3.ZERO, Color(0.9, 0.9, 0.95), 0.15, 1.0))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.06, 0.22, 0.76)), Vector3(0, 0.05, -0.38), Vector3.ZERO, self)
		"pistol":
			P.append(MeshLib.part(MeshLib.box(Vector3(0.034, 0.05, 0.19)), Vector3(0, 0.03, -0.1), Vector3.ZERO, GUN, 0.45, 0.7))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.03, 0.11, 0.04)), Vector3(0, -0.04, 0.0), Vector3(15, 0, 0), GRIP, 0.8))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.01, 0.025, 0.02)), Vector3(0, -0.005, -0.07), Vector3.ZERO, BLACK, 0.6))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.05, 0.16, 0.2)), Vector3(0, 0, -0.08), Vector3.ZERO, self)
			_muzzle(Vector3(0, 0.035, -0.2))
		"shotgun":
			P.append(MeshLib.part(MeshLib.cylinder(0.018, 0.62, 7), Vector3(0, 0.04, -0.4), Vector3(90, 0, 0), GUN, 0.4, 0.7))
			P.append(MeshLib.part(MeshLib.cylinder(0.022, 0.4, 7), Vector3(0, 0.0, -0.32), Vector3(90, 0, 0), WOOD, 0.7))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.04, 0.07, 0.22)), Vector3(0, 0.02, -0.05), Vector3.ZERO, GUN, 0.45, 0.7))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.04, 0.11, 0.3)), Vector3(0, -0.03, 0.2), Vector3(-10, 0, 0), WOOD, 0.7))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.06, 0.14, 0.95)), Vector3(0, 0, -0.25), Vector3.ZERO, self)
			_muzzle(Vector3(0, 0.04, -0.72))
		"smg":
			P.append(MeshLib.part(MeshLib.box(Vector3(0.05, 0.08, 0.36)), Vector3(0, 0.03, -0.14), Vector3.ZERO, GUN, 0.45, 0.7))
			P.append(MeshLib.part(MeshLib.cylinder(0.014, 0.14, 6), Vector3(0, 0.04, -0.38), Vector3(90, 0, 0), GUN, 0.4, 0.7))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.03, 0.12, 0.04)), Vector3(0, -0.05, 0.0), Vector3(10, 0, 0), GRIP, 0.8))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.03, 0.16, 0.035)), Vector3(0, -0.06, -0.14), Vector3.ZERO, BLACK, 0.6))
			P.append(MeshLib.part(MeshLib.box(Vector3(0.03, 0.05, 0.2)), Vector3(0, 0.0, 0.16), Vector3.ZERO, GUN, 0.45, 0.7))
			MeshLib.collider(MeshLib.box_shape(Vector3(0.07, 0.2, 0.5)), Vector3(0, -0.02, -0.1), Vector3.ZERO, self)
			_muzzle(Vector3(0, 0.04, -0.46))
	if not _mesh_cache.has(type):
		_mesh_cache[type] = MeshLib.build(P)
	MeshLib.inst_built(_mesh_cache[type], Vector3.ZERO, Vector3.ZERO, visual, 60.0)

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
	transform = Transform3D(Basis(), Vector3(0, -0.01, -0.03))
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
