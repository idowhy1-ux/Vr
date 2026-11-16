class_name City
extends Node3D
## Procedural low-poly city: one draw call for the ground, one for all the
## buildings, a few for props. Also provides the sidewalk and road graphs that
## pedestrians and cars navigate.

const N := 8                 # blocks per side
const BLOCK := 44.0          # road center to road center
const ROAD_HALF := 4.0       # road half width (2 lanes)
const WALK_W := 3.0          # sidewalk width
const LANE := 2.0            # lane offset from road center
const HALF := N * BLOCK / 2.0

var buildings: Array = []    # [{pos, size}] for spawn exclusion
var x_lines: PackedFloat32Array = []   # road center lines (also z)
var walk_lines: PackedFloat32Array = []  # sidewalk center lines

func road_x(i: int) -> float:
	return i * BLOCK - HALF

func _ready() -> void:
	for i in N + 1:
		x_lines.append(road_x(i))
	for i in N:
		walk_lines.append(road_x(i) + ROAD_HALF + WALK_W * 0.5)
		walk_lines.append(road_x(i + 1) - ROAD_HALF - WALK_W * 0.5)
	_build_ground()
	_build_buildings()
	_build_props()
	_build_environment()

# ---------------------------------------------------------------- ground
func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(N * BLOCK + 400.0, N * BLOCK + 400.0)
	pm.subdivide_depth = 4
	pm.subdivide_width = 4
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("half_size", HALF)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Game.bit(Game.L_WORLD)
	body.collision_mask = 0
	var shape := WorldBoundaryShape3D.new()
	MeshLib.collider(shape, Vector3.ZERO, Vector3.ZERO, body)
	add_child(body)

# ---------------------------------------------------------------- buildings
func _build_buildings() -> void:
	var rng := Game.rng
	var instances: Array = []
	var body := StaticBody3D.new()
	body.collision_layer = Game.bit(Game.L_WORLD)
	body.collision_mask = 0
	add_child(body)
	for bi in N:
		for bj in N:
			var x0 := road_x(bi) + ROAD_HALF + WALK_W
			var z0 := road_x(bj) + ROAD_HALF + WALK_W
			var zone := BLOCK - 2.0 * (ROAD_HALF + WALK_W)   # 30 m
			var center_dist := Vector2(x0 + zone / 2.0, z0 + zone / 2.0).length() / HALF
			var layout := rng.randi_range(0, 3)
			var lots: Array = []
			if layout == 0:
				lots = [Rect2(x0, z0, zone, zone)]
			elif layout == 1:
				lots = [Rect2(x0, z0, zone / 2.0, zone), Rect2(x0 + zone / 2.0, z0, zone / 2.0, zone)]
			elif layout == 2:
				lots = [Rect2(x0, z0, zone, zone / 2.0), Rect2(x0, z0 + zone / 2.0, zone, zone / 2.0)]
			else:
				var h := zone / 2.0
				lots = [Rect2(x0, z0, h, h), Rect2(x0 + h, z0, h, h), Rect2(x0, z0 + h, h, h), Rect2(x0 + h, z0 + h, h, h)]
			for lot in lots:
				var margin := rng.randf_range(1.0, 2.5)
				var w: float = lot.size.x - margin * 2.0
				var d: float = lot.size.y - margin * 2.0
				var tall := (1.0 - center_dist) * 30.0
				var h := rng.randf_range(7.0, 14.0 + tall) + (rng.randf_range(10.0, 30.0) if rng.randf() < 0.18 else 0.0)
				h = snappedf(h, 3.2)
				var cx: float = lot.position.x + lot.size.x / 2.0
				var cz: float = lot.position.y + lot.size.y / 2.0
				var pos := Vector3(cx, h / 2.0, cz)
				var size := Vector3(w, h, d)
				var wall := _wall_color(rng)
				var custom := Color(rng.randf_range(0.0, 1.0), 0.0, float(rng.randi_range(0, 60)), 0.0)
				instances.append({"pos": pos, "size": size, "color": wall, "custom": custom})
				buildings.append({"pos": pos, "size": size})
				MeshLib.collider(MeshLib.box_shape(size), pos, Vector3.ZERO, body)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = MeshLib.box(Vector3.ONE)
	mm.instance_count = instances.size()
	for i in instances.size():
		var inst: Dictionary = instances[i]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(inst["size"]), inst["pos"]))
		mm.set_instance_color(i, inst["color"])
		mm.set_instance_custom_data(i, inst["custom"])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var sh := Shader.new()
	sh.code = BUILDING_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _wall_color(rng: RandomNumberGenerator) -> Color:
	var palette := [Color(0.78, 0.72, 0.62), Color(0.55, 0.58, 0.62), Color(0.72, 0.45, 0.38), Color(0.85, 0.85, 0.82),
		Color(0.4, 0.45, 0.5), Color(0.62, 0.66, 0.7), Color(0.75, 0.6, 0.45), Color(0.33, 0.36, 0.42), Color(0.9, 0.8, 0.65)]
	return Game.rand_color_variant(palette[rng.randi_range(0, palette.size() - 1)], 0.05)

