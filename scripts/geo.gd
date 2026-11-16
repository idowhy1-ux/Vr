class_name Geo
extends RefCounted
## Procedural geometry builder. Produces smooth, rounded meshes (lofts, lathes,
## rounded boxes, ellipsoids, tapered capsules) with per-vertex material
## (colour, roughness, metalness, emission) or a "region" id that is coloured
## later from a palette, and an optional bone id for rigid skinning.
## Front faces use Godot's clockwise winding; normals are welded per smooth group.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()        # linear rgb, a = emission strength
var mats := PackedVector2Array()      # x = roughness, y = metallic
var regions := PackedInt32Array()     # -1 = use own colour
var bones := PackedInt32Array()
var groups := PackedInt32Array()
var idx := PackedInt32Array()

var xf := Transform3D.IDENTITY        # applied to every point added
var color := Color(0.8, 0.8, 0.8)
var rough := 0.8
var metal := 0.0
var emit := 0.0
var region := -1
var bone := 0
var group := 0
var _normals_done := false

# ---------------------------------------------------------------- state
func mat(c: Color, r: float = 0.8, m: float = 0.0, e: float = 0.0) -> Geo:
	color = c
	rough = r
	metal = m
	emit = e
	region = -1
	return self

func reg(r: int) -> Geo:
	region = r
	return self

func new_group() -> int:
	group += 1
	return group

func add_v(p: Vector3) -> int:
	verts.append(xf * p)
	var lc := color.srgb_to_linear()
	cols.append(Color(lc.r, lc.g, lc.b, emit))
	mats.append(Vector2(rough, metal))
	regions.append(region)
	bones.append(bone)
	groups.append(group)
	_normals_done = false
	return verts.size() - 1

## Triangle oriented so that it faces `outward` (world space direction).
func tri_out(a: int, b: int, c: int, outward: Vector3) -> void:
	var n := (verts[c] - verts[a]).cross(verts[b] - verts[a])
	if n.dot(outward) < 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])

# ---------------------------------------------------------------- primitives
## Loft through rings of equal vertex count (closed loops). `ring_regions`
## (optional) gives a region per segment; a change duplicates the ring so the
## colour boundary is sharp while normals stay smooth.
func loft(rings: Array, cap_start: bool = true, cap_end: bool = true, seg_regions: Array = [], seg_mats: Array = [], center_pull: float = 0.0) -> void:
	new_group()
	var n: int = (rings[0] as PackedVector3Array).size()
	var centers: Array[Vector3] = []
	for r in rings:
		var c := Vector3.ZERO
		for p in r:
			c += p
		centers.append(c / n)
	var prev_row := PackedInt32Array()
	var prev_key = null
	for i in rings.size() - 1:
		var key = null
		if i < seg_regions.size():
			key = seg_regions[i]
			region = seg_regions[i]
		if i < seg_mats.size():
			var m: Array = seg_mats[i]
			mat(m[0], m[1], m[2], m[3] if m.size() > 3 else 0.0)
			key = m
			if i < seg_regions.size():
				region = seg_regions[i]
		var row_a: PackedInt32Array
		if i == 0 or key != prev_key:
			row_a = _row(rings[i])
		else:
			row_a = prev_row
		var row_b := _row(rings[i + 1])
		var axis_c: Vector3 = (centers[i] + centers[i + 1]) * 0.5
		for k in n:
			var k2 := (k + 1) % n
			var q := (verts[row_a[k]] + verts[row_a[k2]] + verts[row_b[k]] + verts[row_b[k2]]) * 0.25
			var out := q - xf * axis_c
			tri_out(row_a[k], row_b[k], row_b[k2], out)
			tri_out(row_a[k], row_b[k2], row_a[k2], out)
		prev_row = row_b
		prev_key = key
		if i == 0 and cap_start:
			_cap(row_a, centers[0], centers[0] - centers[1])
	if cap_end:
		var last := rings.size() - 1
		_cap(prev_row, centers[last], centers[last] - centers[last - 1])

