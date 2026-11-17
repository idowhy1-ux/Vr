class_name Gore
extends Node3D
## Blood and gore effects: pooled particle sprays, a single MultiMesh for all
## blood decals on the ground, and a MultiMesh of blob shadows.

var spray_pool: Array[CPUParticles3D] = []
var spray_index := 0
const SPRAY_POOL := 14

var mist_pool: Array[CPUParticles3D] = []
var mist_index := 0
const MIST_POOL := 6

var decals: MultiMeshInstance3D
var decal_mm: MultiMesh
var decal_index := 0

var blobs: MultiMeshInstance3D
var blob_mm: MultiMesh
var blob_users: Array = []   # weak refs to Node3D that want a blob shadow
const MAX_BLOBS := 64

var blood_mat: StandardMaterial3D
var wound_mat: StandardMaterial3D
var flesh_mat: StandardMaterial3D
var guts_mat: StandardMaterial3D
var pools: Array = []          # growing blood pools under corpses
var tracer_mat: StandardMaterial3D
var tracers: Array[MeshInstance3D] = []
var tracer_index := 0
const TRACER_POOL := 10

func _ready() -> void:
	blood_mat = StandardMaterial3D.new()
	blood_mat.albedo_color = MeshLib.BLOOD
	blood_mat.roughness = 0.35
	blood_mat.metallic = 0.0
	blood_mat.metallic_specular = 0.25
	blood_mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	wound_mat = StandardMaterial3D.new()
	wound_mat.albedo_color = Color(0.3, 0.0, 0.01)
	wound_mat.roughness = 0.25
	flesh_mat = StandardMaterial3D.new()
	flesh_mat.albedo_color = Color(0.55, 0.06, 0.07)
	flesh_mat.roughness = 0.35
	guts_mat = StandardMaterial3D.new()
	guts_mat.albedo_color = Color(0.62, 0.3, 0.32)
	guts_mat.roughness = 0.3
	var drop := MeshLib.sphere(0.035, 5, 3)
	for i in SPRAY_POOL:
		var p := _make_spray(drop, 26, 0.75)
		add_child(p)
		spray_pool.append(p)
	for i in MIST_POOL:
		var p := _make_spray(MeshLib.sphere(0.07, 5, 3), 60, 1.1)
		add_child(p)
		mist_pool.append(p)
	_build_decals()
	_build_blobs()
	tracer_mat = StandardMaterial3D.new()
	tracer_mat.albedo_color = Color(1.0, 0.85, 0.4)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(1.0, 0.8, 0.3)
	tracer_mat.emission_energy_multiplier = 2.0
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in TRACER_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.cylinder(0.012, 1.0, 4)
		mi.material_override = tracer_mat
		mi.visible = false
		add_child(mi)
		tracers.append(mi)

func _make_spray(mesh: Mesh, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.color = MeshLib.BLOOD
	p.material_override = blood_mat
	p.local_coords = false
	return p

func _build_decals() -> void:
	decal_mm = MultiMesh.new()
	decal_mm.transform_format = MultiMesh.TRANSFORM_3D
	decal_mm.use_colors = true
	decal_mm.mesh = MeshLib.quad(Vector2(1, 1))
	decal_mm.instance_count = Game.MAX_DECALS
	for i in Game.MAX_DECALS:
		decal_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -50, 0)))
		decal_mm.set_instance_color(i, MeshLib.BLOOD_DARK)
	decals = MultiMeshInstance3D.new()
	decals.multimesh = decal_mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.95)
	m.albedo_texture = _splat_texture()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.45
	m.metallic_specular = 0.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	decals.material_override = m
	decals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(decals)

func _build_blobs() -> void:
	blob_mm = MultiMesh.new()
	blob_mm.transform_format = MultiMesh.TRANSFORM_3D
	blob_mm.mesh = MeshLib.quad(Vector2(1, 1))
	blob_mm.instance_count = MAX_BLOBS
	for i in MAX_BLOBS:
		blob_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -50, 0)))
	blobs = MultiMeshInstance3D.new()
	blobs.multimesh = blob_mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, 0.55)
	m.albedo_texture = _blob_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	blobs.material_override = m
	blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blobs)

## Soft round shadow texture (radial gradient, generated once).
func _blob_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

