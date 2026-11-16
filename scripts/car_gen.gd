class_name CarGen
extends RefCounted
## Procedural car bodies. A lower body is lofted along the car (with wheel
## arches, a shaped nose and tail, headlights, grille and door seams painted
## into the surface) and a cabin is lofted on top (raked windshield, pillars,
## side windows, rear window). Geometry is cached per body type and recoloured
## through a palette, so every paint colour costs one mesh build.

enum { PAINT, PAINT2, GLASS, TRIM, UNDER, CHROME, HEADLIGHT, TAILLIGHT, GRILLE, PLATE, INTERIOR, SEAT, DASH, TIRE, RIM, SIGN, BLACK }

const TYPES := {
	"sedan": {"len": 4.6, "hw": 0.9, "wb": 2.7, "wr": 0.33, "bot": 0.27, "hood": 0.92, "belt": 0.95, "roof": 1.44, "trunk": 0.98,
		"ws": -0.75, "rf": -0.08, "rr": 0.72, "rw": 1.25, "tail": "trunk", "mass": 1350.0},
	"hatch": {"len": 4.1, "hw": 0.87, "wb": 2.5, "wr": 0.31, "bot": 0.26, "hood": 0.9, "belt": 0.95, "roof": 1.47, "trunk": 1.0,
		"ws": -0.62, "rf": 0.05, "rr": 1.15, "rw": 1.85, "tail": "hatch", "mass": 1150.0},
	"suv": {"len": 4.75, "hw": 0.95, "wb": 2.8, "wr": 0.38, "bot": 0.42, "hood": 1.12, "belt": 1.15, "roof": 1.8, "trunk": 1.15,
		"ws": -0.85, "rf": -0.25, "rr": 1.95, "rw": 2.28, "tail": "hatch", "mass": 1900.0},
	"van": {"len": 5.0, "hw": 0.98, "wb": 3.1, "wr": 0.36, "bot": 0.36, "hood": 1.05, "belt": 1.12, "roof": 2.15, "trunk": 1.12,
		"ws": -1.55, "rf": -1.0, "rr": 2.42, "rw": 2.5, "tail": "van", "mass": 2200.0},
}

static var _geo_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}

static func dims(t: String) -> Dictionary:
	return TYPES["sedan" if t in ["police", "taxi"] else t]

## Returns {"body", "interior", "tail", "wheel"} meshes for a type + colour.
static func meshes(t: String, paint: Color) -> Dictionary:
	var key := t + "_" + paint.to_html()
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var base := "sedan" if t in ["police", "taxi"] else t
	var g := _body_geo(base, t)
	var pal := palette(t, paint)
	var res := {
		"body": g.mesh(pal),
		"interior": _interior_geo(base).mesh(pal),
		"tail": _tail_geo(base).mesh(pal),
		"wheel": wheel_mesh(dims(t)["wr"]),
	}
	_mesh_cache[key] = res
	return res

static func palette(t: String, paint: Color) -> Dictionary:
	var p := {}
	var paint_m := [paint, 0.22, 0.55, 0.0]
	p[PAINT] = paint_m
	p[PAINT2] = paint_m
	if t == "police":
		p[PAINT] = [Color(0.05, 0.05, 0.06), 0.22, 0.5, 0.0]
		p[PAINT2] = [Color(0.94, 0.94, 0.95), 0.22, 0.45, 0.0]
	elif t == "taxi":
		p[PAINT] = [Color(0.98, 0.76, 0.05), 0.25, 0.4, 0.0]
		p[PAINT2] = p[PAINT]
	p[GLASS] = [Color(0.05, 0.07, 0.09), 0.04, 0.6, 0.0]
	p[TRIM] = [Color(0.06, 0.06, 0.065), 0.55, 0.1, 0.0]
	p[UNDER] = [Color(0.03, 0.03, 0.03), 0.9, 0.0, 0.0]
	p[CHROME] = [Color(0.85, 0.86, 0.88), 0.12, 1.0, 0.0]
	p[HEADLIGHT] = [Color(0.95, 0.95, 0.9), 0.05, 0.3, 0.35]
	p[TAILLIGHT] = [Color(0.45, 0.02, 0.02), 0.1, 0.2, 0.0]
	p[GRILLE] = [Color(0.04, 0.04, 0.045), 0.4, 0.4, 0.0]
	p[PLATE] = [Color(0.92, 0.92, 0.88), 0.4, 0.0, 0.0]
	p[INTERIOR] = [Color(0.16, 0.16, 0.17), 0.85, 0.0, 0.0]
	p[SEAT] = [Color(0.12, 0.11, 0.11), 0.7, 0.0, 0.0]
	p[DASH] = [Color(0.08, 0.08, 0.085), 0.6, 0.0, 0.0]
	p[TIRE] = [Color(0.05, 0.05, 0.05), 0.92, 0.0, 0.0]
	p[RIM] = [Color(0.72, 0.73, 0.76), 0.25, 0.9, 0.0]
	p[SIGN] = [Color(1.0, 0.95, 0.6), 0.4, 0.0, 0.4] if t == "taxi" else null
	p[BLACK] = [Color(0.02, 0.02, 0.02), 0.6, 0.0, 0.0]
	return p

