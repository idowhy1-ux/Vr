class_name City
extends Node3D
## Procedural textured city. Roads are one big shaded plane, every block is a
## raised slab with curbs, buildings are one MultiMesh using photo facades, and
## street furniture is MultiMeshes of smooth procedural models. A ring of tall
## towers around the playable grid forms the skyline. Also provides the
## sidewalk and road graphs that pedestrians and cars navigate.

const N := 8                 # playable blocks per side
const BLOCK := 44.0          # road centre to road centre
const ROAD_HALF := 4.0       # road half width (2 lanes)
const WALK_W := 3.0          # sidewalk width
const LANE := 2.0            # lane offset from road centre
const CURB_H := 0.15
const HALF := N * BLOCK / 2.0
const RING := 2              # extra skyline blocks around the playable area

# facade slices: tile size (m), floor height, bay width
const FACADES := [
	{"tile": 19.2, "floor": 3.2, "bay": 3.2},    # brick (018A)
	{"tile": 19.2, "floor": 3.2, "bay": 3.2},    # office stone (019A)
	{"tile": 19.2, "floor": 3.2, "bay": 3.2},    # brick office (020A)
	{"tile": 28.0, "floor": 3.5, "bay": 2.0},    # office bands (006)
	{"tile": 34.0, "floor": 3.4, "bay": 2.125},  # glass tower (001)
	{"tile": 36.0, "floor": 1.5, "bay": 1.125},  # glass grid (005)
]
const GROUND_FLOOR := 4.2

var buildings: Array = []
var x_lines: PackedFloat32Array = []
var walk_lines: PackedFloat32Array = []

func road_x(i: int) -> float:
	return i * BLOCK - HALF

func _ready() -> void:
	for i in N + 1:
		x_lines.append(road_x(i))
	for i in N:
		walk_lines.append(road_x(i) + ROAD_HALF + WALK_W * 0.5)
		walk_lines.append(road_x(i + 1) - ROAD_HALF - WALK_W * 0.5)
	_build_roads()
	_build_blocks()
	_build_buildings()
	_build_furniture()
	_build_environment()

# ---------------------------------------------------------------- ground
func _build_roads() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var ext := (N + RING * 2) * BLOCK + 300.0
	pm.size = Vector2(ext, ext)
	pm.subdivide_depth = 8
	pm.subdivide_width = 8
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	m.set_shader_parameter("asphalt", load("res://textures/asphalt_albedo.png"))
	m.set_shader_parameter("asphalt_n", load("res://textures/asphalt_normal.jpg"))
	m.set_shader_parameter("half_size", HALF)
	m.set_shader_parameter("block", BLOCK)
	m.set_shader_parameter("road_half", ROAD_HALF)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Game.bit(Game.L_WORLD)
	body.collision_mask = 0
	MeshLib.collider(WorldBoundaryShape3D.new(), Vector3.ZERO, Vector3.ZERO, body)
	add_child(body)
	# invisible walls at the edge of the skyline ring
	var wall_d := HALF + RING * BLOCK - ROAD_HALF
	for k in 4:
		var w := StaticBody3D.new()
		w.collision_layer = Game.bit(Game.L_WORLD)
		w.collision_mask = 0
		var horizontal := k < 2
		var sz := Vector3(wall_d * 2.0 + 10.0, 30.0, 2.0) if horizontal else Vector3(2.0, 30.0, wall_d * 2.0 + 10.0)
		var pos := Vector3(0, 15, (wall_d + 1.0) * (1 if k == 0 else -1)) if horizontal else Vector3((wall_d + 1.0) * (1 if k == 2 else -1), 15, 0)
		MeshLib.collider(MeshLib.box_shape(sz), pos, Vector3.ZERO, w)
		add_child(w)

