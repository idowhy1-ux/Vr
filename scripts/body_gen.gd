class_name BodyGen
extends RefCounted
## Procedural human bodies. Each build is generated once as smooth geometry
## tagged with clothing "regions" and bone ids; every person "look" is the same
## geometry recoloured through a palette (regions mapped to null are removed,
## which is how hair styles, beards, sleeves and police gear are switched).

enum { SKIN, SHIRT, SLEEVE_LOW, SLEEVE_FORE, PANTS, THIGH_LOW, PANTS_SHIN, SOCK, SHOES, SOLE,
	HAIR_SHORT, HAIR_LONG, HAIR_PONY, EYE_WHITE, IRIS, LIPS, BROW, BELT, BUCKLE,
	COP_BADGE, COP_HAT, COP_BRIM, COP_GEAR, BEARD, GLASSES, PRINT, COLLAR, POCKET, NOSE_TIP }

const BONES := ["pelvis", "chest", "head", "arm_l", "forearm_l", "arm_r", "forearm_r", "thigh_l", "shin_l", "thigh_r", "shin_r"]
const PARENT := [-1, 0, 1, 1, 3, 1, 5, 0, 7, 0, 9]
enum { B_PELVIS, B_CHEST, B_HEAD, B_ARM_L, B_FORE_L, B_ARM_R, B_FORE_R, B_THIGH_L, B_SHIN_L, B_THIGH_R, B_SHIN_R }

## Rest pivot positions (model space, feet at y = 0, facing -Z, right = +X).
static func pivots(female: bool) -> Array:
	var s := 0.95 if female else 1.0
	var sh := 0.165 if female else 0.18
	var hip := 0.092 if female else 0.095
	return [
		Vector3(0, 0.98, 0) * s,                 # pelvis
		Vector3(0, 1.06, 0) * s,                 # chest (waist)
		Vector3(0, 1.47, 0.005) * s,             # head (neck base)
		Vector3(-sh, 1.41 * s, 0),               # arm_l (shoulder)
		Vector3(-sh - 0.01, 1.125 * s, 0),       # forearm_l (elbow)
		Vector3(sh, 1.41 * s, 0),                # arm_r
		Vector3(sh + 0.01, 1.125 * s, 0),        # forearm_r
		Vector3(-hip, 0.93 * s, 0),              # thigh_l (hip)
		Vector3(-hip - 0.005, 0.50 * s, 0),      # shin_l (knee)
		Vector3(hip, 0.93 * s, 0),               # thigh_r
		Vector3(hip + 0.005, 0.50 * s, 0),       # shin_r
	]

## Collision shape and centre for each bone, in bone-local space.
static func part_shape(b: int, female: bool) -> Array:
	var s := 0.95 if female else 1.0
	match b:
		B_PELVIS:
			return [MeshLib.box_shape(Vector3(0.32, 0.22, 0.22) * s), Vector3(0, -0.03, 0) * s]
		B_CHEST:
			return [MeshLib.box_shape(Vector3(0.33, 0.38, 0.22) * s), Vector3(0, 0.19, 0) * s]
		B_HEAD:
			return [MeshLib.sphere_shape(0.105 * s), Vector3(0, 0.18, -0.01) * s]
		B_ARM_L, B_ARM_R:
			return [MeshLib.capsule_shape(0.048, 0.34 * s), Vector3(0, -0.14, 0) * s]
		B_FORE_L, B_FORE_R:
			return [MeshLib.capsule_shape(0.042, 0.42 * s), Vector3(0, -0.2, 0) * s]
		B_THIGH_L, B_THIGH_R:
			return [MeshLib.capsule_shape(0.075, 0.5 * s), Vector3(0, -0.215, 0) * s]
		_:
			return [MeshLib.capsule_shape(0.055, 0.5 * s), Vector3(0, -0.22, -0.02) * s]

const MASS := [14.0, 24.0, 5.0, 2.5, 2.0, 2.5, 2.0, 8.0, 5.0, 8.0, 5.0]

# ---------------------------------------------------------------- generation
static var _geo_cache: Dictionary = {}
static var LOD := 0     # 0 = near (detailed), 1 = far (light)

static func _s(n: int) -> int:
	return n if LOD == 0 else maxi(6, int(round(n * 0.6)))

static func _r(n: int) -> int:
	return n if LOD == 0 else maxi(3, int(round(n * 0.6)))