# ---------------------------------------------------------------- profiles
static func _interp(pts: Array, z: float) -> float:
	if z <= pts[0][0]:
		return pts[0][1]
	for i in pts.size() - 1:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if z <= b[0]:
			var t: float = (z - a[0]) / (b[0] - a[0])
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(a[1], b[1], t)
	return pts[pts.size() - 1][1]

static func _top_profile(d: Dictionary) -> Array:
	var h: float = d["len"] * 0.5
	var hood: float = d["hood"]
	var belt: float = d["belt"]
	var trunk: float = d["trunk"]
	var ws: float = d["ws"]
	var bot: float = d["bot"]
	var front := [[-h - 0.02, bot + 0.3], [-h + 0.04, hood - 0.16], [-h + 0.16, hood - 0.07], [-h + 0.5, hood - 0.03], [ws - 0.2, hood], [ws, belt - 0.02]]
	var back: Array
	match d["tail"]:
		"trunk":
			back = [[d["rw"], trunk], [h - 0.45, trunk + 0.01], [h - 0.18, trunk - 0.03], [h - 0.04, trunk - 0.15], [h + 0.02, bot + 0.26]]
		"hatch":
			back = [[d["rw"] - 0.3, belt], [h - 0.12, belt + 0.02], [h - 0.02, belt - 0.12], [h + 0.02, bot + 0.25]]
		_:
			back = [[h - 0.15, belt + 0.02], [h - 0.02, belt - 0.1], [h + 0.02, bot + 0.25]]
	return front + back

static func _bottom_y(d: Dictionary, z: float) -> float:
	var h: float = d["len"] * 0.5
	var bot: float = d["bot"]
	var y := bot
	var wr: float = d["wr"]
	for zc in [-d["wb"] * 0.5, d["wb"] * 0.5]:
		var dz := absf(z - zc)
		var ar := wr + 0.07
		if dz < ar:
			y = maxf(y, wr + sqrt(ar * ar - dz * dz) * 1.0)
	# ends tuck up
	y = maxf(y, bot + maxf(0.0, absf(z) - (h - 0.35)) * 0.6)
	return y

static func _half_w(d: Dictionary, z: float) -> float:
	var h: float = d["len"] * 0.5
	var hw: float = d["hw"]
	var e: float = absf(z) - (h - 0.45)
	if e > 0.0:
		hw -= e * e * 0.55
	return hw