# ---------------------------------------------------------------- props
func _build_props() -> void:
	var rng := Game.rng
	var lamp_t: Array[Transform3D] = []
	var head_t: Array[Transform3D] = []
	var trunk_t: Array[Transform3D] = []
	var leaf_t: Array[Transform3D] = []
	for bi in N:
		for bj in N:
			var x0 := road_x(bi) + ROAD_HALF
			var z0 := road_x(bj) + ROAD_HALF
			var x1 := road_x(bi + 1) - ROAD_HALF
			var z1 := road_x(bj + 1) - ROAD_HALF
			# lamps on sidewalk edge next to the road
			for k in 2:
				var t := 0.3 + k * 0.4
				lamp_t.append(Transform3D(Basis(), Vector3(x0 + 0.5, 3.0, lerpf(z0, z1, t))))
				lamp_t.append(Transform3D(Basis(), Vector3(x1 - 0.5, 3.0, lerpf(z0, z1, t + 0.2))))
				lamp_t.append(Transform3D(Basis(), Vector3(lerpf(x0, x1, t), 3.0, z0 + 0.5)))
				lamp_t.append(Transform3D(Basis(), Vector3(lerpf(x0, x1, t + 0.2), 3.0, z1 - 0.5)))
			# trees near building edge of the sidewalk
			for k in rng.randi_range(2, 5):
				var side := rng.randi_range(0, 3)
				var t := rng.randf_range(0.1, 0.9)
				var p: Vector3
				if side == 0:
					p = Vector3(x0 + 2.4, 0, lerpf(z0, z1, t))
				elif side == 1:
					p = Vector3(x1 - 2.4, 0, lerpf(z0, z1, t))
				elif side == 2:
					p = Vector3(lerpf(x0, x1, t), 0, z0 + 2.4)
				else:
					p = Vector3(lerpf(x0, x1, t), 0, z1 - 2.4)
				var s := rng.randf_range(0.8, 1.3)
				trunk_t.append(Transform3D(Basis().scaled(Vector3(1, s, 1)), p + Vector3(0, 1.4 * s, 0)))
				leaf_t.append(Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3(0, 3.6 * s, 0)))
	for lt in lamp_t:
		head_t.append(Transform3D(Basis(), lt.origin + Vector3(0, 3.1, 0)))
	_multimesh(MeshLib.cylinder(0.09, 6.0, 6), MeshLib.mat(Color(0.25, 0.26, 0.28), 0.5, 0.6), lamp_t)
	_multimesh(MeshLib.box(Vector3(0.5, 0.25, 0.5)), MeshLib.mat(Color(1.0, 0.95, 0.8), 0.8, 0.0, Color(1.0, 0.9, 0.6), 1.5), head_t)
	_multimesh(MeshLib.cylinder(0.18, 2.8, 6), MeshLib.mat(Color(0.38, 0.26, 0.16), 0.9), trunk_t)
	_multimesh(MeshLib.sphere(1.7, 7, 4), MeshLib.mat(Color(0.2, 0.5, 0.2), 0.9), leaf_t)
	# soft contact shadows under trees and lamp posts (no realtime shadows needed)
	if Game.gore:
		var shadow_t: Array[Transform3D] = []
		for t in leaf_t:
			var s := 4.2 * t.basis.get_scale().x
			shadow_t.append(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(s, s, s)), Vector3(t.origin.x + 0.6, 0.012, t.origin.z + 0.4)))
		for t in lamp_t:
			shadow_t.append(Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(0.7, 0.7, 0.7)), Vector3(t.origin.x, 0.012, t.origin.z)))
		_multimesh(MeshLib.quad(Vector2(1, 1)), Game.gore.blobs.material_override, shadow_t)