## Loft with a material per quad: mat_fn.call(i, k) returns [Color, rough,
## metal, emit] or null (quad skipped). i = segment between ring i and i+1,
## k = quad index around the ring. Vertices are duplicated only where the
## material changes, so boundaries are sharp but shading stays smooth.
func loft_q(rings: Array, mat_fn: Callable, cap_start = null, cap_end = null) -> void:
	new_group()
	var n: int = (rings[0] as PackedVector3Array).size()
	var centers: Array[Vector3] = []
	for r in rings:
		var c := Vector3.ZERO
		for p in r:
			c += p
		centers.append(c / n)
	var cache := {}
	var get_v := func(i: int, k: int, m) -> int:
		var key := [i, k, m]
		if cache.has(key):
			return cache[key]
		if m is int:
			region = m
		else:
			mat(m[0], m[1], m[2], m[3] if m.size() > 3 else 0.0)
		var id := add_v((rings[i] as PackedVector3Array)[k])
		cache[key] = id
		return id
	for i in rings.size() - 1:
		for k in n:
			var m = mat_fn.call(i, k)
			if m == null:
				continue
			var k2 := (k + 1) % n
			var a: int = get_v.call(i, k, m)
			var b: int = get_v.call(i + 1, k, m)
			var c: int = get_v.call(i + 1, k2, m)
			var d: int = get_v.call(i, k2, m)
			var q := (verts[a] + verts[b] + verts[c] + verts[d]) * 0.25
			var out := q - xf * ((centers[i] + centers[i + 1]) * 0.5)
			tri_out(a, b, c, out)
			tri_out(a, c, d, out)
	if cap_start != null:
		var m = cap_start
		var row := PackedInt32Array()
		for k in n:
			row.append(get_v.call(0, k, m))
		_cap(row, centers[0], centers[0] - centers[1])
	if cap_end != null:
		var m = cap_end
		var last := rings.size() - 1
		var row := PackedInt32Array()
		for k in n:
			row.append(get_v.call(last, k, m))
		_cap(row, centers[last], centers[last] - centers[last - 1])

## Rounded-rectangle ring in the XY plane at depth z (superellipse).
static func ring_xy(z: float, yc: float, hw: float, hh: float, segs: int = 20, ex: float = 4.0, top_w: float = -1.0) -> PackedVector3Array:
	var r := PackedVector3Array()
	for k in segs:
		var a := TAU * float(k) / segs
		var c := cos(a)
		var s := sin(a)
		var x := signf(c) * pow(absf(c), 2.0 / ex)
		var y := signf(s) * pow(absf(s), 2.0 / ex)
		var w := hw
		if top_w > 0.0:
			w = lerpf(hw, top_w, clampf((y + 1.0) * 0.5, 0.0, 1.0))
		r.append(Vector3(x * w, yc + y * hh, z))
	return r

func _row(ring: PackedVector3Array) -> PackedInt32Array:
	var row := PackedInt32Array()
	for p in ring:
		row.append(add_v(p))
	return row

func _cap(row: PackedInt32Array, center: Vector3, dir: Vector3) -> void:
	var c := add_v(center)
	var out := xf.basis * dir
	for k in row.size():
		tri_out(c, row[k], row[(k + 1) % row.size()], out)

## Ring around the local Y axis at height y: superellipse with separate
## front (-Z) and back (+Z) depth, offset in x/z. exp 2 = ellipse, >2 = boxier.
static func ring(y: float, rx: float, rz_front: float, rz_back: float, segs: int = 12, ex: float = 2.0, off := Vector2.ZERO) -> PackedVector3Array:
	var r := PackedVector3Array()
	for k in segs:
		var a := TAU * float(k) / segs
		var c := cos(a)
		var s := sin(a)
		var x := signf(c) * pow(absf(c), 2.0 / ex) * rx
		var zr := rz_front if s < 0.0 else rz_back
		var z := signf(s) * pow(absf(s), 2.0 / ex) * zr
		r.append(Vector3(x + off.x, y, z + off.y))
	return r

## Ring perpendicular to an arbitrary axis.
static func ring_axis(center: Vector3, axis: Vector3, radius_a: float, radius_b: float, segs: int = 10) -> PackedVector3Array:
	var ax := axis.normalized()
	var ref := Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := ax.cross(ref).normalized()
	var v := ax.cross(u).normalized()
	var r := PackedVector3Array()
	for k in segs:
		var a := TAU * float(k) / segs
		r.append(center + u * cos(a) * radius_a + v * sin(a) * radius_b)
	return r

## Surface of revolution around local Y. profile = [Vector2(radius, y), ...]
func lathe(profile: Array, segs: int = 12, cap_start: bool = true, cap_end: bool = true, sx: float = 1.0, sz: float = 1.0) -> void:
	var rings := []
	for p in profile:
		rings.append(ring(p.y, p.x * sx, p.x * sz, p.x * sz, segs))
	loft(rings, cap_start, cap_end)