# ---------------------------------------------------------------- body
static func _body_geo(base: String, t: String) -> Geo:
	var gkey := base + "_" + t
	if _geo_cache.has(gkey):
		return _geo_cache[gkey]
	var d: Dictionary = TYPES[base]
	var g := Geo.new()
	var h: float = d["len"] * 0.5
	var top := _top_profile(d)
	var segs := 20
	# stations along the car (dense at the arches and ends, with door seams)
	var zs: Array[float] = []
	var z := -h - 0.02
	while z < h + 0.02:
		zs.append(z)
		var near_end := absf(z) > h - 0.4
		var near_arch: bool = absf(absf(z) - d["wb"] * 0.5) < d["wr"] + 0.12
		z += 0.07 if near_end else (0.09 if near_arch else 0.22)
	zs.append(h + 0.02)
	var seams: Array[float] = []
	var ws: float = d["ws"]
	if base != "van":
		seams = [ws + 0.05, lerpf(ws, d["rw"], 0.5), d["rw"] - 0.08]
	else:
		seams = [ws + 0.05, ws + 1.1]
	for sz in seams:
		zs.append(sz)
		zs.append(sz + 0.014)
	zs.sort()
	var rings := []
	var info := []
	for i in zs.size():
		var zz: float = zs[i]
		var yt := _interp(top, zz)
		var yb := _bottom_y(d, zz)
		if yt - yb < 0.08:
			yt = yb + 0.08
		var hw := _half_w(d, zz)
		var endf := clampf((absf(zz) - (h - 0.06)) / 0.08, 0.0, 1.0)
		hw *= 1.0 - endf * 0.12
		var yc := (yt + yb) * 0.5
		var hh := (yt - yb) * 0.5
		rings.append(Geo.ring_xy(zz, yc, hw, hh, segs, 5.0, hw * 0.94))
		info.append([zz, yb, yt, hw])
	var is_seam := func(i: int) -> bool:
		for sz in seams:
			if absf(info[i][0] - sz) < 0.001:
				return true
		return false
	var police := t == "police"
	var mat_fn := func(i: int, k: int):
		var a := TAU * (float(k) + 0.5) / segs
		var xn := cos(a)
		var yn := sin(a)
		var zm: float = (info[i][0] + info[i + 1][0]) * 0.5
		var side := absf(xn) > 0.8
		if yn < -0.8:
			return UNDER
		var front := zm < -h + 0.22
		var rear := zm > h - 0.2
		if front and yn < -0.3:
			return TRIM
		if rear:
			if yn > 0.25 and yn < 0.7 and absf(xn) > 0.5 and absf(xn) < 0.93:
				return TAILLIGHT
			if yn < -0.3:
				return TRIM
		if is_seam.call(i) and side and yn > -0.55 and yn < 0.85:
			return BLACK
		if side and yn < -0.74:
			return TRIM
		if police and zm > ws and zm < d["rw"] - 0.05 and yn < 0.8:
			return PAINT2
		return PAINT
	g.loft_q(rings, mat_fn, TRIM, TRIM)
	# cabin
	_cabin(g, d, police)
	# wheel wells (hide the inside of the arches)
	for zc in [-d["wb"] * 0.5, d["wb"] * 0.5]:
		g.reg(UNDER).rbox(Vector3(0, d["wr"] + 0.25, zc), Vector3(d["hw"] * 1.86, 0.36, (d["wr"] + 0.07) * 2.0), 0.05, 1)
	# headlights and grille set into the nose
	var ny := _interp(top, -h + 0.12)
	for sx in [-1.0, 1.0]:
		g.xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18)), Vector3(sx * (_half_w(d, -h + 0.1) - 0.24), ny - 0.07, -h + 0.08))
		g.reg(CHROME).rbox(Vector3.ZERO, Vector3(0.34, 0.11, 0.1), 0.03, 1)
		g.reg(HEADLIGHT).rbox(Vector3(0, 0, -0.012), Vector3(0.3, 0.085, 0.09), 0.025, 1)
		g.xf = Transform3D.IDENTITY
	g.reg(GRILLE).rbox(Vector3(0, ny - 0.1, -h + 0.04), Vector3(0.62, 0.13, 0.08), 0.03, 1)
	g.reg(CHROME).rbox(Vector3(0, ny - 0.035, -h + 0.03), Vector3(0.64, 0.018, 0.08), 0.008, 1)
	# bumpers, plates, mirrors, handles
	var bw: float = d["hw"] * 1.9
	g.reg(TRIM).rbox(Vector3(0, d["bot"] + 0.13, -h + 0.03), Vector3(bw * 0.92, 0.14, 0.12), 0.05, 1)
	g.reg(TRIM).rbox(Vector3(0, d["bot"] + 0.14, h - 0.03), Vector3(bw * 0.92, 0.14, 0.12), 0.05, 1)
	g.reg(PLATE).rbox(Vector3(0, d["bot"] + 0.19, -h - 0.035), Vector3(0.36, 0.1, 0.012), 0.006, 1)
	g.reg(PLATE).rbox(Vector3(0, d["bot"] + 0.32, h + 0.02), Vector3(0.36, 0.1, 0.012), 0.006, 1)
	for sx in [-1.0, 1.0]:
		var mz: float = ws + 0.18
		g.reg(PAINT).rbox(Vector3(sx * (d["hw"] + 0.06), d["belt"] + 0.06, mz), Vector3(0.12, 0.09, 0.15), 0.035, 1)
		g.reg(GLASS).rbox(Vector3(sx * (d["hw"] + 0.06), d["belt"] + 0.06, mz + 0.07), Vector3(0.1, 0.07, 0.01), 0.004, 1)
		for hz in [ws + 0.7, lerpf(ws, d["rw"], 0.5) + 0.6]:
			if base != "van" or hz < ws + 1.0:
				g.reg(CHROME).rbox(Vector3(sx * (_half_w(d, hz) + 0.005), d["belt"] - 0.07, hz), Vector3(0.02, 0.025, 0.12), 0.01, 1)
	if police:
		# push bar and roof light bar mount
		g.reg(BLACK).rbox(Vector3(0, d["bot"] + 0.25, -h - 0.12), Vector3(1.0, 0.32, 0.06), 0.02, 1)
		for sx in [-0.4, 0.4]:
			g.reg(BLACK).rbox(Vector3(sx, d["bot"] + 0.25, -h - 0.06), Vector3(0.05, 0.3, 0.14), 0.015, 1)
		g.reg(BLACK).rbox(Vector3(0, d["roof"] + 0.03, lerpf(d["rf"], d["rr"], 0.35)), Vector3(1.25, 0.05, 0.3), 0.02, 1)
	if t == "taxi":
		g.reg(SIGN).rbox(Vector3(0, d["roof"] + 0.1, lerpf(d["rf"], d["rr"], 0.4)), Vector3(0.55, 0.16, 0.22), 0.04, 1)
	g.compute_normals()
	_geo_cache[gkey] = g
	return g