## build: 0 male, 1 male heavy, 2 female, 3 female slim
static func geometry(build: int) -> Geo:
	var ckey := build * 10 + LOD
	if _geo_cache.has(ckey):
		return _geo_cache[ckey]
	var female := build >= 2
	var heavy := build == 1
	var slim := build == 3
	var s := 0.95 if female else 1.0
	var g := Geo.new()
	var pv := pivots(female)
	var belly := 0.035 if heavy else (-0.01 if slim else 0.0)
	var bulk := 1.08 if heavy else (0.93 if slim else 1.0)

	# ---------------- pelvis
	g.bone = B_PELVIS
	var hipw := (0.185 if female else 0.172) * bulk
	var butt := (0.135 if female else 0.12)
	var pr := [
		Geo.ring(0.83 * s, 0.07, 0.05, 0.06, _s(14), 2.0, Vector2(0, 0.0)),
		Geo.ring(0.87 * s, hipw * 0.92, 0.095, butt * 0.95, _s(14), 2.4),
		Geo.ring(0.93 * s, hipw, 0.105 + belly * 0.4, butt, _s(14), 2.4),
		Geo.ring(0.99 * s, hipw * 0.96, 0.108 + belly * 0.8, butt * 0.88, _s(14), 2.4),
		Geo.ring(1.035 * s, (0.15 if not female else 0.14) * bulk, 0.106 + belly, 0.095, _s(14), 2.3),
		Geo.ring(1.075 * s, (0.148 if not female else 0.132) * bulk, 0.104 + belly, 0.092, _s(14), 2.3),
	]
	g.loft(pr, true, true, [PANTS, PANTS, PANTS, PANTS, BELT])
	g.reg(BUCKLE).rbox(Vector3(0, 1.055 * s, -(0.108 + belly)), Vector3(0.05, 0.035, 0.012), 0.004, 1)
	g.reg(COP_GEAR).loft([Geo.ring(1.0 * s, hipw * 0.99, 0.112 + belly, butt * 0.92, _s(14), 2.4), Geo.ring(1.05 * s, hipw * 0.95, 0.112 + belly, 0.1, _s(14), 2.4)], false, false, [COP_GEAR])
	g.reg(COP_GEAR).rbox(Vector3(0.175 * s, 0.97 * s, 0.01), Vector3(0.05, 0.15, 0.085), 0.012, 1)
	g.reg(COP_GEAR).rbox(Vector3(-0.17 * s, 1.0 * s, -0.04), Vector3(0.04, 0.07, 0.06), 0.01, 1)
	g.reg(COP_GEAR).rbox(Vector3(-0.12 * s, 1.0 * s, 0.1), Vector3(0.05, 0.06, 0.04), 0.01, 1)

	# ---------------- chest
	g.bone = B_CHEST
	var shw := (0.16 if female else 0.185) * bulk
	var bust := 0.03 if female else 0.0
	var cr := [
		Geo.ring(1.03 * s, (0.155 if not female else 0.142) * bulk, 0.112 + belly, 0.1, _s(14), 2.3),
		Geo.ring(1.12 * s, (0.155 if not female else 0.135) * bulk, 0.112 + belly * 0.9, 0.1, _s(14), 2.3),
		Geo.ring(1.21 * s, (0.162 if not female else 0.142) * bulk, 0.118 + belly * 0.5 + bust * 0.6, 0.105, _s(14), 2.4),
		Geo.ring(1.28 * s, (0.172 if not female else 0.15) * bulk, 0.124 + bust, 0.11, _s(14), 2.5),
		Geo.ring(1.345 * s, shw * 0.97, 0.116 + bust * 0.4, 0.107, _s(14), 2.5),
		Geo.ring(1.39 * s, shw * 0.94, 0.1, 0.1, _s(14), 2.5),
		Geo.ring(1.425 * s, shw * 0.8, 0.08, 0.084, _s(14), 2.4),
		Geo.ring(1.452 * s, 0.105, 0.066, 0.07, _s(14), 2.1, Vector2(0, 0.006)),
		Geo.ring(1.475 * s, 0.062, 0.058, 0.06, _s(14), 2.0, Vector2(0, 0.008)),
	]
	g.loft(cr, true, false, [SHIRT, SHIRT, SHIRT, SHIRT, SHIRT, SHIRT, SHIRT, COLLAR])
	# chest details
	if LOD == 0:
		g.reg(PRINT).rbox(Vector3(0, 1.255 * s, -(0.122 + bust * 0.6 + belly * 0.4) - 0.001), Vector3(0.1, 0.08, 0.005), 0.003, 1)
		g.reg(POCKET).rbox(Vector3(-0.075, 1.3 * s, -(0.121 + bust * 0.8)), Vector3(0.07, 0.075, 0.01), 0.004, 1)
		g.reg(POCKET).rbox(Vector3(0.075, 1.3 * s, -(0.121 + bust * 0.8)), Vector3(0.07, 0.075, 0.01), 0.004, 1)
	g.reg(COP_BADGE).rbox(Vector3(-0.078, 1.355 * s, -(0.116 + bust * 0.4)), Vector3(0.038, 0.045, 0.008), 0.004, 1)
	g.reg(COP_GEAR).rbox(Vector3(0.12, 1.385 * s, -0.08), Vector3(0.035, 0.06, 0.025), 0.006, 1)
	if female:
		g.reg(SHIRT).ellipsoid(Vector3(-0.052, 1.275 * s, -0.112), Vector3(0.056, 0.05, 0.036), _s(12), _r(7))
		g.reg(SHIRT).ellipsoid(Vector3(0.052, 1.275 * s, -0.112), Vector3(0.056, 0.05, 0.036), _s(12), _r(7))

	# ---------------- head + neck
	g.bone = B_HEAD
	var hy := 1.0 * s
	g.reg(SKIN).loft([Geo.ring(1.44 * hy, 0.056, 0.05, 0.058, _s(12), 2.0, Vector2(0, 0.012)),
		Geo.ring(1.52 * hy, 0.054, 0.048, 0.056, _s(12), 2.0, Vector2(0, 0.014)),
		Geo.ring(1.59 * hy, 0.055, 0.05, 0.055, _s(12), 2.0, Vector2(0, 0.016))], false, true)
	g.reg(SKIN).ellipsoid(Vector3(0, 1.672 * hy, 0.012), Vector3(0.078, 0.1, 0.1), _s(16), _r(10))
	var face := [
		Geo.ring(1.53 * hy, 0.03, 0.012, 0.014, _s(14), 2.2, Vector2(0, -0.068)),
		Geo.ring(1.542 * hy, 0.045, 0.022, 0.032, _s(14), 2.3, Vector2(0, -0.06)),
		Geo.ring(1.566 * hy, 0.06, 0.032, 0.056, _s(14), 2.3, Vector2(0, -0.04)),
		Geo.ring(1.596 * hy, 0.067, 0.047, 0.07, _s(14), 2.1, Vector2(0, -0.022)),
		Geo.ring(1.626 * hy, 0.071, 0.07, 0.08, _s(14), 2.0, Vector2(0, -0.01)),
		Geo.ring(1.656 * hy, 0.075, 0.084, 0.085, _s(14), 2.0, Vector2(0, -0.004)),
		Geo.ring(1.69 * hy, 0.075, 0.088, 0.09, _s(14), 2.0, Vector2(0, 0.0)),
	]
	if female:
		for i in 3:
			face[i] = _scale_ring(face[i], Vector3(0.92, 1.0, 0.95), Vector3(0, 0, -0.05))
	g.reg(SKIN).loft(face, true, true)
	# beard (follows the jaw slightly outside it)
	var beard := []
	for i in 4:
		beard.append(_scale_ring(face[i], Vector3(1.06, 1.0, 1.06), Vector3(0, 1.57 * hy, -0.03)))
	g.reg(BEARD).loft(beard, true, false)
	# nose, lips, ears, eyes, brows (fine details only up close)
	if LOD == 0:
		g.reg(SKIN).capsule(Vector3(0, 1.656 * hy, -0.088), Vector3(0, 1.614 * hy, -0.11), 0.009, 0.012, _s(8), 2)
		g.reg(NOSE_TIP).ellipsoid(Vector3(0, 1.609 * hy, -0.104), Vector3(0.017, 0.011, 0.013), _s(10), _r(6))
		g.reg(LIPS).ellipsoid(Vector3(0, 1.587 * hy, -0.083), Vector3(0.021, 0.006, 0.01), _s(10), _r(5))
		g.reg(LIPS).ellipsoid(Vector3(0, 1.577 * hy, -0.081), Vector3(0.019, 0.006, 0.01), _s(10), _r(5))
		for sx: float in [-1.0, 1.0]:
			g.reg(SKIN).ellipsoid(Vector3(0.077 * sx, 1.645 * hy, 0.012), Vector3(0.012, 0.03, 0.019), _s(8), _r(6))
			g.reg(EYE_WHITE).ellipsoid(Vector3(0.031 * sx, 1.658 * hy, -0.079), Vector3(0.0125, 0.011, 0.01), _s(10), _r(6))
			g.reg(IRIS).ellipsoid(Vector3(0.031 * sx, 1.658 * hy, -0.0885), Vector3(0.0068, 0.0068, 0.003), _s(8), _r(4))
			g.reg(SKIN).capsule(Vector3(0.016 * sx, 1.6685 * hy, -0.089), Vector3(0.046 * sx, 1.6685 * hy, -0.083), 0.0055, 0.005, _s(6), 1)
			g.reg(BROW).capsule(Vector3(0.014 * sx, 1.678 * hy, -0.091), Vector3(0.05 * sx, 1.679 * hy, -0.083), 0.0045, 0.0035, _s(6), 1)
			g.reg(GLASSES).rbox(Vector3(0.031 * sx, 1.658 * hy, -0.094), Vector3(0.034, 0.024, 0.006), 0.006, 1)
			g.reg(GLASSES).capsule(Vector3(0.05 * sx, 1.664 * hy, -0.09), Vector3(0.079 * sx, 1.664 * hy, -0.01), 0.002, 0.002, _s(4), 1)
		g.reg(GLASSES).capsule(Vector3(-0.014, 1.662 * hy, -0.095), Vector3(0.014, 1.662 * hy, -0.095), 0.002, 0.002, _s(4), 1)
	else:
		for sx: float in [-1.0, 1.0]:
			g.reg(SKIN).ellipsoid(Vector3(0.077 * sx, 1.645 * hy, 0.012), Vector3(0.012, 0.03, 0.019), 5, 3)
			g.reg(EYE_WHITE).ellipsoid(Vector3(0.031 * sx, 1.658 * hy, -0.082), Vector3(0.012, 0.009, 0.008), 5, 3)
		g.reg(SKIN).capsule(Vector3(0, 1.656 * hy, -0.088), Vector3(0, 1.612 * hy, -0.108), 0.01, 0.014, 5, 1)
	# hair
	_hair_cap(g, Vector3(0, 1.676 * hy, 0.014), Vector3(0.0835, 0.1035, 0.1045), HAIR_SHORT, 1.0)
	_hair_cap(g, Vector3(0, 1.676 * hy, 0.014), Vector3(0.086, 0.106, 0.107), HAIR_LONG, 1.05)
	g.reg(HAIR_LONG).loft([Geo.ring(1.68 * hy, 0.084, 0.02, 0.07, _s(12), 2.2, Vector2(0, 0.05)),
		Geo.ring(1.58 * hy, 0.088, 0.02, 0.07, _s(12), 2.2, Vector2(0, 0.06)),
		Geo.ring(1.47 * hy, 0.09, 0.02, 0.055, _s(12), 2.2, Vector2(0, 0.075)),
		Geo.ring(1.4 * hy, 0.075, 0.015, 0.03, _s(12), 2.2, Vector2(0, 0.085))], true, true)
	_hair_cap(g, Vector3(0, 1.676 * hy, 0.014), Vector3(0.0845, 0.1045, 0.1055), HAIR_PONY, 1.0)
	g.reg(HAIR_PONY).capsule(Vector3(0, 1.665 * hy, 0.112), Vector3(0, 1.49 * hy, 0.14), 0.026, 0.012, _s(8), 2)
	# police cap
	g.reg(COP_HAT).lathe([Vector2(0.091, 1.7 * hy), Vector2(0.094, 1.735 * hy), Vector2(0.1, 1.775 * hy), Vector2(0.06, 1.79 * hy)], 16, true, true, 1.0, 1.08)
	g.reg(COP_BRIM).ellipsoid(Vector3(0, 1.71 * hy, -0.082), Vector3(0.072, 0.008, 0.05), _s(12), _r(4))
	g.reg(COP_BADGE).rbox(Vector3(0, 1.745 * hy, -0.1), Vector3(0.025, 0.028, 0.006), 0.004, 1)

	# ---------------- arms
	for side: float in [-1.0, 1.0]:
		var ab := B_ARM_L if side < 0 else B_ARM_R
		var fb := B_FORE_L if side < 0 else B_FORE_R
		var sx: float = pv[ab].x
		var ex: float = pv[fb].x
		var t := bulk
		g.bone = ab
		var arm := [
			_limb_ring(1.447 * s, sx - 0.016 * side, 0.0, 0.012 * t, 0.014 * t, 0.014 * t),
			_limb_ring(1.44 * s, sx - 0.01 * side, 0.0, 0.03 * t, 0.034 * t, 0.032 * t),
			_limb_ring(1.422 * s, sx - 0.003 * side, 0.0, 0.044 * t, 0.048 * t, 0.045 * t),
			_limb_ring(1.385 * s, sx + 0.003 * side, 0.0, 0.049 * t, 0.052 * t, 0.049 * t),
			_limb_ring(1.33 * s, lerpf(sx, ex, 0.3), 0.0, 0.047 * t, 0.048 * t, 0.046 * t),
			_limb_ring(1.30 * s, lerpf(sx, ex, 0.4), 0.0, 0.048 * t, 0.049 * t, 0.046 * t),
			_limb_ring(1.24 * s, lerpf(sx, ex, 0.6), 0.0, 0.045 * t, 0.047 * t, 0.042 * t),
			_limb_ring(1.17 * s, lerpf(sx, ex, 0.85), 0.0, 0.041 * t, 0.04 * t, 0.04 * t),
			_limb_ring(1.12 * s, ex, 0.0, 0.039 * t, 0.038 * t, 0.04 * t),
			_limb_ring(1.1 * s, ex, 0.0, 0.03 * t, 0.03 * t, 0.03 * t),
		]
		g.loft(arm, true, true, [SHIRT, SHIRT, SHIRT, SHIRT, SHIRT, SLEEVE_LOW, SLEEVE_LOW, SLEEVE_LOW, SLEEVE_LOW])
		g.bone = fb
		var wx := ex + 0.004 * side
		var fore := [
			_limb_ring(1.15 * s, ex, 0.0, 0.03 * t, 0.03 * t, 0.03 * t),
			_limb_ring(1.13 * s, ex, 0.0, 0.038 * t, 0.038 * t, 0.04 * t),
			_limb_ring(1.08 * s, ex, -0.002, 0.04 * t, 0.042 * t, 0.044 * t),
			_limb_ring(1.03 * s, lerpf(ex, wx, 0.4), -0.002, 0.037 * t, 0.042 * t, 0.042 * t),
			_limb_ring(0.96 * s, lerpf(ex, wx, 0.7), 0.0, 0.03 * t, 0.034 * t, 0.034 * t),
			_limb_ring(0.915 * s, wx, 0.0, 0.021, 0.027, 0.027),
			_limb_ring(0.9 * s, wx, 0.0, 0.021, 0.027, 0.027),
			_limb_ring(0.88 * s, wx, 0.0, 0.016, 0.02, 0.02),
		]
		g.loft(fore, true, true, [SLEEVE_FORE, SLEEVE_FORE, SLEEVE_FORE, SLEEVE_FORE, SLEEVE_FORE, SKIN, SKIN])
		_hand(g, Vector3(wx, 0.9 * s, 0.0), side, s)

	# ---------------- legs
	for side: float in [-1.0, 1.0]:
		var tb := B_THIGH_L if side < 0 else B_THIGH_R
		var kb := B_SHIN_L if side < 0 else B_SHIN_R
		var hx: float = pv[tb].x
		var kx: float = pv[kb].x
		var t := bulk * (1.05 if female else 1.0)
		g.bone = tb
		var thigh := [
			_limb_ring(0.985 * s, hx, 0.0, 0.05 * t, 0.05 * t, 0.05 * t),
			_limb_ring(0.955 * s, hx, 0.0, 0.082 * t, 0.085 * t, 0.085 * t),
			_limb_ring(0.89 * s, hx, -0.004, 0.088 * t, 0.09 * t, 0.088 * t),
			_limb_ring(0.80 * s, lerpf(hx, kx, 0.35), -0.006, 0.082 * t, 0.084 * t, 0.078 * t),
			_limb_ring(0.72 * s, lerpf(hx, kx, 0.55), -0.006, 0.076 * t, 0.078 * t, 0.072 * t),
			_limb_ring(0.62 * s, lerpf(hx, kx, 0.8), -0.004, 0.064 * t, 0.066 * t, 0.062 * t),
			_limb_ring(0.52 * s, kx, 0.0, 0.054 * t, 0.056 * t, 0.052 * t),
			_limb_ring(0.49 * s, kx, 0.0, 0.04 * t, 0.04 * t, 0.04 * t),
		]
		g.loft(thigh, true, true, [PANTS, PANTS, PANTS, THIGH_LOW, THIGH_LOW, THIGH_LOW, THIGH_LOW])
		g.bone = kb
		var ax := kx
		var shin := [
			_limb_ring(0.535 * s, kx, 0.0, 0.04 * t, 0.04 * t, 0.04 * t),
			_limb_ring(0.51 * s, kx, 0.0, 0.052 * t, 0.054 * t, 0.052 * t),
			_limb_ring(0.44 * s, kx, 0.004, 0.052 * t, 0.048 * t, 0.062 * t),
			_limb_ring(0.37 * s, kx, 0.008, 0.052 * t, 0.044 * t, 0.068 * t),
			_limb_ring(0.28 * s, ax, 0.004, 0.044 * t, 0.04 * t, 0.052 * t),
			_limb_ring(0.19 * s, ax, 0.0, 0.035, 0.034, 0.038),
			_limb_ring(0.15 * s, ax, 0.0, 0.032, 0.032, 0.034),
			_limb_ring(0.09, ax, 0.0, 0.032, 0.032, 0.034),
		]
		g.loft(shin, true, true, [PANTS_SHIN, PANTS_SHIN, PANTS_SHIN, PANTS_SHIN, PANTS_SHIN, SOCK, SOCK])
		_shoe(g, ax, s)
	_geo_cache[ckey] = g
	g.compute_normals()
	return g