## Tapered capsule from a (radius ra) to b (radius rb), rounded ends.
func capsule(a: Vector3, b: Vector3, ra: float, rb: float, segs: int = 10, end_rings: int = 3, flat_a: float = 1.0, flat_b: float = 1.0) -> void:
	var ax := b - a
	var rings := []
	for i in range(end_rings, 0, -1):
		var t := float(i) / end_rings * PI * 0.5
		rings.append(ring_axis(a - ax.normalized() * sin(t) * ra * flat_a, ax, ra * cos(t), ra * cos(t), segs))
	rings.append(ring_axis(a, ax, ra, ra, segs))
	rings.append(ring_axis(b, ax, rb, rb, segs))
	for i in range(1, end_rings + 1):
		var t := float(i) / end_rings * PI * 0.5
		rings.append(ring_axis(b + ax.normalized() * sin(t) * rb * flat_b, ax, rb * cos(t), rb * cos(t), segs))
	# close the tips with tiny rings -> cap
	loft(rings, true, true)

func ellipsoid(c: Vector3, r: Vector3, segs: int = 12, rings_n: int = 8) -> void:
	var rings := []
	for i in range(1, rings_n):
		var t := PI * float(i) / rings_n
		var y := -cos(t) * r.y
		var s := sin(t)
		rings.append(ring(y, r.x * s, r.z * s, r.z * s, segs, 2.0))
	for k in rings.size():
		var rr: PackedVector3Array = rings[k]
		for j in rr.size():
			rr[j] += c
		rings[k] = rr
	loft(rings, false, false)
	# poles (same smooth group as the loft, so normals weld across)
	_fan_to(add_v(c + Vector3(0, -r.y, 0)), rings[0], Vector3.DOWN)
	_fan_to(add_v(c + Vector3(0, r.y, 0)), rings[rings.size() - 1], Vector3.UP)

func _fan_to(pole: int, ring_pts: PackedVector3Array, dir: Vector3) -> void:
	var row := PackedInt32Array()
	for p in ring_pts:
		row.append(add_v(p))
	var out := xf.basis * dir
	for k in row.size():
		tri_out(pole, row[k], row[(k + 1) % row.size()], out)

## Rounded box (all edges rounded with radius rad). Smooth everywhere.
func rbox(c: Vector3, size: Vector3, rad: float, sub: int = 3) -> void:
	new_group()
	var h := size * 0.5
	rad = minf(rad, minf(h.x, minf(h.y, h.z)) * 0.999)
	var inner := h - Vector3(rad, rad, rad)
	var n := sub * 2 + 1
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var grid := PackedInt32Array()
		for i in n + 1:
			for j in n + 1:
				var a := float(i) / n * 2.0 - 1.0
				var b := float(j) / n * 2.0 - 1.0
				# denser near edges for nice rounding
				a = signf(a) * pow(absf(a), 0.6)
				b = signf(b) * pow(absf(b), 0.6)
				var p := nrm + u * a + v * b
				var q := p * h
				var clamped := Vector3(clampf(q.x, -inner.x, inner.x), clampf(q.y, -inner.y, inner.y), clampf(q.z, -inner.z, inner.z))
				var d := q - clamped
				var pos := clamped + (d.normalized() * rad if d.length() > 0.00001 else nrm * rad)
				grid.append(add_v(c + pos))
		for i in n:
			for j in n:
				var i0 := grid[i * (n + 1) + j]
				var i1 := grid[(i + 1) * (n + 1) + j]
				var i2 := grid[(i + 1) * (n + 1) + j + 1]
				var i3 := grid[i * (n + 1) + j + 1]
				var out := xf.basis * nrm
				tri_out(i0, i1, i2, out)
				tri_out(i0, i2, i3, out)

## Flat (faceted) box, for hard-edged parts.
func box(c: Vector3, size: Vector3) -> void:
	rbox(c, size, 0.0005, 0)

## Quad facing `out`.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	new_group()
	var i0 := add_v(a)
	var i1 := add_v(b)
	var i2 := add_v(c)
	var i3 := add_v(d)
	var o := xf.basis * out
	tri_out(i0, i1, i2, o)
	tri_out(i0, i2, i3, o)

## Flip all triangles (for inward-facing shells).
func flip_from(start_index: int) -> void:
	var i := start_index
	while i + 2 < idx.size():
		var t := idx[i + 1]
		idx[i + 1] = idx[i + 2]
		idx[i + 2] = t
		i += 3