static func _cabin(g: Geo, d: Dictionary, police: bool) -> void:
	var ws: float = d["ws"]
	var rf: float = d["rf"]
	var rr: float = d["rr"]
	var rw: float = d["rw"]
	var roof: float = d["roof"]
	var belt: float = d["belt"]
	var segs := 16
	var zs: Array[float] = []
	var steps := 14
	for i in steps + 1:
		zs.append(lerpf(ws - 0.04, rw + 0.04, float(i) / steps))
	var bpil := lerpf(ws, rw, 0.5) if d["tail"] != "van" else ws + 1.1
	zs.append(bpil - 0.05)
	zs.append(bpil + 0.05)
	zs.sort()
	var prof := [[ws - 0.04, belt - 0.03], [ws, belt + 0.01], [rf, roof - 0.01], [lerpf(rf, rr, 0.5), roof + 0.015], [rr, roof - 0.01], [rw, belt + 0.01], [rw + 0.04, belt - 0.03]]
	var rings := []
	var info := []
	for z in zs:
		var yt := _interp(prof, z)
		var yb := belt - 0.06
		var hwb := _half_w(d, z) * 0.97
		var hwt := hwb * 0.8
		rings.append(Geo.ring_xy(z, (yt + yb) * 0.5, hwb, maxf((yt - yb) * 0.5, 0.02), segs, 4.0, hwt))
		info.append([z, yb, yt])
	var mat_fn := func(i: int, k: int):
		var a := TAU * (float(k) + 0.5) / segs
		var xn := cos(a)
		var yn := sin(a)
		var zm: float = (info[i][0] + info[i + 1][0]) * 0.5
		var height: float = (info[i][2] + info[i + 1][2]) * 0.5 - info[i][1]
		if yn < -0.55:
			return null
		var corner := absf(xn) > 0.62 and yn > 0.62
		if yn > 0.62 and not corner:
			if zm < rf - 0.03 or zm > rr + 0.03:
				return GLASS
			return PAINT
		if corner:
			return PAINT
		# sides
		if yn < -0.25:
			return PAINT2 if police else PAINT
		if absf(zm - bpil) < 0.05:
			return BLACK
		if d["tail"] == "van" and zm > bpil + 0.05 and zm < rw - 0.4:
			return PAINT
		if height > 0.3:
			return GLASS
		return PAINT
	g.loft_q(rings, mat_fn)

