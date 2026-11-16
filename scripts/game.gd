extends Node
## Global game state (autoload "Game"): collision layers, tuning, wanted level,
## shared references and small helpers used by every other script.

# ---- Collision layers (bit indices, 1-based like the editor) ----
const L_WORLD := 1
const L_PLAYER := 2
const L_NPC := 3
const L_RAGDOLL := 4
const L_CAR := 5
const L_PROP := 6
const L_SENSOR := 7

static func bit(layer: int) -> int:
	return 1 << (layer - 1)

static func mask(layers: Array) -> int:
	var m := 0
	for l in layers:
		m |= 1 << (l - 1)
	return m

# ---- Performance budget (tuned for Quest 3 @ 90 Hz) ----
const MAX_PEDS := 18
const MAX_COPS_BASE := 2
const MAX_CARS := 9
const MAX_RAGDOLLS := 8
const MAX_DECALS := 220
const SPAWN_RADIUS := 65.0
const DESPAWN_RADIUS := 115.0
const ANIM_RANGE := 45.0

# ---- Runtime references ----
var main: Main
var player: Player
var city: City
var gore: Gore
var sfx: Sfx
var desktop_mode := false
var base_physics_rate := 90
var autotest := false
var screenshot := false
var shadows := true

# ---- Wanted level ----
var wanted := 0.0
var wanted_stars := 0
var heat_timer := 0.0
var kills := 0
var score := 0

signal wanted_changed(stars: int)
signal message(text: String)

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args() or "--autotest" in OS.get_cmdline_args()

func _process(delta: float) -> void:
	# Wanted level decays while no cop has seen the player for a while.
	if wanted > 0.0:
		heat_timer += delta
		if heat_timer > 18.0:
			wanted = maxf(0.0, wanted - delta * 0.09)
			_update_stars()

func add_wanted(amount: float, why: String = "") -> void:
	wanted = clampf(wanted + amount, 0.0, 5.0)
	heat_timer = 0.0
	_update_stars()
	if why != "":
		show_message(why)

func cop_saw_player() -> void:
	heat_timer = 0.0

func _update_stars() -> void:
	var s := int(floor(wanted + 0.001))
	if s != wanted_stars:
		wanted_stars = s
		wanted_changed.emit(s)

func show_message(text: String) -> void:
	message.emit(text)

func add_score(points: int) -> void:
	score += points

# ---- Helpers ----
func randf_range(a: float, b: float) -> float:
	return rng.randf_range(a, b)

func randi_range(a: int, b: int) -> int:
	return rng.randi_range(a, b)

func rand_color_variant(base: Color, amount: float = 0.12) -> Color:
	var c := base
	c.r = clampf(c.r + rng.randf_range(-amount, amount), 0.0, 1.0)
	c.g = clampf(c.g + rng.randf_range(-amount, amount), 0.0, 1.0)
	c.b = clampf(c.b + rng.randf_range(-amount, amount), 0.0, 1.0)
	return c

func player_pos() -> Vector3:
	if player:
		return player.global_position
	return Vector3.ZERO

func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

## Returns the physics body that should receive hits for a node (walks up the tree).
static func hittable_of(node: Node) -> Node:
	var n := node
	while n:
		if n.has_method("take_hit"):
			return n
		n = n.get_parent()
	return null

## Player committed a crime: raises the wanted level.
func crime(kind: String) -> void:
	match kind:
		"assault":
			add_wanted(0.25)
			if wanted < 1.0:
				wanted = 1.0
				_update_stars()
		"murder":
			kills += 1
			add_score(100)
			add_wanted(0.8, "")
			if wanted < 1.0:
				wanted = 1.0
				_update_stars()
		"cop_assault":
			add_wanted(0.6)
			if wanted < 1.0:
				wanted = 1.0
				_update_stars()
		"cop_murder":
			kills += 1
			add_score(250)
			add_wanted(1.2, "COP DOWN  +WANTED")
			if wanted < 2.0:
				wanted = 2.0
				_update_stars()
		"carjack":
			add_score(150)
			add_wanted(1.0, "CAR STOLEN  +WANTED")
			if wanted < 1.0:
				wanted = 1.0
				_update_stars()
		"car_destroy":
			add_score(200)
			add_wanted(0.7)
	heat_timer = 0.0

## Scare every pedestrian near a point.
func panic(pos: Vector3, radius: float) -> void:
	for p in get_tree().get_nodes_in_group("peds"):
		if p.has_method("scare") and p.global_position.distance_to(pos) < radius:
			p.scare(pos)