static func _limb_ring(y: float, x: float, z: float, rx: float, rzf: float, rzb: float) -> PackedVector3Array:
	return Geo.ring(y, rx, rzf, rzb, _s(12), 2.0, Vector2(x, z))

static func _scale_ring(r: PackedVector3Array, sc: Vector3, pivot: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in r:
		var q := p
		q.x *= sc.x
		q.z = (q.z - pivot.z) * sc.z + pivot.z
		out.append(q)
	return out

## Hair shell over the skull with a natural hairline (higher at the forehead).
static func _hair_cap(g: Geo, c: Vector3, r: Vector3, region: int, back_drop: float) -> void:
	var segs := _s(13)
	var k_n := 5 if LOD == 0 else 3
	var rings := []
	for k in range(1, k_n + 1):
		var ring := PackedVector3Array()
		for i in segs:
			var a := TAU * float(i) / segs
			var f := sin(a)                       # -1 = front (-Z), +1 = back
			var tmax := lerpf(1.86, 1.25, -f) if f < 0.0 else lerpf(1.86, 2.35 * back_drop, f)
			var t := tmax * float(k) / k_n
			ring.append(c + Vector3(r.x * sin(t) * cos(a), r.y * cos(t), r.z * sin(t) * sin(a)))
		rings.append(ring)
	g.reg(region)
	g.loft(rings, false, false)
	g._fan_to(g.add_v(c + Vector3(0, r.y, 0)), rings[0], Vector3.UP)

static func _hand(g: Geo, wrist: Vector3, side: float, s: float) -> void:
	var inward := -side
	if LOD == 1:
		g.reg(SKIN).rbox(wrist + Vector3(inward * 0.004, -0.075 * s, -0.004), Vector3(0.028, 0.13, 0.075), 0.013, 0)
		g.reg(SKIN).capsule(wrist + Vector3(inward * 0.006, -0.03 * s, -0.036), wrist + Vector3(inward * 0.03, -0.09, -0.05), 0.011, 0.008, 5, 1)
		return
	g.reg(SKIN).rbox(wrist + Vector3(0, -0.05 * s, -0.002), Vector3(0.026, 0.085, 0.078), 0.012, 1)
	var lens := [0.074, 0.08, 0.076, 0.062]
	for j in 4:
		var z := -0.028 + j * 0.0188
		var a := wrist + Vector3(0, -0.09 * s, z)
		var tip := a + Vector3(inward * 0.018, -lens[j], -0.004)
		g.reg(SKIN).capsule(a, tip, 0.0088, 0.0072, 6, 1)
	var t0 := wrist + Vector3(inward * 0.006, -0.03 * s, -0.036)
	var t2 := t0 + Vector3(inward * 0.026, -0.065, -0.022)
	g.reg(SKIN).capsule(t0, t2, 0.011, 0.0082, 6, 1)

static func _shoe(g: Geo, x: float, s: float) -> void:
	var rings := []
	var prof := [[0.068, 0.02, 0.025, 0.045], [0.05, 0.04, 0.048, 0.058], [0.02, 0.045, 0.05, 0.062],
		[-0.03, 0.049, 0.044, 0.052], [-0.085, 0.051, 0.034, 0.04], [-0.135, 0.046, 0.027, 0.033], [-0.17, 0.032, 0.02, 0.028], [-0.185, 0.015, 0.012, 0.026]]
	for p in prof:
		rings.append(Geo.ring_axis(Vector3(x, p[3], p[0] * s), Vector3.BACK, p[1], p[2], _s(10)))
	g.reg(SHOES).loft(rings, true, true)
	g.reg(SOLE).rbox(Vector3(x, 0.011, -0.058 * s), Vector3(0.1, 0.022, 0.255 * s), 0.009, 1)

# ---------------------------------------------------------------- looks
const SKIN_TONES := [Color(0.96, 0.8, 0.68), Color(0.88, 0.68, 0.53), Color(0.76, 0.56, 0.42), Color(0.6, 0.42, 0.3),
	Color(0.45, 0.3, 0.21), Color(0.32, 0.21, 0.15), Color(0.93, 0.74, 0.6)]
const HAIR_COLS := [Color(0.08, 0.06, 0.05), Color(0.18, 0.11, 0.06), Color(0.35, 0.22, 0.12), Color(0.6, 0.45, 0.25),
	Color(0.85, 0.72, 0.45), Color(0.45, 0.16, 0.08), Color(0.55, 0.55, 0.55), Color(0.12, 0.1, 0.09)]
const TOPS := [Color(0.85, 0.85, 0.83), Color(0.12, 0.12, 0.14), Color(0.62, 0.12, 0.12), Color(0.15, 0.27, 0.5),
	Color(0.3, 0.45, 0.32), Color(0.75, 0.6, 0.35), Color(0.45, 0.45, 0.48), Color(0.55, 0.3, 0.5), Color(0.9, 0.55, 0.2), Color(0.28, 0.4, 0.62)]
const BOTTOMS := [Color(0.16, 0.22, 0.38), Color(0.12, 0.12, 0.13), Color(0.42, 0.37, 0.28), Color(0.25, 0.3, 0.42), Color(0.5, 0.48, 0.44), Color(0.22, 0.2, 0.18)]
const SHOE_COLS := [Color(0.08, 0.07, 0.07), Color(0.9, 0.9, 0.9), Color(0.35, 0.22, 0.12), Color(0.2, 0.25, 0.4), Color(0.5, 0.1, 0.1)]

static func random_palette(rng: RandomNumberGenerator, build: int, cop: bool) -> Dictionary:
	var female := build >= 2
	var skin: Color = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)]
	var hair: Color = HAIR_COLS[rng.randi_range(0, HAIR_COLS.size() - 1)]
	var top: Color = TOPS[rng.randi_range(0, TOPS.size() - 1)]
	var bottom: Color = BOTTOMS[rng.randi_range(0, BOTTOMS.size() - 1)]
	var shoes: Color = SHOE_COLS[rng.randi_range(0, SHOE_COLS.size() - 1)]
	var long_sleeve := rng.randf() < 0.4
	var shorts := rng.randf() < 0.22
	var p := {}
	var cloth := func(c: Color) -> Array: return [c, 0.92, 0.0, 0.0]
	p[SKIN] = [skin, 0.55, 0.0, 0.0]
	p[NOSE_TIP] = [skin.lerp(Color(0.85, 0.45, 0.4), 0.12), 0.5, 0.0, 0.0]
	p[LIPS] = [skin.lerp(Color(0.6, 0.25, 0.25), 0.35 if not female else 0.55), 0.45, 0.0, 0.0]
	p[EYE_WHITE] = [Color(0.92, 0.9, 0.86), 0.2, 0.0, 0.0]
	p[IRIS] = [[Color(0.25, 0.15, 0.08), Color(0.2, 0.35, 0.5), Color(0.3, 0.4, 0.25), Color(0.1, 0.07, 0.05)][rng.randi_range(0, 3)], 0.15, 0.0, 0.0]
	p[BROW] = [hair.darkened(0.2), 0.9, 0.0, 0.0]
	p[SHIRT] = cloth.call(top)
	p[COLLAR] = cloth.call(top.darkened(0.08))
	p[SLEEVE_LOW] = cloth.call(top) if long_sleeve else p[SKIN]
	p[SLEEVE_FORE] = cloth.call(top) if long_sleeve else p[SKIN]
	p[PANTS] = cloth.call(bottom)
	p[THIGH_LOW] = p[SKIN] if shorts else cloth.call(bottom)
	p[PANTS_SHIN] = p[SKIN] if shorts else cloth.call(bottom)
	p[SOCK] = cloth.call(Color(0.92, 0.92, 0.9)) if shorts else cloth.call(bottom)
	p[SHOES] = [shoes, 0.5, 0.0, 0.0]
	p[SOLE] = [Color(0.9, 0.88, 0.84) if shoes.v < 0.5 else Color(0.15, 0.15, 0.15), 0.8, 0.0, 0.0]
	p[BELT] = cloth.call(bottom) if rng.randf() < 0.4 else [Color(0.12, 0.08, 0.05), 0.5, 0.0, 0.0]
	p[BUCKLE] = [Color(0.75, 0.7, 0.55), 0.3, 1.0, 0.0] if p[BELT][0] != bottom else null
	p[PRINT] = cloth.call(TOPS[rng.randi_range(0, TOPS.size() - 1)]) if rng.randf() < 0.3 and not cop else null
	p[POCKET] = cloth.call(top.darkened(0.06)) if (cop or rng.randf() < 0.2) else null
	# hair style
	var style := rng.randi_range(0, 9)
	p[HAIR_SHORT] = null
	p[HAIR_LONG] = null
	p[HAIR_PONY] = null
	var hair_m := [hair, 0.75, 0.0, 0.0]
	if female:
		if style < 5:
			p[HAIR_LONG] = hair_m
		elif style < 8:
			p[HAIR_PONY] = hair_m
		else:
			p[HAIR_SHORT] = hair_m
	elif style < 7:
		p[HAIR_SHORT] = hair_m
	elif style < 8:
		p[HAIR_LONG] = hair_m
	p[BEARD] = [hair.darkened(0.1), 0.9, 0.0, 0.0] if (not female and rng.randf() < 0.3) else null
	p[GLASSES] = [Color(0.04, 0.04, 0.05), 0.1, 0.3, 0.0] if rng.randf() < 0.15 else null
	p[COP_BADGE] = null
	p[COP_HAT] = null
	p[COP_BRIM] = null
	p[COP_GEAR] = null
	if cop:
		var navy := Color(0.1, 0.14, 0.28)
		p[SHIRT] = cloth.call(navy)
		p[COLLAR] = cloth.call(navy.darkened(0.1))
		p[POCKET] = cloth.call(navy.darkened(0.08))
		p[SLEEVE_LOW] = cloth.call(navy) if long_sleeve else p[SKIN]
		p[SLEEVE_FORE] = cloth.call(navy) if long_sleeve else p[SKIN]
		var dark := Color(0.07, 0.08, 0.12)
		p[PANTS] = cloth.call(dark)
		p[THIGH_LOW] = cloth.call(dark)
		p[PANTS_SHIN] = cloth.call(dark)
		p[SOCK] = cloth.call(dark)
		p[SHOES] = [Color(0.04, 0.04, 0.04), 0.3, 0.0, 0.0]
		p[SOLE] = [Color(0.05, 0.05, 0.05), 0.8, 0.0, 0.0]
		p[BELT] = [Color(0.04, 0.04, 0.04), 0.4, 0.0, 0.0]
		p[BUCKLE] = [Color(0.8, 0.8, 0.82), 0.3, 1.0, 0.0]
		p[COP_BADGE] = [Color(0.95, 0.78, 0.3), 0.25, 1.0, 0.0]
		p[COP_HAT] = [navy.darkened(0.3), 0.85, 0.0, 0.0]
		p[COP_BRIM] = [Color(0.03, 0.03, 0.03), 0.2, 0.0, 0.0]
		p[COP_GEAR] = [Color(0.05, 0.05, 0.05), 0.45, 0.0, 0.0]
		p[PRINT] = null
		if p[HAIR_LONG] != null:
			p[HAIR_LONG] = null
			p[HAIR_PONY] = hair_m
	return p

