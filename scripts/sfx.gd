class_name Sfx
extends Node
## Sound. Real recorded CC0 effects from res://sounds (see CREDITS.md) with
## random variations and no immediate repeats, far-away versions of gunshots
## and explosions, a few synthesized sounds (powers), audio buses with an urban
## slap-back echo on gunfire, light reverb, a limiter, and a city ambience bed.

## Sound groups in res://sounds: name -> number of variations (0 = single file).
const COUNTS := {"amb_traffic": 0, "amb_wind": 0, "bodyfall": 6, "bone": 8, "carhit": 4, "casing": 3, "concrete": 3,
	"crunch": 5, "dead": 4, "door_close": 0, "door_open": 0, "engine_high": 2, "engine_loop": 0, "engine_start": 0,
	"explosion": 1, "explosion_far": 1, "glass": 4, "grunt": 6, "hit": 8, "horn_loop": 0, "horn_start": 0, "hurt": 5,
	"metal": 4, "pain": 12, "pain_f": 6, "pickup": 3, "pistol": 3, "pistol_far": 2, "punch": 5, "ricochet": 3,
	"scream_f": 7, "shotgun": 3, "shotgun_far": 2, "siren_loop": 0, "skid_loop": 0, "smg": 2, "smg_far": 1,
	"splat": 8, "squish": 6, "step": 4, "whoosh": 3, "wood": 3, "yell": 14}

## name -> [groups, volume dB, unit size, max distance, pitch jitter, bus]
const DEFS := {
	"pistol": [["pistol"], 6.0, 18.0, 450.0, 0.03, "Guns"],
	"shotgun": [["shotgun"], 8.0, 20.0, 500.0, 0.03, "Guns"],
	"smg": [["smg"], 4.0, 16.0, 420.0, 0.05, "Guns"],
	"explosion": [["explosion"], 12.0, 40.0, 800.0, 0.08, "Guns"],
	"punch": [["punch", "hit"], 3.0, 3.0, 45.0, 0.08, "World"],
	"squish": [["squish"], 1.0, 3.0, 40.0, 0.1, "World"],
	"splat": [["splat"], 3.0, 4.0, 55.0, 0.08, "World"],
	"slash": [["squish", "splat"], 1.0, 3.0, 45.0, 0.12, "World"],
	"crack": [["bone"], 3.0, 4.0, 55.0, 0.08, "World"],
	"crunch": [["crunch"], 3.0, 4.0, 55.0, 0.08, "World"],
	"thud": [["bodyfall"], 1.0, 4.0, 50.0, 0.1, "World"],
	"clank": [["metal", "carhit"], 1.0, 6.0, 90.0, 0.08, "World"],
	"carhit": [["carhit"], 5.0, 9.0, 140.0, 0.08, "World"],
	"glass": [["glass"], 3.0, 6.0, 90.0, 0.06, "World"],
	"concrete": [["concrete"], -1.0, 3.0, 45.0, 0.12, "World"],
	"wood": [["wood"], -1.0, 3.0, 45.0, 0.1, "World"],
	"pickup": [["pickup"], -6.0, 2.0, 20.0, 0.08, "World"],
	"scream": [["yell"], 3.0, 7.0, 100.0, 0.06, "Voice"],
	"scream_f": [["scream_f"], 3.0, 7.0, 100.0, 0.06, "Voice"],
	"grunt": [["grunt", "hurt"], 0.0, 4.0, 55.0, 0.06, "Voice"],
	"pain": [["pain", "hurt"], 1.0, 4.0, 60.0, 0.06, "Voice"],
	"pain_f": [["pain_f"], 1.0, 4.0, 60.0, 0.05, "Voice"],
	"yell": [["yell"], 1.0, 5.0, 85.0, 0.06, "Voice"],
	"dead": [["dead"], 1.0, 4.0, 60.0, 0.05, "Voice"],
	"whoosh": [["whoosh"], -3.0, 2.0, 25.0, 0.15, "World"],
	"ricochet": [["ricochet"], -2.0, 5.0, 80.0, 0.12, "World"],
	"casing": [["casing"], -9.0, 1.5, 15.0, 0.12, "World"],
	"step": [["step"], -12.0, 1.5, 18.0, 0.12, "World"],
	"door_open": [["door_open"], -2.0, 3.0, 30.0, 0.04, "World"],
	"door_close": [["door_close"], 0.0, 3.0, 35.0, 0.04, "World"],
	"enter_car": [["door_close"], 0.0, 3.0, 35.0, 0.04, "World"],
	"engine_start": [["engine_start"], 0.0, 5.0, 60.0, 0.02, "World"],
	"horn": [["horn_start"], 4.0, 10.0, 150.0, 0.0, "World"],
}

## Looping sounds: name -> [file, bus]
const LOOPS := {"engine": ["engine_loop", "World"], "engine_high": ["engine_high_0", "World"], "siren": ["siren_loop", "World"],
	"skid": ["skid_loop", "World"], "horn": ["horn_loop", "World"]}

const RATE := 22050
const POOL_SIZE := 32
var streams: Dictionary = {}       # file name -> AudioStream
var synth: Dictionary = {}         # synthesized clips
var last_pick: Dictionary = {}
var pool: Array[AudioStreamPlayer3D] = []
var pool_index := 0
var amb_traffic: AudioStreamPlayer
var amb_wind: AudioStreamPlayer