## Raised slabs with curb faces; collision includes small ramps at the curbs so
## people and cars roll up onto the sidewalk smoothly.
func _build_blocks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := -RING
	var hi := N + RING
	for bi in range(lo, hi):
		for bj in range(lo, hi):
			var x0 := road_x(bi) + ROAD_HALF
			var z0 := road_x(bj) + ROAD_HALF
			var x1 := road_x(bi + 1) - ROAD_HALF
			var z1 := road_x(bj + 1) - ROAD_HALF
			_slab(st, x0, z0, x1, z1, CURB_H)
			var body := StaticBody3D.new()
			body.collision_layer = Game.bit(Game.L_WORLD)
			body.collision_mask = 0
			add_child(body)
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			MeshLib.collider(MeshLib.box_shape(Vector3(x1 - x0, CURB_H, z1 - z0)), Vector3(cx, CURB_H * 0.5, cz), Vector3.ZERO, body)
			if bi >= 0 and bi < N and bj >= 0 and bj < N:
				_ramps(body, x0, z0, x1, z1)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sidewalk.gdshader")
	m.set_shader_parameter("walk", load("res://textures/sidewalk_albedo.png"))
	m.set_shader_parameter("walk_n", load("res://textures/sidewalk_normal.jpg"))
	m.set_shader_parameter("curb", load("res://textures/concrete_albedo.png"))
	m.set_shader_parameter("pavers", load("res://textures/pavers_albedo.png"))
	m.set_shader_parameter("pavers_n", load("res://textures/pavers_normal.jpg"))
	m.set_shader_parameter("half_size", HALF)
	m.set_shader_parameter("block", BLOCK)
	m.set_shader_parameter("road_half", ROAD_HALF)
	m.set_shader_parameter("walk_w", WALK_W)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _slab(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, h: float) -> void:
	var r := 0.12   # rounded curb edge
	# top (subdivided a little so vertex fog/lighting are smooth)
	var steps := 6
	for i in steps:
		for j in steps:
			var ax := lerpf(x0, x1, float(i) / steps)
			var bx := lerpf(x0, x1, float(i + 1) / steps)
			var az := lerpf(z0, z1, float(j) / steps)
			var bz := lerpf(z0, z1, float(j + 1) / steps)
			_quad(st, Vector3(ax, h, az), Vector3(bx, h, az), Vector3(bx, h, bz), Vector3(ax, h, bz), Vector3.UP)
	# sides (curb faces) with a slight bevel at the top edge
	var corners := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
	var outs := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var o: Vector3 = outs[k]
		_quad(st, a + o * 0.0, b + o * 0.0, b + Vector3(0, h - r * 0.3, 0), a + Vector3(0, h - r * 0.3, 0), o)
		_quad(st, a + Vector3(0, h - r * 0.3, 0), b + Vector3(0, h - r * 0.3, 0), b + Vector3(0, h, 0) - o * r * 0.3, a + Vector3(0, h, 0) - o * r * 0.3, (o + Vector3.UP).normalized())

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var face := (c - a).cross(b - a)
	var pts := [a, b, c, a, c, d]
	if face.dot(n) < 0.0:
		pts = [a, c, b, a, d, c]
	for p in pts:
		st.set_normal(n)
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)

func _ramps(body: StaticBody3D, x0: float, z0: float, x1: float, z1: float) -> void:
	var w := 0.4
	var h := CURB_H
	var defs := [
		[Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(0, 0, -1)],
		[Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(1, 0, 0)],
		[Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3(0, 0, 1)],
		[Vector3(x0, 0, z1), Vector3(x0, 0, z0), Vector3(-1, 0, 0)],
	]
	for dfn in defs:
		var a: Vector3 = dfn[0]
		var b: Vector3 = dfn[1]
		var o: Vector3 = dfn[2]
		var pts := PackedVector3Array([a, b, a + Vector3(0, h, 0), b + Vector3(0, h, 0), a + o * w, b + o * w])
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		MeshLib.collider(shape, Vector3.ZERO, Vector3.ZERO, body)

## Height of the walkable surface at a point (sidewalks are raised).
func ground_height(p: Vector3) -> float:
	var lx := fposmod(p.x + HALF, BLOCK)
	var lz := fposmod(p.z + HALF, BLOCK)
	if lx > ROAD_HALF and lx < BLOCK - ROAD_HALF and lz > ROAD_HALF and lz < BLOCK - ROAD_HALF:
		return CURB_H
	return 0.0