## Irregular blood splat with droplets, generated procedurally at startup.
func _splat_texture() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var lobes: Array = []
	for i in 7:
		lobes.append([rng.randf_range(0.0, TAU), rng.randf_range(0.05, 0.13), rng.randi_range(2, 6)])
	var drops: Array = []
	for i in 14:
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.36, 0.47)
		drops.append([Vector2(0.5 + cos(a) * d, 0.5 + sin(a) * d), rng.randf_range(0.012, 0.035)])
	for y in n:
		for x in n:
			var uv := Vector2((x + 0.5) / n, (y + 0.5) / n)
			var dv := uv - Vector2(0.5, 0.5)
			var ang := atan2(dv.y, dv.x)
			var rad := 0.27
			for l in lobes:
				rad += l[1] * 0.5 * (1.0 + sin(ang * l[2] + l[0])) * 0.5
			var a := 1.0 - smoothstep(rad - 0.015, rad + 0.01, dv.length())
			for dr in drops:
				a = maxf(a, 1.0 - smoothstep(dr[1] - 0.006, dr[1] + 0.004, uv.distance_to(dr[0])))
			# darker, thicker centre
			var shade := 0.8 + 0.2 * smoothstep(0.0, rad, dv.length())
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func register_blob(n: Node3D, size: float) -> void:
	if blob_users.size() >= MAX_BLOBS:
		return
	blob_users.append({"node": weakref(n), "size": size})

func _process(delta: float) -> void:
	_grow_pools(delta)
	# Update blob shadows under cars / people (cheap fake shadows).
	var i := 0
	var alive: Array = []
	for u in blob_users:
		var n: Node3D = u["node"].get_ref()
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		alive.append(u)
		if i < MAX_BLOBS:
			var p := n.global_position
			var s: float = u["size"]
			var t := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(s, s, s)), Vector3(p.x, ground_y(p) + 0.03, p.z))
			blob_mm.set_instance_transform(i, t)
			i += 1
	while i < MAX_BLOBS and i < blob_users.size():
		blob_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -50, 0)))
		i += 1
	blob_users = alive

# ---------------------------------------------------------------- public API
## Short directional blood spray at a point.
func spray(pos: Vector3, dir: Vector3 = Vector3.UP, strength: float = 1.0) -> void:
	var p: CPUParticles3D = spray_pool[spray_index]
	spray_index = (spray_index + 1) % SPRAY_POOL
	p.global_position = pos
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.initial_velocity_min = 2.0 * strength
	p.initial_velocity_max = 6.5 * strength
	p.restart()
	p.emitting = true
	decal(pos, 0.5 + strength * 0.4)

## Big blood explosion (gibs, car impacts, shotgun headshots).
func burst(pos: Vector3, strength: float = 1.0) -> void:
	var p: CPUParticles3D = mist_pool[mist_index]
	mist_index = (mist_index + 1) % MIST_POOL
	p.global_position = pos
	p.direction = Vector3.UP
	p.spread = 85.0
	p.initial_velocity_min = 3.0 * strength
	p.initial_velocity_max = 9.0 * strength
	p.restart()
	p.emitting = true
	for k in 4:
		decal(pos + Vector3(Game.randf_range(-1.2, 1.2), 0, Game.randf_range(-1.2, 1.2)), Game.randf_range(0.8, 1.8) * strength)

## Flat blood decal on the ground.
func decal(pos: Vector3, size: float = 1.0) -> void:
	var i := decal_index
	decal_index = (decal_index + 1) % Game.MAX_DECALS
	var s := clampf(size, 0.3, 3.0)
	var rot := Basis(Vector3.RIGHT, -PI / 2.0).rotated(Vector3.UP, Game.randf_range(0.0, TAU))
	var t := Transform3D(rot * Basis().scaled(Vector3(s * Game.randf_range(0.8, 1.25), s * Game.randf_range(0.8, 1.25), 1.0)), Vector3(pos.x, ground_y(pos) + 0.015 + (i % 7) * 0.002, pos.z))
	decal_mm.set_instance_transform(i, t)
	var c := MeshLib.BLOOD_DARK
	c.r += Game.randf_range(-0.08, 0.1)
	decal_mm.set_instance_color(i, c)

