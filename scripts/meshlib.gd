class_name MeshLib
## Shared low-poly meshes and materials. Everything is created once and reused
## so the Quest 3 only pays for a handful of GPU resources.

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

static func mat(color: Color, rough: float = 0.85, metal: float = 0.0, emissive: Color = Color.BLACK, emit_energy: float = 1.0) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [color.to_html(), rough, metal, emissive.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	if emissive != Color.BLACK:
		m.emission_enabled = true
		m.emission = emissive
		m.emission_energy_multiplier = emit_energy
	_mats[key] = m
	return m

static func mat_alpha(color: Color) -> StandardMaterial3D:
	var key := "alpha_" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[key] = m
	return m

static func box(size: Vector3) -> BoxMesh:
	var key := "box_%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var b := BoxMesh.new()
	b.size = size
	_meshes[key] = b
	return b

static func sphere(radius: float, segs: int = 8, rings: int = 5) -> SphereMesh:
	var key := "sph_%s_%d_%d" % [radius, segs, rings]
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = rings
	_meshes[key] = s
	return s

static func capsule(radius: float, height: float, segs: int = 6, rings: int = 3) -> CapsuleMesh:
	var key := "cap_%s_%s_%d" % [radius, height, segs]
	if _meshes.has(key):
		return _meshes[key]
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = rings
	_meshes[key] = c
	return c

static func cylinder(radius: float, height: float, segs: int = 10) -> CylinderMesh:
	var key := "cyl_%s_%s_%d" % [radius, height, segs]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	_meshes[key] = c
	return c

static func cone(radius: float, height: float, segs: int = 8) -> CylinderMesh:
	var key := "cone_%s_%s_%d" % [radius, height, segs]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	_meshes[key] = c
	return c

static func taper(r_top: float, r_bottom: float, height: float, segs: int = 8) -> CylinderMesh:
	var key := "taper_%s_%s_%s_%d" % [r_top, r_bottom, height, segs]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	_meshes[key] = c
	return c

static func quad(size: Vector2) -> QuadMesh:
	var key := "quad_%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var q := QuadMesh.new()
	q.size = size
	_meshes[key] = q
	return q

## Convenience: MeshInstance3D with mesh, material and local transform.
static func inst(mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Distance culling for small parts: eyes, badges, lights, rims, shoes...
	var size := mesh.get_aabb().get_longest_axis_size()
	if size < 0.16:
		mi.visibility_range_end = 22.0
	elif size < 0.45:
		mi.visibility_range_end = 45.0
	elif size < 1.0:
		mi.visibility_range_end = 80.0
	if parent:
		parent.add_child(mi)
	return mi

static func box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s

static func sphere_shape(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s

static func cylinder_shape(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s

static func capsule_shape(r: float, h: float) -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = h
	return s

static func collider(shape: Shape3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, parent: Node = null) -> CollisionShape3D:
	var c := CollisionShape3D.new()
	c.shape = shape
	c.position = pos
	c.rotation_degrees = rot_deg
	if parent:
		parent.add_child(c)
	return c

# ---- Palette ----
const SKIN := [Color(0.93, 0.76, 0.62), Color(0.80, 0.60, 0.45), Color(0.55, 0.38, 0.27), Color(0.98, 0.84, 0.72), Color(0.40, 0.27, 0.19)]
const SHIRTS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.5, 0.85), Color(0.95, 0.9, 0.3), Color(0.3, 0.75, 0.4), Color(0.9, 0.9, 0.9), Color(0.6, 0.3, 0.7), Color(0.95, 0.55, 0.2), Color(0.15, 0.15, 0.18)]
const PANTS := [Color(0.18, 0.22, 0.4), Color(0.15, 0.15, 0.15), Color(0.45, 0.4, 0.33), Color(0.3, 0.3, 0.55)]
const CAR_COLORS := [Color(0.85, 0.1, 0.1), Color(0.1, 0.3, 0.8), Color(0.92, 0.92, 0.92), Color(0.12, 0.12, 0.12), Color(0.9, 0.75, 0.1), Color(0.1, 0.55, 0.3), Color(0.6, 0.6, 0.65), Color(0.95, 0.5, 0.1)]
const BLOOD := Color(0.5, 0.01, 0.02)
const BLOOD_DARK := Color(0.36, 0.0, 0.01)
const BONE := Color(0.93, 0.9, 0.82)

# ---------------------------------------------------------------- merged meshes
# Many small primitives are baked into one ArrayMesh with per-vertex colour,
# roughness, metalness and emission, all drawn with a single shared shader.
# This cuts draw calls by ~3x for people, cars and weapons (important on Quest).

static var _atlas: ShaderMaterial
static var _arrays_cache: Dictionary = {}

static func atlas() -> ShaderMaterial:
	if _atlas:
		return _atlas
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = UV2.x;
	METALLIC = UV2.y;
	EMISSION = COLOR.rgb * COLOR.a * 3.0;
}
"""
	_atlas = ShaderMaterial.new()
	_atlas.shader = sh
	return _atlas

## One entry for build(): primitive mesh, local placement and surface look.
static func part(mesh: Mesh, pos: Vector3, rot_deg: Vector3, color: Color, rough: float = 0.8, metal: float = 0.0, emit: float = 0.0, scale: Vector3 = Vector3.ONE) -> Array:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scale)
	return [mesh, Transform3D(b, pos), color, rough, metal, emit]

static func _arrays_of(mesh: Mesh) -> Array:
	var id := mesh.get_instance_id()
	if not _arrays_cache.has(id):
		_arrays_cache[id] = mesh.surface_get_arrays(0)
	return _arrays_cache[id]

static func build(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for p in parts:
		var arr := _arrays_of(p[0])
		var t: Transform3D = p[1]
		var c: Color = (p[2] as Color).srgb_to_linear()
		var look := Color(c.r, c.g, c.b, p[5])
		var ruv := Vector2(p[3], p[4])
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb := t.basis.inverse().transposed()
		var base := verts.size()
		for i in v.size():
			verts.append(t * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(look)
			uv2s.append(ruv)
		if ind.is_empty():
			for i in v.size():
				idx.append(base + i)
		else:
			for i in ind:
				idx.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

## MeshInstance3D for a merged mesh (uses the shared atlas shader).
static func inst_built(mesh: ArrayMesh, pos: Vector3, rot_deg: Vector3, parent: Node, vis_range: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = atlas()
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = vis_range
	if parent:
		parent.add_child(mi)
	return mi