# ---------------------------------------------------------------- buildings
func _build_buildings() -> void:
	var rng := Game.rng
	var instances: Array = []
	for bi in range(-RING, N + RING):
		for bj in range(-RING, N + RING):
			var inner := bi >= 0 and bi < N and bj >= 0 and bj < N
			var body := StaticBody3D.new()
			body.collision_layer = Game.bit(Game.L_WORLD)
			body.collision_mask = 0
			add_child(body)
			var x0 := road_x(bi) + ROAD_HALF + WALK_W
			var z0 := road_x(bj) + ROAD_HALF + WALK_W
			var zone := BLOCK - 2.0 * (ROAD_HALF + WALK_W)
			var center_dist := Vector2(x0 + zone / 2.0, z0 + zone / 2.0).length() / HALF
			var lots: Array = []
			var layout := rng.randi_range(0, 3) if inner else rng.randi_range(0, 1)
			if layout == 0:
				lots = [Rect2(x0, z0, zone, zone)]
			elif layout == 1:
				lots = [Rect2(x0, z0, zone / 2.0, zone), Rect2(x0 + zone / 2.0, z0, zone / 2.0, zone)]
			elif layout == 2:
				lots = [Rect2(x0, z0, zone, zone / 2.0), Rect2(x0, z0 + zone / 2.0, zone, zone / 2.0)]
			else:
				var hz := zone / 2.0
				lots = [Rect2(x0, z0, hz, hz), Rect2(x0 + hz, z0, hz, hz), Rect2(x0, z0 + hz, hz, hz), Rect2(x0 + hz, z0 + hz, hz, hz)]
			for lot in lots:
				var slice: int
				var floors: int
				var tall := clampf(1.0 - center_dist, 0.0, 1.0)
				if not inner:
					slice = [3, 4, 5, 1, 4][rng.randi_range(0, 4)]
				elif rng.randf() < 0.18 + tall * 0.25:
					slice = [3, 4, 1][rng.randi_range(0, 2)]
				else:
					slice = [0, 2, 0, 1][rng.randi_range(0, 3)]
				var f: Dictionary = FACADES[slice]
				var floor_h: float = f["floor"]
				var bay: float = f["bay"]
				var target_h := rng.randf_range(10.0, 18.0 + tall * 26.0) + (rng.randf_range(12.0, 35.0) if rng.randf() < 0.15 else 0.0)
				if not inner:
					target_h = rng.randf_range(35.0, 95.0)
				floors = maxi(2, int(round((target_h - GROUND_FLOOR) / floor_h)))
				var h := GROUND_FLOOR + floors * floor_h + 0.6
				var margin := rng.randf_range(0.0, 1.2) if inner else rng.randf_range(0.0, 3.0)
				var w: float = maxf(bay * 3.0, floor((lot.size.x - margin * 2.0) / bay) * bay)
				var d: float = maxf(bay * 3.0, floor((lot.size.y - margin * 2.0) / bay) * bay)
				var cx: float = lot.position.x + lot.size.x / 2.0
				var cz: float = lot.position.y + lot.size.y / 2.0
				var pos := Vector3(cx, CURB_H + h / 2.0, cz)
				var size := Vector3(w, h, d)
				var tint := _tint(rng, slice)
				instances.append({"pos": pos, "size": size, "color": tint, "custom": Color(slice, rng.randf(), float(rng.randi_range(0, 999)), 0.0)})
				if inner:
					buildings.append({"pos": pos, "size": size})
				MeshLib.collider(MeshLib.box_shape(size), pos, Vector3.ZERO, body)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = instances.size()
	for i in instances.size():
		var inst: Dictionary = instances[i]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(inst["size"]), inst["pos"]))
		mm.set_instance_color(i, inst["color"])
		mm.set_instance_custom_data(i, inst["custom"])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/building.gdshader")
	m.set_shader_parameter("facade_albedo", load("res://textures/facade_albedo_array.png"))
	m.set_shader_parameter("facade_normal", load("res://textures/facade_normal_array.png"))
	m.set_shader_parameter("roof_albedo", load("res://textures/concrete_albedo.png"))
	var tiles := PackedVector4Array()
	for f in FACADES:
		tiles.append(Vector4(f["tile"], f["tile"], 0, 0))
	m.set_shader_parameter("tiles", tiles)
	m.set_shader_parameter("ground_floor", GROUND_FLOOR)
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