## Builds the skinned mesh, the skeleton description and the skin for a look.
static func make_look(build: int, palette: Dictionary) -> Dictionary:
	LOD = 1
	var mesh_far := geometry(build).mesh(palette, true)
	LOD = 0
	var g := geometry(build)
	var female := build >= 2
	var mesh := g.mesh(palette, true)
	var pv := pivots(female)
	var skin := Skin.new()
	for b in BONES.size():
		skin.add_bind(b, Transform3D(Basis(), -pv[b]))
	return {"mesh": mesh, "mesh_far": mesh_far, "skin": skin, "female": female, "build": build, "palette": palette}

## Creates a Skeleton3D with the body's bones in rest pose.
static func make_skeleton(female: bool) -> Skeleton3D:
	var sk := Skeleton3D.new()
	var pv := pivots(female)
	for b in BONES.size():
		sk.add_bone(BONES[b])
	for b in BONES.size():
		sk.set_bone_parent(b, PARENT[b])
		var parent_pos: Vector3 = pv[PARENT[b]] if PARENT[b] >= 0 else Vector3.ZERO
		var rest := Transform3D(Basis(), pv[b] - parent_pos)
		sk.set_bone_rest(b, rest)
		sk.set_bone_pose_position(b, rest.origin)
		sk.set_bone_pose_rotation(b, Quaternion.IDENTITY)
	return sk
