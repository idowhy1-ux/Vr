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

func _process(_delta: float) -> void:
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
			var t := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(s, s, s)), Vector3(p.x, 0.03, p.z))
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
	var t := Transform3D(rot * Basis().scaled(Vector3(s * Game.randf_range(0.8, 1.25), s * Game.randf_range(0.8, 1.25), 1.0)), Vector3(pos.x, 0.015 + (i % 7) * 0.002, pos.z))
	decal_mm.set_instance_transform(i, t)
	var c := MeshLib.BLOOD_DARK
	c.r += Game.randf_range(-0.08, 0.1)
	decal_mm.set_instance_color(i, c)

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
