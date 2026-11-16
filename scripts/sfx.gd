class_name Sfx
extends Node
## Procedurally generated sound effects (no audio files needed). All clips are
## synthesized once at startup into AudioStreamWAV resources and played through
## a small pool of AudioStreamPlayer3D nodes.

const RATE := 22050
var clips: Dictionary = {}
var pool: Array[AudioStreamPlayer3D] = []
var pool_index := 0
const POOL_SIZE := 20

func _ready() -> void:
	_build_all()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 90.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		pool.append(p)

func play(name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	if not clips.has(name):
		return null
	var p: AudioStreamPlayer3D = pool[pool_index]
	pool_index = (pool_index + 1) % POOL_SIZE
	p.stop()
	p.stream = clips[name]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * Game.randf_range(0.93, 1.07)
	p.play()
	return p

## Dedicated looping player for engines / sirens / telekinesis hum.
func make_loop_player(name: String, parent: Node, volume_db: float = -6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = clips[name]
	p.volume_db = volume_db
	p.max_distance = 70.0
	p.unit_size = 5.0
	p.autoplay = false
	parent.add_child(p)
	return p

# ---------------------------------------------------------------- synthesis
func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _noise_burst(dur: float, decay: float, lowpass: float = 0.0, gain: float = 1.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay)
		var s := Game.rng.randf_range(-1.0, 1.0)
		if lowpass > 0.0:
			prev = prev + (s - prev) * lowpass
			s = prev
		out[i] = s * env * gain
	return out

func _tone(dur: float, f0: float, f1: float, decay: float, gain: float = 1.0, wave: int = 0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(f0, f1, k)
		phase += TAU * f / RATE
		var s: float
		if wave == 0:
			s = sin(phase)
		elif wave == 1:
			s = 2.0 * (fmod(phase / TAU, 1.0)) - 1.0
		else:
			s = 1.0 if sin(phase) > 0.0 else -1.0
		out[i] = s * exp(-t * decay) * gain
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i < b.size():
			v += b[i]
		out[i] = v
	return out

func _build_all() -> void:
	# Guns
	clips["pistol"] = _wav(_mix(_noise_burst(0.28, 22.0, 0.6, 0.9), _tone(0.2, 180.0, 60.0, 25.0, 0.7)))
	clips["shotgun"] = _wav(_mix(_noise_burst(0.45, 12.0, 0.35, 1.0), _tone(0.35, 120.0, 40.0, 14.0, 0.9)))
	clips["smg"] = _wav(_mix(_noise_burst(0.12, 45.0, 0.7, 0.8), _tone(0.1, 220.0, 90.0, 40.0, 0.5)))
	# Impacts
	clips["punch"] = _wav(_mix(_tone(0.14, 90.0, 45.0, 30.0, 0.9), _noise_burst(0.1, 50.0, 0.25, 0.4)))
	clips["squish"] = _wav(_mix(_noise_burst(0.25, 18.0, 0.12, 0.8), _tone(0.2, 300.0, 80.0, 30.0, 0.3)))
	clips["crack"] = _wav(_mix(_noise_burst(0.08, 60.0, 0.9, 1.0), _noise_burst(0.2, 25.0, 0.3, 0.5)))
	clips["slash"] = _wav(_noise_burst(0.22, 20.0, 0.85, 0.7))
	clips["thud"] = _wav(_tone(0.2, 70.0, 35.0, 18.0, 0.9))
	clips["clank"] = _wav(_mix(_tone(0.3, 900.0, 600.0, 14.0, 0.4, 2), _noise_burst(0.2, 30.0, 0.5, 0.6)))
	clips["splat"] = _wav(_mix(_noise_burst(0.3, 14.0, 0.08, 0.9), _tone(0.15, 150.0, 50.0, 25.0, 0.5)))
	# Voices
	clips["scream"] = _wav(_mix(_tone(0.7, 900.0, 500.0, 2.5, 0.35, 1), _tone(0.7, 1350.0, 760.0, 3.0, 0.2)))
	clips["grunt"] = _wav(_tone(0.25, 220.0, 120.0, 10.0, 0.5, 1))
	clips["yell"] = _wav(_tone(0.45, 400.0, 300.0, 5.0, 0.4, 1))
	# Powers
	clips["whoosh"] = _wav(_noise_burst(0.5, 7.0, 0.2, 0.8))
	clips["tk_grab"] = _wav(_tone(0.4, 200.0, 600.0, 4.0, 0.4))
	clips["tk_hum"] = _wav(_mix(_tone(0.5, 55.0, 55.0, 0.0, 0.35, 1), _tone(0.5, 110.0, 110.0, 0.0, 0.15)), true)
	clips["explosion"] = _wav(_mix(_noise_burst(1.6, 3.5, 0.08, 1.0), _tone(0.8, 60.0, 25.0, 4.0, 1.0)))
	clips["jump"] = _wav(_tone(0.2, 300.0, 700.0, 10.0, 0.3))
	clips["pickup"] = _wav(_tone(0.12, 600.0, 900.0, 20.0, 0.3))
	clips["enter_car"] = _wav(_mix(_tone(0.2, 300.0, 120.0, 15.0, 0.4, 2), _noise_burst(0.15, 30.0, 0.4, 0.3)))
	clips["dead"] = _wav(_tone(1.2, 220.0, 55.0, 2.5, 0.6, 1))
	# Loops
	clips["engine"] = _wav(_mix(_tone(0.5, 60.0, 60.0, 0.0, 0.35, 1), _noise_burst(0.5, 0.0, 0.05, 0.2)), true)
	clips["siren"] = _wav(_build_siren(), true)
	clips["skid"] = _wav(_noise_burst(0.4, 0.0, 0.5, 0.5), true)

func _build_siren() -> PackedFloat32Array:
	var dur := 1.4
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 720.0 if fmod(t, 0.7) < 0.35 else 960.0
		phase += TAU * f / RATE
		out[i] = (sin(phase) * 0.5 + (1.0 if sin(phase * 2.0) > 0.0 else -1.0) * 0.08) * 0.6
	return out