func _tint(rng: RandomNumberGenerator, slice: int) -> Color:
	var warm := [Color(1.0, 0.97, 0.92), Color(1.05, 0.92, 0.82), Color(0.92, 0.88, 0.85), Color(1.1, 1.02, 0.9), Color(0.85, 0.82, 0.8), Color(1.0, 0.85, 0.75)]
	var cool := [Color(1.0, 1.0, 1.0), Color(0.92, 0.95, 1.0), Color(0.85, 0.85, 0.88), Color(1.05, 1.02, 0.97)]
	var pal: Array = warm if slice in [0, 2] else cool
	return pal[rng.randi_range(0, pal.size() - 1)]

# ---------------------------------------------------------------- street furniture
var _chunks: Dictionary = {}

func _put(kind: String, bi: int, bj: int, t: Transform3D) -> void:
	var key := Vector3i(bi / 2, bj / 2, 0)
	if not _chunks.has(key):
		_chunks[key] = {}
	var c: Dictionary = _chunks[key]
	if not c.has(kind):
		c[kind] = []
	(c[kind] as Array).append(t)

func _build_furniture() -> void:
	var rng := Game.rng
	for bi in N:
		for bj in N:
			var body := StaticBody3D.new()
			body.collision_layer = Game.bit(Game.L_WORLD)
			body.collision_mask = 0
			add_child(body)
			var x0 := road_x(bi) + ROAD_HALF
			var z0 := road_x(bj) + ROAD_HALF
			var x1 := road_x(bi + 1) - ROAD_HALF
			var z1 := road_x(bj + 1) - ROAD_HALF
			# the four edges: start point, direction along the edge, inward normal
			var edges := [
				[Vector3(x0, CURB_H, z0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
				[Vector3(x1, CURB_H, z0), Vector3(0, 0, 1), Vector3(-1, 0, 0)],
				[Vector3(x1, CURB_H, z1), Vector3(-1, 0, 0), Vector3(0, 0, -1)],
				[Vector3(x0, CURB_H, z1), Vector3(0, 0, -1), Vector3(1, 0, 0)],
			]
			var len := x1 - x0
			for e in edges:
				var a: Vector3 = e[0]
				var dir: Vector3 = e[1]
				var inn: Vector3 = e[2]
				var road_side := -inn
				for t in [0.25, 0.75]:
					var p: Vector3 = a + dir * len * t + inn * 0.45
					_put("lamp", bi, bj, Transform3D(_face_x(road_side), p))
					MeshLib.collider(MeshLib.capsule_shape(0.12, 6.0), p + Vector3(0, 3.0, 0), Vector3.ZERO, body)
				for t in [0.13, 0.5, 0.87]:
					if rng.randf() < 0.9:
						var p: Vector3 = a + dir * len * t + inn * 0.95
						var s := rng.randf_range(0.85, 1.2)
						var v := rng.randi_range(0, 2)
						_put("tree%d" % v, bi, bj, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s, s)), p))
						MeshLib.collider(MeshLib.capsule_shape(0.16, 3.0), p + Vector3(0, 1.5, 0), Vector3.ZERO, body)
				var hp: Vector3 = a + dir * len * rng.randf_range(0.42, 0.58) + inn * 0.55
				if rng.randf() < 0.6:
					_put("hydrant", bi, bj, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), hp))
					MeshLib.collider(MeshLib.capsule_shape(0.15, 0.8), hp + Vector3(0, 0.4, 0), Vector3.ZERO, body)
				for k in rng.randi_range(0, 2):
					var bp: Vector3 = a + dir * len * rng.randf_range(0.15, 0.85) + inn * 0.6
					_put("bin", bi, bj, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), bp))
					MeshLib.collider(MeshLib.capsule_shape(0.28, 1.0), bp + Vector3(0, 0.5, 0), Vector3.ZERO, body)
				if rng.randf() < 0.5:
					var bp: Vector3 = a + dir * len * rng.randf_range(0.3, 0.7) + inn * 2.55
					_put("bench", bi, bj, Transform3D(_face_z(road_side), bp))
			# traffic lights on two opposite corners of the block
			for corner in [[Vector3(x0 + 0.5, CURB_H, z0 + 0.5), Vector3(-1, 0, 0)], [Vector3(x1 - 0.5, CURB_H, z1 - 0.5), Vector3(1, 0, 0)]]:
				var p: Vector3 = corner[0]
				var out: Vector3 = corner[1]
				_put("light", bi, bj, Transform3D(_face_x(out), p))
				MeshLib.collider(MeshLib.capsule_shape(0.12, 5.5), p + Vector3(0, 2.75, 0), Vector3.ZERO, body)
	var meshes := {"lamp": _lamp_mesh(), "tree0": _tree_mesh(0), "tree1": _tree_mesh(1), "tree2": _tree_mesh(2),
		"light": _traffic_light_mesh(), "hydrant": _hydrant_mesh(), "bin": _bin_mesh(), "bench": _bench_mesh()}
	var ranges := {"lamp": 170.0, "tree0": 150.0, "tree1": 150.0, "tree2": 150.0, "light": 150.0, "hydrant": 75.0, "bin": 75.0, "bench": 75.0}
	for key in _chunks.keys():
		var c: Dictionary = _chunks[key]
		var center := Vector3(road_x(key.x * 2) + BLOCK, 0, road_x(key.y * 2) + BLOCK)
		for kind in c.keys():
			var arr: Array[Transform3D] = []
			for t in c[kind]:
				var tt: Transform3D = t
				tt.origin -= center
				arr.append(tt)
			_mm(meshes[kind], arr, kind in ["lamp", "tree0", "tree1", "tree2", "light"], ranges[kind], center)
	_chunks.clear()