## Inside of the cabin seen while driving: headliner, pillars, door cards,
## dashboard and seats (glass is left open so you can see out).
static func _interior_geo(base: String) -> Geo:
	var key := "int_" + base
	if _geo_cache.has(key):
		return _geo_cache[key]
	var d: Dictionary = TYPES[base]
	var g := Geo.new()
	var ws: float = d["ws"]
	var belt: float = d["belt"]
	var hw: float = d["hw"]
	var tmp := Geo.new()
	_cabin(tmp, d, false)
	var pal := {GLASS: null, PAINT: [Color(0.2, 0.2, 0.21), 0.9, 0.0, 0.0], PAINT2: [Color(0.2, 0.2, 0.21), 0.9, 0.0, 0.0], BLACK: [Color(0.1, 0.1, 0.1), 0.8, 0.0, 0.0]}
	var arr := tmp.arrays(pal, false, -1, Transform3D(Basis().scaled(Vector3(0.985, 0.99, 0.99)), Vector3(0, -0.005, 0)), true)
	_append_arrays(g, arr)
	# door cards and floor
	for sx in [-1.0, 1.0]:
		g.reg(INTERIOR).rbox(Vector3(sx * (hw * 0.86 - 0.04), belt - 0.22, lerpf(ws, d["rw"], 0.5)), Vector3(0.04, 0.38, (d["rw"] - ws) * 0.9), 0.015, 1)
	g.reg(INTERIOR).rbox(Vector3(0, d["bot"] + 0.12, lerpf(ws, d["rw"], 0.5)), Vector3(hw * 1.8, 0.06, (d["rw"] - ws)), 0.02, 1)
	# dashboard with instrument binnacle and centre console
	g.reg(DASH).rbox(Vector3(0, belt - 0.08, ws + 0.12), Vector3(hw * 1.85, 0.2, 0.42), 0.06, 1)
	g.reg(DASH).rbox(Vector3(-0.38, belt + 0.03, ws + 0.28), Vector3(0.34, 0.08, 0.14), 0.03, 1)
	g.reg(HEADLIGHT).rbox(Vector3(-0.38, belt + 0.03, ws + 0.348), Vector3(0.26, 0.05, 0.004), 0.002, 1)
	g.reg(DASH).rbox(Vector3(0, belt - 0.3, ws + 0.55), Vector3(0.22, 0.25, 0.7), 0.04, 1)
	# seats
	var seat_z: float = ws + 0.85 if base != "van" else ws + 0.7
	for sx in [-0.38, 0.38]:
		g.reg(SEAT).rbox(Vector3(sx, d["bot"] + 0.2, seat_z), Vector3(0.48, 0.14, 0.5), 0.05, 1)
		g.xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18)), Vector3(sx, d["bot"] + 0.55, seat_z + 0.3))
		g.reg(SEAT).rbox(Vector3.ZERO, Vector3(0.46, 0.62, 0.12), 0.05, 1)
		g.reg(SEAT).rbox(Vector3(0, 0.4, 0.0), Vector3(0.26, 0.17, 0.1), 0.04, 1)
		g.xf = Transform3D.IDENTITY
	if base in ["sedan", "suv", "hatch"]:
		var rz: float = minf(seat_z + 0.85, d["rw"] - 0.45)
		g.reg(SEAT).rbox(Vector3(0, d["bot"] + 0.22, rz), Vector3(hw * 1.6, 0.14, 0.45), 0.05, 1)
		g.xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-16)), Vector3(0, d["bot"] + 0.52, rz + 0.27))
		g.reg(SEAT).rbox(Vector3.ZERO, Vector3(hw * 1.6, minf(0.55, belt + 0.1 - d["bot"] - 0.25), 0.1), 0.04, 1)
		g.xf = Transform3D.IDENTITY
	g.compute_normals()
	_geo_cache[key] = g
	return g