## A blood pool that slowly spreads under a body.
func pool(pos: Vector3) -> void:
	var i := decal_index
	decal(pos, 0.4)
	pools.append({"i": i, "pos": Vector3(pos.x, 0.0, pos.z), "size": 0.4, "max": Game.randf_range(1.8, 2.8), "rot": Game.randf_range(0.0, TAU)})
	if pools.size() > 12:
		pools.pop_front()

func _grow_pools(delta: float) -> void:
	for p in pools:
		if p["size"] >= p["max"]:
			continue
		p["size"] = minf(p["max"], p["size"] + delta * 0.25)
		var s: float = p["size"]
		var pos: Vector3 = p["pos"]
		var rot := Basis(Vector3.RIGHT, -PI / 2.0).rotated(Vector3.UP, p["rot"])
		decal_mm.set_instance_transform(p["i"], Transform3D(rot * Basis().scaled(Vector3(s, s, 1.0)), Vector3(pos.x, ground_y(pos) + 0.012, pos.z)))

## Ground height under a point (sidewalks are raised).
func ground_y(pos: Vector3) -> float:
	if Game.city and Game.city.has_method("ground_height"):
		return Game.city.ground_height(pos)
	return 0.0

# ---------------------------------------------------------------- bullet impacts
var _dust_pool: Array[CPUParticles3D] = []
var _spark_pool: Array[CPUParticles3D] = []
var _glass_pool: Array[CPUParticles3D] = []
var _casing_pool: Array[CPUParticles3D] = []
var _fx_i := 0
var _casing_i := 0
var holes_mm: MultiMesh
var hole_index := 0
const MAX_HOLES := 160

func _impact_fx(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.local_coords = false
	match kind:
		"dust":
			p.amount = 14
			p.lifetime = 0.9
			p.mesh = MeshLib.sphere(0.03, 5, 3)
			p.material_override = MeshLib.mat(Color(0.62, 0.6, 0.56), 1.0)
			p.spread = 35.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 2.6
			p.gravity = Vector3(0, -1.5, 0)
			p.damping_min = 2.0
			p.damping_max = 4.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 2.2
			var curve := Curve.new()
			curve.add_point(Vector2(0, 0.6))
			curve.add_point(Vector2(1, 1.6))
			p.scale_amount_curve = curve
		"spark":
			p.amount = 16
			p.lifetime = 0.35
			p.mesh = MeshLib.box(Vector3(0.008, 0.008, 0.05))
			p.material_override = MeshLib.mat(Color(1.0, 0.8, 0.4), 1.0, 0.0, Color(1.0, 0.7, 0.25), 6.0)
			p.spread = 50.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 8.0
			p.gravity = Vector3(0, -9.8, 0)
			p.particle_flag_align_y = true
		"glass":
			p.amount = 24
			p.lifetime = 0.9
			p.mesh = MeshLib.box(Vector3(0.025, 0.003, 0.02))
			p.material_override = MeshLib.mat(Color(0.75, 0.85, 0.9), 0.05, 0.6)
			p.spread = 70.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 4.5
			p.gravity = Vector3(0, -9.8, 0)
			p.angular_velocity_min = -720.0
			p.angular_velocity_max = 720.0
	add_child(p)
	return p

func _build_impacts() -> void:
	for i in 6:
		_dust_pool.append(_impact_fx("dust"))
		_spark_pool.append(_impact_fx("spark"))
	for i in 3:
		_glass_pool.append(_impact_fx("glass"))
	for i in 8:
		var c := CPUParticles3D.new()
		c.one_shot = true
		c.emitting = false
		c.amount = 1
		c.lifetime = 0.8
		c.explosiveness = 1.0
		c.local_coords = false
		c.spread = 12.0
		c.gravity = Vector3(0, -9.8, 0)
		c.angular_velocity_min = -900.0
		c.angular_velocity_max = 900.0
		add_child(c)
		_casing_pool.append(c)
	holes_mm = MultiMesh.new()
	holes_mm.transform_format = MultiMesh.TRANSFORM_3D
	holes_mm.mesh = MeshLib.quad(Vector2(1, 1))
	holes_mm.instance_count = MAX_HOLES
	for i in MAX_HOLES:
		holes_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -50, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = holes_mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.03, 0.95)
	m.albedo_texture = _blob_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _fire_fx(p: CPUParticles3D, pos: Vector3, dir: Vector3) -> void:
	p.global_position = pos
	p.direction = dir
	p.restart()
	p.emitting = true