## Basis whose local +X points along `dir` (horizontal).
func _face_x(dir: Vector3) -> Basis:
	var x := Vector3(dir.x, 0, dir.z).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))

## Basis whose local -Z points along `dir` (horizontal).
func _face_z(dir: Vector3) -> Basis:
	return Basis.looking_at(Vector3(dir.x, 0, dir.z).normalized(), Vector3.UP)

func _mm(mesh: Mesh, xforms: Array[Transform3D], shadows: bool, vis: float = 0.0, origin := Vector3.ZERO) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MeshLib.atlas()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = origin
	mmi.visibility_range_end = vis
	add_child(mmi)

static func _lamp_mesh() -> ArrayMesh:
	var g := Geo.new()
	var metal := Color(0.22, 0.23, 0.25)
	g.mat(metal, 0.45, 0.7).lathe([Vector2(0.0, 0.0), Vector2(0.13, 0.0), Vector2(0.12, 0.35), Vector2(0.08, 0.45), Vector2(0.065, 3.0), Vector2(0.05, 6.4), Vector2(0.0, 6.45)], 8)
	var rings := []
	for k in 7:
		var t := float(k) / 6.0
		var p := Vector3(t * 1.6, 6.15 + sin(t * PI * 0.5) * 0.45 - t * t * 0.25, 0)
		var tang := Vector3(1.6, cos(t * PI * 0.5) * PI * 0.5 * 0.45 - 2.0 * t * 0.25, 0)
		rings.append(Geo.ring_axis(p, tang, 0.04, 0.04, 6))
	g.mat(metal, 0.45, 0.7).loft(rings, true, true)
	g.mat(metal, 0.4, 0.7).rbox(Vector3(1.75, 6.33, 0), Vector3(0.62, 0.12, 0.28), 0.05, 1)
	g.mat(Color(1.0, 0.95, 0.82), 0.2, 0.0, 1.6).rbox(Vector3(1.75, 6.265, 0), Vector3(0.5, 0.02, 0.2), 0.008, 0)
	g.mat(Color(0.2, 0.2, 0.22), 0.6, 0.3).rbox(Vector3(0, 1.1, -0.08), Vector3(0.14, 0.24, 0.06), 0.02, 0)
	return g.mesh()

static func _foliage(g: Geo, c: Vector3, r: Vector3, col: Color, seed: float) -> void:
	var start := g.verts.size()
	g.mat(col, 0.85).ellipsoid(c, r, 8, 5)
	for i in range(start, g.verts.size()):
		var p := g.verts[i]
		var d := (p - c)
		var nrm := d.normalized()
		var bump := sin(nrm.x * 7.0 + seed) * sin(nrm.y * 6.0 + seed * 1.7) * sin(nrm.z * 7.5 + seed * 0.6)
		g.verts[i] = p + nrm * bump * r.length() * 0.09
		var shade := clampf(0.82 + (d.y / r.y) * 0.22, 0.65, 1.08)
		var cc := g.cols[i]
		g.cols[i] = Color(cc.r * shade, cc.g * shade, cc.b * shade, 0.0)

