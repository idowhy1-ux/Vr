extends Node3D
## Model viewer for checking procedural models in screenshots.
## godot --path . res://tools/viewer.tscn -- --shot=/path/out.png --what=people

var what := "people"
var shot := "/tmp/viewer.png"
var frame := 0
var cam: Camera3D
var targets: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--what="):
			what = a.substr(7)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 155, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = MeshLib.mat(Color(0.5, 0.5, 0.5), 0.9)
	add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	match what:
		"people":
			for i in 8:
				var build := i % 4
				var pal := BodyGen.random_palette(rng, build, i >= 6)
				var look := BodyGen.make_look(build, pal)
				var sk := BodyGen.make_skeleton(look["female"])
				sk.position = Vector3(-3.5 + i * 1.0, 0, 0)
				add_child(sk)
				var mi := MeshInstance3D.new()
				mi.mesh = look["mesh"]
				mi.skin = look["skin"]
				mi.material_override = MeshLib.atlas()
				sk.add_child(mi)
				mi.skeleton = mi.get_path_to(sk)
				if i == 1:
					sk.set_bone_pose_rotation(BodyGen.B_ARM_R, Quaternion(Vector3.RIGHT, -1.4))
					sk.set_bone_pose_rotation(BodyGen.B_FORE_R, Quaternion(Vector3.RIGHT, 0.8))
					sk.set_bone_pose_rotation(BodyGen.B_THIGH_L, Quaternion(Vector3.RIGHT, 0.6))
					sk.set_bone_pose_rotation(BodyGen.B_SHIN_L, Quaternion(Vector3.RIGHT, -0.9))
			cam.position = Vector3(0, 1.3, -7.5)
			cam.look_at(Vector3(0, 0.95, 0))
		"faces":
			for i in 4:
				var build: int = [0, 2, 1, 3][i]
				var pal := BodyGen.random_palette(rng, build, i == 3)
				var look := BodyGen.make_look(build, pal)
				var sk := BodyGen.make_skeleton(look["female"])
				sk.position = Vector3(-0.6 + i * 0.4, 0, 0)
				add_child(sk)
				var mi := MeshInstance3D.new()
				mi.mesh = look["mesh"]
				mi.skin = look["skin"]
				mi.material_override = MeshLib.atlas()
				sk.add_child(mi)
				mi.skeleton = mi.get_path_to(sk)
			cam.position = Vector3(0.0, 1.64, -1.7)
			cam.look_at(Vector3(0, 1.6, 0))
		_:
			if has_method("_build_" + what):
				call("_build_" + what)
	var t0 := Time.get_ticks_msec()
	print("[viewer] built in %d ms" % (Time.get_ticks_msec() - t0))