## Append another Geo (transformed by t).
func append(g: Geo, t: Transform3D = Transform3D.IDENTITY) -> void:
	g.compute_normals()
	compute_normals()
	var base := verts.size()
	for i in g.verts.size():
		verts.append(t * g.verts[i])
		norms.append((t.basis * g.norms[i]).normalized())
		cols.append(g.cols[i])
		mats.append(g.mats[i])
		regions.append(g.regions[i])
		bones.append(g.bones[i])
		groups.append(g.groups[i] + 100000)
	for i in g.idx:
		idx.append(base + i)

# ---------------------------------------------------------------- output
func compute_normals() -> void:
	if _normals_done and norms.size() == verts.size():
		return
	var acc := {}
	var face := PackedVector3Array()
	face.resize(verts.size())
	var i := 0
	while i + 2 < idx.size():
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var n := (verts[c] - verts[a]).cross(verts[b] - verts[a])   # outward for CW
		face[a] += n
		face[b] += n
		face[c] += n
		i += 3
	# weld by position + smooth group
	for v in verts.size():
		var key := Vector4i(roundi(verts[v].x * 2000.0), roundi(verts[v].y * 2000.0), roundi(verts[v].z * 2000.0), groups[v])
		acc[key] = acc.get(key, Vector3.ZERO) + face[v]
	norms.resize(verts.size())
	for v in verts.size():
		var key := Vector4i(roundi(verts[v].x * 2000.0), roundi(verts[v].y * 2000.0), roundi(verts[v].z * 2000.0), groups[v])
		var n: Vector3 = acc[key]
		norms[v] = n.normalized() if n.length() > 0.0000001 else Vector3.UP
	_normals_done = true

## palette: region id -> [Color, rough, metal, emit]. Regions mapped to null
## are dropped (their triangles removed).
func arrays(palette: Dictionary = {}, skinned: bool = false, only_bone: int = -1, to_local: Transform3D = Transform3D.IDENTITY, flip: bool = false) -> Array:
	compute_normals()
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_m := PackedVector2Array()
	var out_b := PackedInt32Array()
	var out_w := PackedFloat32Array()
	var out_i := PackedInt32Array()
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var keep := PackedByteArray()
	keep.resize(verts.size())
	for v in verts.size():
		var ok := only_bone < 0 or bones[v] == only_bone
		if ok and regions[v] >= 0 and palette.has(regions[v]) and palette[regions[v]] == null:
			ok = false
		keep[v] = 1 if ok else 0
	var i := 0
	while i + 2 < idx.size():
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		i += 3
		if keep[a] == 0 or keep[b] == 0 or keep[c] == 0:
			continue
		for v in ([a, c, b] if flip else [a, b, c]):
			if remap[v] < 0:
				remap[v] = out_v.size()
				out_v.append(to_local * verts[v])
				out_n.append((to_local.basis * norms[v]).normalized() * (-1.0 if flip else 1.0))
				var col := cols[v]
				var m := mats[v]
				if regions[v] >= 0 and palette.has(regions[v]):
					var p: Array = palette[regions[v]]
					var lc: Color = (p[0] as Color).srgb_to_linear()
					col = Color(lc.r, lc.g, lc.b, p[3] if p.size() > 3 else 0.0)
					m = Vector2(p[1], p[2])
				out_c.append(col)
				out_m.append(m)
				if skinned:
					out_b.append_array([bones[v], 0, 0, 0])
					out_w.append_array([1.0, 0.0, 0.0, 0.0])
			out_i.append(remap[v])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out_v
	arr[Mesh.ARRAY_NORMAL] = out_n
	arr[Mesh.ARRAY_COLOR] = out_c
	arr[Mesh.ARRAY_TEX_UV2] = out_m
	arr[Mesh.ARRAY_INDEX] = out_i
	if skinned:
		arr[Mesh.ARRAY_BONES] = out_b
		arr[Mesh.ARRAY_WEIGHTS] = out_w
	return arr

func mesh(palette: Dictionary = {}, skinned: bool = false, only_bone: int = -1, to_local: Transform3D = Transform3D.IDENTITY, flip: bool = false) -> ArrayMesh:
	var am := ArrayMesh.new()
	var arr := arrays(palette, skinned, only_bone, to_local, flip)
	if (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return am
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

static func mesh_from_arrays(arr: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	if not (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