static func _tree_mesh(v: int) -> ArrayMesh:
	var g := Geo.new()
	var bark := Color(0.45, 0.36, 0.28)
	var h: float = [3.3, 4.0, 2.8][v]
	g.mat(Color(0.3, 0.23, 0.16), 0.98).ellipsoid(Vector3(0, 0.0, 0), Vector3(0.5, 0.006, 0.5), 8, 2)
	g.mat(bark, 0.95).lathe([Vector2(0.0, 0.0), Vector2(0.17, 0.0), Vector2(0.13, 0.35), Vector2(0.11, h * 0.65), Vector2(0.075, h), Vector2(0.0, h + 0.05)], 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + v
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf() * 0.5
		var s := Vector3(0, h * rng.randf_range(0.55, 0.8), 0)
		var e := s + Vector3(cos(a) * 1.0, rng.randf_range(0.7, 1.2), sin(a) * 1.0)
		g.mat(bark, 0.95).capsule(s, e, 0.06, 0.03, 5, 1)
	var greens := [Color(0.36, 0.56, 0.24), Color(0.42, 0.6, 0.26), Color(0.32, 0.5, 0.22), Color(0.48, 0.62, 0.3)]
	var top: float = h + 0.7
	var clumps := [[Vector3(0, top, 0), Vector3(1.6, 1.3, 1.6)]]
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf() * 0.6
		var rr := rng.randf_range(0.9, 1.3)
		clumps.append([Vector3(cos(a) * rr, top + rng.randf_range(-0.7, 0.5), sin(a) * rr), Vector3(1.0, 0.85, 1.0) * rng.randf_range(0.8, 1.15)])
	if v == 1:
		clumps.append([Vector3(0, top + 1.2, 0), Vector3(1.1, 1.0, 1.1)])
	for i in clumps.size():
		var cl: Array = clumps[i]
		_foliage(g, cl[0], cl[1], greens[rng.randi_range(0, greens.size() - 1)], float(i) * 3.1 + v)
	return g.mesh()

static func _pit_mesh() -> ArrayMesh:
	var g := Geo.new()
	g.mat(Color(0.16, 0.12, 0.09), 0.95).quad(Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0), Vector3.BACK)
	return g.mesh()

static func _traffic_light_mesh() -> ArrayMesh:
	var g := Geo.new()
	var metal := Color(0.18, 0.19, 0.2)
	g.mat(metal, 0.5, 0.6).lathe([Vector2(0.0, 0.0), Vector2(0.14, 0.0), Vector2(0.11, 0.3), Vector2(0.08, 0.35), Vector2(0.075, 5.6), Vector2(0.0, 5.65)], 8)
	g.mat(metal, 0.5, 0.6).capsule(Vector3(0, 5.3, 0), Vector3(4.2, 5.4, 0), 0.055, 0.045, 6, 1)
	for hx in [2.4, 4.0]:
		g.mat(Color(0.08, 0.08, 0.09), 0.5, 0.2).rbox(Vector3(hx, 4.85, 0), Vector3(0.32, 0.92, 0.3), 0.05, 1)
		var cols := [[Color(1.0, 0.15, 0.1), 1.2], [Color(0.45, 0.35, 0.05), 0.0], [Color(0.05, 0.3, 0.12), 0.0]]
		for k in 3:
			var c: Array = cols[k]
			for face in [-1.0, 1.0]:
				var lit: float = c[1] if face < 0 else [0.0, 0.0, 1.2][k]
				var lc: Color = c[0] if face < 0 else [Color(0.4, 0.05, 0.03), Color(0.45, 0.35, 0.05), Color(0.1, 1.0, 0.45)][k]
				g.mat(lc, 0.15, 0.0, lit).ellipsoid(Vector3(hx, 5.12 - k * 0.27, face * 0.15), Vector3(0.095, 0.095, 0.03), 8, 3)
				g.mat(Color(0.05, 0.05, 0.05), 0.5).rbox(Vector3(hx, 5.19 - k * 0.27, face * 0.2), Vector3(0.24, 0.02, 0.1), 0.008, 0)
	# pedestrian signal on the pole
	g.mat(Color(0.08, 0.08, 0.09), 0.5).rbox(Vector3(0.0, 2.6, -0.2), Vector3(0.28, 0.3, 0.2), 0.03, 0)
	g.mat(Color(1.0, 0.45, 0.1), 0.2, 0.0, 0.8).rbox(Vector3(0.0, 2.6, -0.305), Vector3(0.2, 0.22, 0.01), 0.004, 0)
	return g.mesh()