static func _append_arrays(g: Geo, arr: Array) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var m: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var base := g.verts.size()
	g.compute_normals()
	g.new_group()
	for i in v.size():
		g.verts.append(v[i])
		g.norms.append(n[i])
		g.cols.append(c[i])
		g.mats.append(m[i])
		g.regions.append(-1)
		g.bones.append(0)
		g.groups.append(g.group + 500000)
	for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
		g.idx.append(base + i)
	g._normals_done = true

static func _tail_geo(base: String) -> Geo:
	var key := "tail_" + base
	if _geo_cache.has(key):
		return _geo_cache[key]
	var d: Dictionary = TYPES[base]
	var g := Geo.new()
	var h: float = d["len"] * 0.5
	var y := _interp(_top_profile(d), h - 0.1) - 0.13
	for sx in [-1.0, 1.0]:
		g.reg(TAILLIGHT).rbox(Vector3(sx * (d["hw"] - 0.17), y, h - 0.02), Vector3(0.26, 0.1, 0.05), 0.02, 1)
	_geo_cache[key] = g
	return g

static var _wheels: Dictionary = {}

static func wheel_mesh(r: float) -> ArrayMesh:
	var key := "%.3f" % r
	if _wheels.has(key):
		return _wheels[key]
	var g := Geo.new()
	var s := r / 0.33
	g.xf = Transform3D(Basis(Vector3.BACK, PI / 2.0))   # lathe Y -> wheel axle (X)
	var tire := [Vector2(0.215, -0.1), Vector2(0.27, -0.112), Vector2(0.315, -0.106), Vector2(0.33, -0.08), Vector2(0.335, -0.03),
		Vector2(0.335, 0.03), Vector2(0.33, 0.08), Vector2(0.315, 0.106), Vector2(0.27, 0.112), Vector2(0.215, 0.1)]
	for i in tire.size():
		tire[i] = tire[i] * s
	g.mat(Color(0.05, 0.05, 0.05), 0.92).lathe(tire, 16, false, false)
	g.mat(Color(0.7, 0.71, 0.74), 0.25, 0.9).lathe([Vector2(0.0, 0.085 * s), Vector2(0.05 * s, 0.087 * s), Vector2(0.215 * s, 0.075 * s), Vector2(0.222 * s, 0.06 * s),
		Vector2(0.222 * s, -0.06 * s), Vector2(0.215 * s, -0.075 * s), Vector2(0.05 * s, -0.087 * s), Vector2(0.0, -0.085 * s)], 12, false, false)
	g.xf = Transform3D.IDENTITY
	# dark wheel face with five radial spokes and a hub on both sides
	for face in [-1.0, 1.0]:
		g.xf = Transform3D.IDENTITY
		g.mat(Color(0.05, 0.05, 0.055), 0.7).ellipsoid(Vector3(face * 0.084 * s, 0, 0), Vector3(0.004, 0.2 * s, 0.2 * s), 12, 2)
		for k in 5:
			g.xf = Transform3D(Basis(Vector3.RIGHT, TAU * k / 5.0), Vector3.ZERO)
			g.mat(Color(0.74, 0.75, 0.78), 0.25, 0.95).rbox(Vector3(face * 0.088 * s, 0.11 * s, 0), Vector3(0.016, 0.2 * s, 0.045 * s), 0.008, 0)
		g.xf = Transform3D.IDENTITY
		g.mat(Color(0.78, 0.79, 0.82), 0.2, 1.0).ellipsoid(Vector3(face * 0.09 * s, 0, 0), Vector3(0.014, 0.055, 0.055) * s, 8, 3)
	var m := g.mesh()
	_wheels[key] = m
	return m