func _multimesh(mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# Lamps are solid: add thin collision so cars/ragdolls bump into them.
	if mesh is CylinderMesh and (mesh as CylinderMesh).height > 5.0:
		var body := StaticBody3D.new()
		body.collision_layer = Game.bit(Game.L_WORLD)
		body.collision_mask = 0
		for t in transforms:
			MeshLib.collider(MeshLib.capsule_shape(0.12, 6.0), t.origin, Vector3.ZERO, body)
		add_child(body)

# ---------------------------------------------------------------- lighting
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	var skym := ProceduralSkyMaterial.new()
	skym.sky_top_color = Color(0.25, 0.45, 0.85)
	skym.sky_horizon_color = Color(0.75, 0.82, 0.92)
	skym.ground_bottom_color = Color(0.35, 0.35, 0.35)
	skym.ground_horizon_color = Color(0.7, 0.75, 0.8)
	skym.sun_angle_max = 20.0
	skym.sun_curve = 0.12
	sky.sky_material = skym
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.88)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# ---------------------------------------------------------------- navigation
func walk_count() -> int:
	return walk_lines.size()

func walk_pos(a: int, b: int) -> Vector3:
	return Vector3(walk_lines[clampi(a, 0, walk_lines.size() - 1)], 0.0, walk_lines[clampi(b, 0, walk_lines.size() - 1)])

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

## Lane center point for travelling from node a to node b (drive on the right).
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