static func _hydrant_mesh() -> ArrayMesh:
	var g := Geo.new()
	var red := Color(0.72, 0.1, 0.07)
	g.mat(red, 0.45, 0.2).lathe([Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.16, 0.06), Vector2(0.12, 0.08), Vector2(0.11, 0.55), Vector2(0.14, 0.58), Vector2(0.13, 0.64), Vector2(0.1, 0.72), Vector2(0.03, 0.8), Vector2(0.0, 0.82)], 10)
	for a in [0.0, PI]:
		var d := Vector3(cos(a), 0, sin(a))
		g.mat(red, 0.45, 0.2).capsule(d * 0.08 + Vector3(0, 0.42, 0), d * 0.2 + Vector3(0, 0.42, 0), 0.045, 0.045, 8, 1)
	g.mat(Color(0.75, 0.73, 0.68), 0.35, 0.8).capsule(Vector3(0, 0.38, -0.08), Vector3(0, 0.38, -0.2), 0.055, 0.055, 8, 1)
	return g.mesh()

static func _bin_mesh() -> ArrayMesh:
	var g := Geo.new()
	var green := Color(0.12, 0.22, 0.16)
	g.mat(green, 0.5, 0.5).lathe([Vector2(0.0, 0.0), Vector2(0.24, 0.0), Vector2(0.27, 0.06), Vector2(0.29, 0.85), Vector2(0.3, 0.88), Vector2(0.27, 0.92), Vector2(0.0, 0.93)], 14)
	g.mat(Color(0.05, 0.05, 0.05), 0.8).lathe([Vector2(0.0, 0.94), Vector2(0.2, 0.935), Vector2(0.0, 0.936)], 12)
	g.mat(green.lightened(0.1), 0.5, 0.5).lathe([Vector2(0.0, 0.93), Vector2(0.31, 0.92), Vector2(0.31, 0.96), Vector2(0.18, 1.02), Vector2(0.0, 1.03)], 14)
	return g.mesh()

static func _bench_mesh() -> ArrayMesh:
	var g := Geo.new()
	var wood := Color(0.5, 0.33, 0.18)
	var metal := Color(0.12, 0.12, 0.13)
	for k in 3:
		g.mat(wood, 0.7).rbox(Vector3(0, 0.45, -0.18 + k * 0.13), Vector3(1.7, 0.04, 0.11), 0.015, 0)
	for k in 2:
		g.mat(wood, 0.7).rbox(Vector3(0, 0.62 + k * 0.15, 0.2), Vector3(1.7, 0.11, 0.035), 0.015, 0)
	for sx in [-0.75, 0.75]:
		g.mat(metal, 0.5, 0.6).rbox(Vector3(sx, 0.22, -0.05), Vector3(0.05, 0.44, 0.45), 0.015, 0)
		g.mat(metal, 0.5, 0.6).rbox(Vector3(sx, 0.62, 0.21), Vector3(0.05, 0.4, 0.04), 0.015, 0)
		g.mat(metal, 0.5, 0.6).rbox(Vector3(sx, 0.55, -0.05), Vector3(0.05, 0.04, 0.5), 0.015, 0)
	return g.mesh()

# ---------------------------------------------------------------- lighting
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.35
	sun.shadow_enabled = Game.shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 32.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_opacity = 0.85
	add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	var skym := ProceduralSkyMaterial.new()
	skym.sky_top_color = Color(0.2, 0.4, 0.78)
	skym.sky_horizon_color = Color(0.72, 0.8, 0.9)
	skym.ground_bottom_color = Color(0.3, 0.3, 0.32)
	skym.ground_horizon_color = Color(0.7, 0.75, 0.8)
	skym.sun_angle_max = 12.0
	skym.sun_curve = 0.1
	sky.sky_material = skym
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.77, 0.86)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.15
	env.fog_sun_scatter = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# ---------------------------------------------------------------- navigation