func _process(_d: float) -> void:
	frame += 1
	if frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("[viewer] saved ", shot, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		get_tree().quit()

func _build_weapons() -> void:
	var types := ["bat", "baton", "knife", "machete", "axe", "pistol", "shotgun", "smg"]
	for i in types.size():
		var mi := MeshInstance3D.new()
		mi.mesh = Weapon.visual_mesh(types[i])
		mi.material_override = MeshLib.atlas()
		mi.position = Vector3(0.05 + (i % 2) * 0.95, 0.75 + (i / 2) * 0.22, 0)
		mi.rotation_degrees = Vector3(0, -90, 0)
		add_child(mi)
	cam.position = Vector3(0.45, 1.08, -2.2)
	cam.look_at(Vector3(0.45, 1.06, 0))

func _build_cars() -> void:
	var types := ["sedan", "hatch", "suv", "van", "police", "taxi"]
	var cols := [Color(0.7, 0.08, 0.08), Color(0.1, 0.25, 0.6), Color(0.85, 0.85, 0.87), Color(0.15, 0.15, 0.17), Color.WHITE, Color.WHITE]
	for i in types.size():
		var m := CarGen.meshes(types[i], cols[i])
		var root := Node3D.new()
		root.position = Vector3(-6.5 + i * 2.6, 0, (i % 2) * 2.5)
		root.rotation_degrees = Vector3(0, -30, 0)
		add_child(root)
		for k in ["body", "interior", "tail"]:
			var mi := MeshInstance3D.new()
			mi.mesh = m[k]
			mi.material_override = MeshLib.atlas()
			root.add_child(mi)
		var d := CarGen.dims(types[i])
		for p in [Vector3(-(d["hw"] - 0.11), d["wr"], -d["wb"] * 0.5), Vector3(d["hw"] - 0.11, d["wr"], -d["wb"] * 0.5), Vector3(-(d["hw"] - 0.11), d["wr"], d["wb"] * 0.5), Vector3(d["hw"] - 0.11, d["wr"], d["wb"] * 0.5)]:
			var w := MeshInstance3D.new()
			w.mesh = m["wheel"]
			w.material_override = MeshLib.atlas()
			w.position = p
			root.add_child(w)
	cam.position = Vector3(1.0, 3.2, -9.5)
	cam.look_at(Vector3(-0.5, 0.6, 1.0))
	cam.fov = 55

func _build_car1() -> void:
	var types := ["sedan", "police"]
	for i in 2:
		var m := CarGen.meshes(types[i], Color(0.7, 0.08, 0.08))
		var root := Node3D.new()
		root.position = Vector3(-2.6 + i * 5.2, 0, 0)
		root.rotation_degrees = Vector3(0, 90 if i == 0 else 150, 0)
		add_child(root)
		for k in ["body", "interior", "tail"]:
			var mi := MeshInstance3D.new()
			mi.mesh = m[k]
			mi.material_override = MeshLib.atlas()
			root.add_child(mi)
		var d := CarGen.dims(types[i])
		for p in [Vector3(-(d["hw"] - 0.11), d["wr"], -d["wb"] * 0.5), Vector3(d["hw"] - 0.11, d["wr"], -d["wb"] * 0.5), Vector3(-(d["hw"] - 0.11), d["wr"], d["wb"] * 0.5), Vector3(d["hw"] - 0.11, d["wr"], d["wb"] * 0.5)]:
			var w := MeshInstance3D.new()
			w.mesh = m["wheel"]
			w.material_override = MeshLib.atlas()
			w.position = p
			root.add_child(w)
	cam.position = Vector3(0.0, 1.4, -8.5)
	cam.look_at(Vector3(0.0, 0.7, 0))
	cam.fov = 50

func _build_hands() -> void:
	for i in 4:
		var side := "right" if i % 2 == 0 else "left"
		var hg := Hand._hand_geo(1.0 if side == "right" else -1.0)
		var sk := Skeleton3D.new()
		var pos: Array[Vector3] = hg["pos"]
		var parent: Array[int] = hg["parent"]
		for b in pos.size():
			sk.add_bone("b%d" % b)
		for b in pos.size():
			sk.set_bone_parent(b, parent[b])
			var pp: Vector3 = pos[parent[b]] if parent[b] >= 0 else Vector3.ZERO
			sk.set_bone_rest(b, Transform3D(Basis(), pos[b] - pp))
		sk.reset_bone_poses()
		sk.position = Vector3(-0.3 + i * 0.2, 1.2, 0)
		sk.rotation_degrees = Vector3(0, -90 if side == "right" else 90, 0)
		add_child(sk)
		var mi := MeshInstance3D.new()
		mi.mesh = hg["mesh"]
		mi.skin = hg["skin"]
		mi.material_override = MeshLib.atlas()
		sk.add_child(mi)
		mi.skeleton = mi.get_path_to(sk)
		if i >= 2:
			var s := 1.0 if side == "right" else -1.0
			for b in range(1, 13):
				sk.set_bone_pose_rotation(b, Quaternion(Vector3.UP, [1.35, 1.6, 1.0][(b - 1) % 3] * s))
	cam.position = Vector3(0.0, 1.25, -0.75)
	cam.look_at(Vector3(0.0, 1.2, 0))

func _tri(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		t += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return t

func _build_stats() -> void:
	var r := {}
	r["lamp"] = _tri(City._lamp_mesh())
	for v in 3:
		r["tree%d" % v] = _tri(City._tree_mesh(v))
	r["traffic_light"] = _tri(City._traffic_light_mesh())
	r["hydrant"] = _tri(City._hydrant_mesh())
	r["bin"] = _tri(City._bin_mesh())
	r["bench"] = _tri(City._bench_mesh())
	var cm := CarGen.meshes("sedan", Color.RED)
	r["car_body"] = _tri(cm["body"])
	r["car_interior"] = _tri(cm["interior"])
	r["wheel"] = _tri(cm["wheel"])
	var lk := BodyGen.make_look(0, BodyGen.random_palette(RandomNumberGenerator.new(), 0, false))
	r["person"] = _tri(lk["mesh"])
	r["person_far"] = _tri(lk["mesh_far"])
	r["seated_cop"] = r["person"]
	for t in ["pistol", "shotgun", "bat"]:
		r["weapon_" + t] = _tri(Weapon.visual_mesh(t))
	print("[stats] ", r)