## A bullet hitting a surface: "concrete", "metal" or "glass".
func impact(pos: Vector3, normal: Vector3, surface: String) -> void:
	if _dust_pool.is_empty():
		_build_impacts()
	_fx_i = (_fx_i + 1) % 6
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	match surface:
		"concrete":
			_fire_fx(_dust_pool[_fx_i], pos + n * 0.02, n)
			Game.sfx.play("concrete", pos, -4.0)
		"metal":
			_fire_fx(_spark_pool[_fx_i], pos + n * 0.02, n)
			Game.sfx.play("metal", pos, -6.0, 1.25)
		"glass":
			_fire_fx(_glass_pool[_fx_i % 3], pos, n)
			Game.sfx.play("glass", pos, -2.0)
	if surface != "glass":
		if Game.rng.randf() < 0.18:
			Game.sfx.play("ricochet", pos, -4.0)
		# bullet hole facing out of the surface
		var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var b := Basis.looking_at(-n, up).rotated(n, Game.randf_range(0.0, TAU))
		var sz := Game.randf_range(0.05, 0.08)
		holes_mm.set_instance_transform(hole_index, Transform3D(b.scaled(Vector3(sz, sz, sz)), pos + n * 0.006))
		hole_index = (hole_index + 1) % MAX_HOLES

## A spent cartridge (brass, or a red shotgun shell) flying out of a gun.
func casing(pos: Vector3, vel: Vector3, shell: bool) -> void:
	if _casing_pool.is_empty():
		_build_impacts()
	var c := _casing_pool[_casing_i]
	_casing_i = (_casing_i + 1) % _casing_pool.size()
	if shell:
		c.mesh = MeshLib.cylinder(0.0105, 0.07, 8)
		c.material_override = MeshLib.mat(Color(0.65, 0.08, 0.06), 0.5)
	else:
		c.mesh = MeshLib.cylinder(0.0055, 0.022, 6)
		c.material_override = MeshLib.mat(Color(0.85, 0.65, 0.3), 0.25, 1.0)
	c.initial_velocity_min = vel.length() * 0.85
	c.initial_velocity_max = vel.length() * 1.1
	_fire_fx(c, pos, vel.normalized())
	# tink when it lands
	var land := pos + vel * 0.4
	land.y = ground_y(land)
	get_tree().create_timer(0.45).timeout.connect(func(): Game.sfx.play("casing", land, -2.0 if shell else 0.0, 0.6 if shell else 1.0))

var _flash_pool: Array[MeshInstance3D] = []
var _flash_i := 0

## Brief muzzle flash at a point (used by police guns).
func muzzle_flash(pos: Vector3) -> void:
	if _flash_pool.is_empty():
		for k in 4:
			var mi := MeshInstance3D.new()
			mi.mesh = MeshLib.sphere(0.07, 6, 4)
			mi.material_override = MeshLib.mat(Color(1, 0.9, 0.5), 1.0, 0.0, Color(1.0, 0.75, 0.3), 5.0)
			mi.visible = false
			add_child(mi)
			_flash_pool.append(mi)
	var f := _flash_pool[_flash_i]
	_flash_i = (_flash_i + 1) % _flash_pool.size()
	f.global_position = pos
	f.visible = true
	get_tree().create_timer(0.05).timeout.connect(func(): f.visible = false)

## Bullet tracer from a to b, hidden after a few frames.
func tracer(a: Vector3, b: Vector3) -> void:
	var mi: MeshInstance3D = tracers[tracer_index]
	tracer_index = (tracer_index + 1) % TRACER_POOL
	var d := b - a
	var len := d.length()
	if len < 0.05:
		return
	mi.visible = true
	var mid := (a + b) * 0.5
	var basis := Basis()
	var up := d.normalized()
	var axis := Vector3.UP.cross(up)
	if axis.length() > 0.001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	basis = basis.scaled(Vector3(1, len, 1))
	mi.global_transform = Transform3D(basis, mid)
	var t := get_tree().create_timer(0.06)
	t.timeout.connect(func(): mi.visible = false)