func walk_count() -> int:
	return walk_lines.size()

func walk_pos(a: int, b: int) -> Vector3:
	return Vector3(walk_lines[clampi(a, 0, walk_lines.size() - 1)], CURB_H, walk_lines[clampi(b, 0, walk_lines.size() - 1)])

func nearest_walk_node(p: Vector3) -> Vector2i:
	var best_a := 0
	var best_b := 0
	var ba := INF
	var bb := INF
	for i in walk_lines.size():
		var da := absf(walk_lines[i] - p.x)
		if da < ba:
			ba = da
			best_a = i
		var db := absf(walk_lines[i] - p.z)
		if db < bb:
			bb = db
			best_b = i
	return Vector2i(best_a, best_b)

func next_walk_node(cur: Vector2i, prev: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cur + d
		if n.x < 0 or n.y < 0 or n.x >= walk_lines.size() or n.y >= walk_lines.size():
			continue
		if n == prev and Game.rng.randf() < 0.85:
			continue
		options.append(n)
	if options.is_empty():
		return prev
	return options[Game.rng.randi_range(0, options.size() - 1)]

func random_walk_node() -> Vector2i:
	return Vector2i(Game.rng.randi_range(0, walk_lines.size() - 1), Game.rng.randi_range(0, walk_lines.size() - 1))

func random_walk_point_near(center: Vector3, min_r: float, max_r: float) -> Vector3:
	for attempt in 12:
		var n := random_walk_node()
		var p := walk_pos(n.x, n.y)
		var d := Game.flat(p - center).length()
		if d >= min_r and d <= max_r:
			return p
	var n := nearest_walk_node(center + Vector3(Game.randf_range(-max_r, max_r), 0, Game.randf_range(-max_r, max_r)))
	return walk_pos(n.x, n.y)

func road_pos(i: int, j: int) -> Vector3:
	return Vector3(road_x(clampi(i, 0, N)), 0.0, road_x(clampi(j, 0, N)))

func nearest_road_node(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(round((p.x + HALF) / BLOCK)), 0, N), clampi(int(round((p.z + HALF) / BLOCK)), 0, N))

func next_road_node(cur: Vector2i, prev: Vector2i, toward: Vector3 = Vector3.INF) -> Vector2i:
	var options: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cur + d
		if n.x < 0 or n.y < 0 or n.x > N or n.y > N:
			continue
		if n == prev:
			continue
		options.append(n)
	if options.is_empty():
		return prev
	if toward != Vector3.INF:
		var best := options[0]
		var bd := INF
		for o in options:
			var dd := Game.flat(road_pos(o.x, o.y) - toward).length()
			if dd < bd:
				bd = dd
				best = o
		return best
	return options[Game.rng.randi_range(0, options.size() - 1)]

func lane_point(a: Vector2i, b: Vector2i, t: float = 1.0) -> Vector3:
	var pa := road_pos(a.x, a.y)
	var pb := road_pos(b.x, b.y)
	var dir := (pb - pa).normalized()
	var right := dir.cross(Vector3.UP) * LANE
	return pa.lerp(pb, t) + right

func random_road_point_near(center: Vector3, min_r: float, max_r: float) -> Dictionary:
	for attempt in 14:
		var a := Vector2i(Game.rng.randi_range(0, N), Game.rng.randi_range(0, N))
		var b := next_road_node(a, Vector2i(-9, -9))
		var p := lane_point(a, b, Game.randf_range(0.2, 0.8))
		var d := Game.flat(p - center).length()
		if d >= min_r and d <= max_r:
			return {"pos": p, "from": a, "to": b}
	var a := nearest_road_node(center)
	var b := next_road_node(a, Vector2i(-9, -9))
	return {"pos": lane_point(a, b, 0.5), "from": a, "to": b}

func in_bounds(p: Vector3) -> bool:
	return absf(p.x) < HALF + 30.0 and absf(p.z) < HALF + 30.0