# ---------------------------------------------------------------- shaders
const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
uniform float half_size = 176.0;
uniform float block = 44.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// anti-aliased band: 1 inside [a, b], 0 outside, smoothed by the pixel footprint
float band(float x, float a, float b, float w) { return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x)); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz + vec2(half_size);
	vec2 m = mod(p + vec2(block * 0.5), block) - vec2(block * 0.5);
	vec2 r = abs(m);
	bool inside = p.x > -8.0 && p.y > -8.0 && p.x < half_size * 2.0 + 8.0 && p.y < half_size * 2.0 + 8.0;
	float grain = vnoise(p * 0.45) * 0.05 + vnoise(p * 2.1) * 0.025;
	vec3 asphalt = vec3(0.15, 0.15, 0.16) + grain;
	vec3 walk = vec3(0.58, 0.56, 0.52) + grain * 1.5;
	vec3 lot = vec3(0.3, 0.3, 0.28) + grain;
	vec3 outer = vec3(0.32, 0.38, 0.22) + grain;
	vec3 col = outer;
	float rough = 0.95;
	if (inside) {
		col = lot;
		bool road_x = r.x < 4.0;
		bool road_z = r.y < 4.0;
		bool walk_x = r.x < 7.0;
		bool walk_z = r.y < 7.0;
		if (walk_x || walk_z) {
			col = walk;
			// paving tiles
			vec2 tile = fract(p / 1.5);
			vec2 tw = fwidth(p / 1.5) * 1.5;
			float line = smoothstep(0.96 - tw.x, 0.96, tile.x) + smoothstep(0.96 - tw.y, 0.96, tile.y);
			col -= clamp(line, 0.0, 1.0) * 0.06;
		}
		if (road_x || road_z) {
			col = asphalt;
			rough = 0.8;
			// center dashes
			vec2 fw = fwidth(p) + vec2(0.001);
			float dash_x = band(r.x, -1.0, 0.09, fw.x) * band(fract(p.y / 4.0), 0.5, 1.0, fw.y / 4.0) * step(7.0, r.y);
			float dash_z = band(r.y, -1.0, 0.09, fw.y) * band(fract(p.x / 4.0), 0.5, 1.0, fw.x / 4.0) * step(7.0, r.x);
			// edge lines
			float edge_x = band(r.x, 3.7, 3.85, fw.x) * float(road_x) * step(7.0, r.y);
			float edge_z = band(r.y, 3.7, 3.85, fw.y) * float(road_z) * step(7.0, r.x);
			// crosswalks
			float cw_x = float(road_x) * band(r.y, 7.3, 9.3, fw.y) * band(fract(p.x / 1.2), 0.5, 1.0, fw.x / 1.2);
			float cw_z = float(road_z) * band(r.x, 7.3, 9.3, fw.x) * band(fract(p.y / 1.2), 0.5, 1.0, fw.y / 1.2);
			float paint = clamp(dash_x + dash_z + edge_x + edge_z, 0.0, 1.0);
			col = mix(col, vec3(0.85, 0.8, 0.45), paint);
			col = mix(col, vec3(0.9, 0.9, 0.9), clamp(cw_x + cw_z, 0.0, 1.0) * 0.9);
			// gutter darkening near the curb
			float curb = smoothstep(3.0, 4.0, max(float(road_x) * r.x, float(road_z) * r.y));
			col *= 1.0 - curb * 0.25;
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
}
"""

const BUILDING_SHADER := """
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
varying vec3 wpos;
varying vec3 wnrm;
varying flat vec4 icol;
varying flat vec4 icustom;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	icol = COLOR;
	icustom = INSTANCE_CUSTOM;
}
void fragment() {
	vec3 wall = icol.rgb;
	float side = 1.0 - abs(wnrm.y);
	float u = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
	vec2 g = vec2(u, wpos.y - 0.4) / vec2(2.4, 3.2);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	vec2 w = fwidth(g) * 0.75 + vec2(0.0005);
	float wx = smoothstep(0.2 - w.x, 0.2 + w.x, f.x) * (1.0 - smoothstep(0.8 - w.x, 0.8 + w.x, f.x));
	float wy = smoothstep(0.25 - w.y, 0.25 + w.y, f.y) * (1.0 - smoothstep(0.8 - w.y, 0.8 + w.y, f.y));
	// fade the window pattern to its average when it is too fine to resolve (no shimmer in VR)
	float fine = smoothstep(0.25, 0.5, max(w.x, w.y));
	float win = mix(wx * wy, 0.33, fine) * step(1.0, wpos.y);
	float h = hash(cell + vec2(floor(icustom.z), floor(icustom.z) * 0.37));
	vec3 glass = mix(vec3(0.1, 0.14, 0.2), vec3(0.55, 0.68, 0.8), h * 0.6);
	float lit = step(0.72, h) * icustom.x;
	vec3 col = mix(wall, glass, win * side);
	float trim = smoothstep(0.94 - w.y, 0.94 + w.y, f.y) * (1.0 - fine) * side;
	col = mix(col, wall * 0.78, trim * 0.8);
	// ground floor darker band + roof tone
	col = mix(col, wall * 0.7, step(wpos.y, 0.6) * side);
	col = mix(col, wall * 0.6, 1.0 - side);
	// subtle grime at the bottom and per-floor variation
	col *= 1.0 - 0.15 * (1.0 - smoothstep(0.0, 6.0, wpos.y)) * side;
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.3, win * side);
	SPECULAR = mix(0.25, 0.6, win * side);
	EMISSION = vec3(1.0, 0.82, 0.5) * lit * win * side * 0.55;
}
"""
