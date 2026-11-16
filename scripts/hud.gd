class_name Hud
extends Node3D
## Wrist HUD (on the left hand) + floating messages in front of the camera.

var hp_bar: MeshInstance3D
var hp_bg: MeshInstance3D
var stars: Label3D
var info: Label3D
var msg: Label3D
var msg_t := 0.0
var player: Player
var hp_mat: StandardMaterial3D

func setup(p: Player) -> void:
	player = p
	# wrist panel
	# a watch-style display on the back of the left wrist (grip-pose space:
	# back of the left hand faces -X, fingers towards -Y, thumb towards -Z)
	var panel := Node3D.new()
	var k := sqrt(0.5)
	panel.transform = Transform3D(Basis(Vector3(0, -k, -k), Vector3(0, -k, k), Vector3(-1, 0, 0)), Vector3(-0.072, 0.083, 0.075))
	p.left.add_child(panel)
	var bg := MeshLib.inst(MeshLib.box(Vector3(0.12, 0.075, 0.004)), MeshLib.mat_alpha(Color(0.05, 0.05, 0.08, 0.75)), Vector3(0, 0, -0.002), Vector3.ZERO, panel)
	hp_bg = MeshLib.inst(MeshLib.box(Vector3(0.1, 0.012, 0.004)), MeshLib.mat(Color(0.2, 0.05, 0.05), 1.0), Vector3(0, 0.022, 0.001), Vector3.ZERO, panel)
	hp_mat = StandardMaterial3D.new()
	hp_mat.albedo_color = Color(0.2, 0.9, 0.3)
	hp_mat.emission_enabled = true
	hp_mat.emission = Color(0.1, 0.6, 0.2)
	hp_bar = MeshLib.inst(MeshLib.box(Vector3(1.0, 0.012, 0.004)), hp_mat, Vector3(0, 0.022, 0.003), Vector3.ZERO, panel)
	stars = _label(panel, Vector3(0, 0.004, 0.003), 44, Color(1.0, 0.85, 0.2))
	info = _label(panel, Vector3(0, -0.02, 0.003), 26, Color(0.9, 0.9, 0.95))
	# message label floating in front of the camera
	msg = Label3D.new()
	msg.font_size = 64
	msg.pixel_size = 0.0007
	msg.outline_size = 12
	msg.modulate = Color(1, 0.95, 0.8)
	msg.no_depth_test = true
	msg.render_priority = 50
	msg.position = Vector3(0, -0.22, -1.6)
	msg.visible = false
	p.camera.add_child(msg)
	Game.message.connect(show_message)
	Game.wanted_changed.connect(_on_wanted)
	show_message("STEAL CARS. FIGHT COPS. USE YOUR POWERS.")

func _label(parent: Node, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = 0.00035
	l.outline_size = 6
	l.modulate = color
	l.position = pos
	l.no_depth_test = true
	l.render_priority = 40
	parent.add_child(l)
	return l

func show_message(text: String) -> void:
	msg.text = text
	msg.visible = true
	msg.modulate.a = 1.0
	msg_t = 3.2

func _on_wanted(s: int) -> void:
	if s > 0:
		show_message("WANTED LEVEL %d" % s)

func _process(delta: float) -> void:
	if player == null:
		return
	var h := clampf(player.health / 100.0, 0.0, 1.0)
	hp_bar.scale.x = maxf(h * 0.1, 0.001)
	hp_bar.position.x = -0.05 + h * 0.05
	hp_mat.albedo_color = Color(0.2, 0.9, 0.3).lerp(Color(0.9, 0.1, 0.1), 1.0 - h)
	hp_mat.emission = Color(0.1, 0.6, 0.2).lerp(Color(0.6, 0.05, 0.05), 1.0 - h)
	var st := ""
	for i in 5:
		st += "*" if i < Game.wanted_stars else "-"
	stars.text = st
	var l: String = player.left.held.label() if player.left.held is Weapon else "-"
	var r: String = player.right.held.label() if player.right.held is Weapon else "-"
	var bt := "READY" if player.bullet_cd <= 0.0 else "%ds" % int(ceil(player.bullet_cd))
	info.text = "L:%s  R:%s\nSCORE %d   SLOWMO %s" % [l, r, Game.score, bt]
	if msg_t > 0.0:
		msg_t -= delta / maxf(Engine.time_scale, 0.05)
		if msg_t < 0.8:
			msg.modulate.a = msg_t / 0.8
		if msg_t <= 0.0:
			msg.visible = false