func _ready() -> void:
	_setup_buses()
	for g in COUNTS.keys():
		var n: int = COUNTS[g]
		if n == 0:
			_load(g)
		else:
			for i in n:
				_load("%s_%d" % [g, i])
	_build_synth()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		pool.append(p)
	amb_traffic = _ambience("amb_traffic", -15.0)
	amb_wind = _ambience("amb_wind", -24.0)

func _load(file: String) -> void:
	var path := "res://sounds/%s.ogg" % file
	if ResourceLoader.exists(path):
		streams[file] = load(path)

func _ambience(file: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = streams.get(file)
	p.volume_db = db
	p.bus = "Ambience"
	p.autoplay = true
	add_child(p)
	return p

func _setup_buses() -> void:
	if AudioServer.get_bus_index("World") >= 0:
		return
	# Master: final limiter so stacked explosions never clip
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	_add_bus("World", "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55
	rev.damping = 0.6
	rev.spread = 0.8
	rev.hipass = 0.25
	rev.dry = 1.0
	rev.wet = 0.1
	AudioServer.add_bus_effect(AudioServer.get_bus_index("World"), rev)
	_add_bus("Guns", "World")
	# slap-back echoes off the buildings
	var d := AudioEffectDelay.new()
	d.dry = 1.0
	d.tap1_active = true
	d.tap1_delay_ms = 140.0
	d.tap1_level_db = -13.0
	d.tap1_pan = -0.3
	d.tap2_active = true
	d.tap2_delay_ms = 310.0
	d.tap2_level_db = -19.0
	d.tap2_pan = 0.35
	d.feedback_active = false
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Guns"), d)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -10.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Guns"), comp)
	_add_bus("Voice", "World")
	_add_bus("Ambience", "Master")

func _add_bus(bus_name: String, send: String) -> void:
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)

func _listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO

## Pick a random variation of a group, never the same one twice in a row.
func _pick(group: String) -> AudioStream:
	var n: int = COUNTS.get(group, -1)
	if n < 0:
		return null
	if n == 0:
		return streams.get(group)
	var i := Game.rng.randi_range(0, n - 1)
	if n > 1 and last_pick.get(group, -1) == i:
		i = (i + 1) % n
	last_pick[group] = i
	return streams.get("%s_%d" % [group, i])

func play(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var stream: AudioStream = null
	var def: Array = DEFS.get(sound_name, [])
	var unit := 4.0
	var maxd := 80.0
	var jitter := 0.07
	var bus := "World"
	var vol := volume_db
	if def.is_empty():
		stream = synth.get(sound_name)
		if stream == null:
			return null
	else:
		var groups: Array = def[0]
		var group: String = groups[Game.rng.randi_range(0, groups.size() - 1)]
		# distant gunfire and explosions use the far-away recordings
		if COUNTS.has(group + "_far") and pos.distance_to(_listener_pos()) > 30.0:
			group += "_far"
		stream = _pick(group)
		vol += def[1]
		unit = def[2]
		maxd = def[3]
		jitter = def[4]
		bus = def[5]
	if stream == null:
		return null
	var p: AudioStreamPlayer3D = pool[pool_index]
	pool_index = (pool_index + 1) % POOL_SIZE
	p.stop()
	p.stream = stream
	p.bus = bus
	p.unit_size = unit
	p.max_distance = maxd
	p.global_position = pos
	p.volume_db = vol
	p.pitch_scale = pitch * Game.randf_range(1.0 - jitter, 1.0 + jitter)
	p.play()
	return p

## Dedicated looping player (engines, sirens, skids, horn, telekinesis hum).
func make_loop_player(sound_name: String, parent: Node, volume_db: float = -6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if LOOPS.has(sound_name):
		p.stream = streams.get(LOOPS[sound_name][0])
		p.bus = LOOPS[sound_name][1]
	else:
		p.stream = synth.get(sound_name)
		p.bus = "World"
	p.volume_db = volume_db
	p.max_distance = 120.0 if sound_name == "siren" else 70.0
	p.unit_size = 12.0 if sound_name == "siren" else 5.0
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -18.0
	p.autoplay = false
	parent.add_child(p)
	return p

# ---------------------------------------------------------------- synthesized (powers)
func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _tone(dur: float, f0: float, f1: float, decay: float, gain: float = 1.0, saw: bool = false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / dur) / RATE
		var s := (2.0 * fmod(phase / TAU, 1.0) - 1.0) if saw else sin(phase)
		out[i] = s * exp(-t * decay) * gain
	return out

func _build_synth() -> void:
	# telekinesis: rising shimmer when grabbing, low pulsing hum while holding
	var g := _tone(0.45, 180.0, 720.0, 4.0, 0.5)
	var g2 := _tone(0.45, 360.0, 1440.0, 5.0, 0.2)
	for i in g.size():
		g[i] += g2[i]
	synth["tk_grab"] = _wav(g)
	var n := int(1.0 * RATE)
	var hum := PackedFloat32Array()
	hum.resize(n)
	for i in n:
		var t := float(i) / RATE
		hum[i] = (sin(TAU * 55.0 * t) * 0.35 + sin(TAU * 110.0 * t) * 0.15 + sin(TAU * 165.0 * t) * 0.06) * (0.75 + 0.25 * sin(TAU * 4.0 * t))
	synth["tk_hum"] = _wav(hum, true)
	synth["jump"] = _wav(_tone(0.25, 120.0, 60.0, 9.0, 0.6))
