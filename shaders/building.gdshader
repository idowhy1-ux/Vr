shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Buildings drawn as one MultiMesh of unit boxes. Upper floors use photo
// facades from a texture array; the ground floor is a procedural shopfront.
// INSTANCE_CUSTOM: x = facade slice, y = shop sign hue, z = seed, w = unused.
// COLOR (instance): wall tint applied to the non-glass parts of the facade.

uniform sampler2DArray facade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray facade_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tiles[6];
uniform float ground_floor = 4.2;

varying vec3 lpos;
varying vec3 bsize;
varying vec3 lnrm;
varying flat vec4 icustom;
varying flat vec4 icol;

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

vec3 hue(float h) {
	vec3 k = clamp(abs(fract(vec3(h) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k;
}

void vertex() {
	bsize = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = (VERTEX + vec3(0.5)) * bsize;
	lnrm = NORMAL;
	icustom = INSTANCE_CUSTOM;
	icol = COLOR;
}

void fragment() {
	int slice = int(icustom.x + 0.5);
	vec2 tile = tiles[slice].xy;
	vec3 n = lnrm;
	float u = abs(n.x) > 0.5 ? (n.x > 0.0 ? bsize.z - lpos.z : lpos.z) : (n.z > 0.0 ? lpos.x : bsize.x - lpos.x);
	float y = lpos.y;
	vec3 alb;
	float rough = 0.85;
	float metal = 0.0;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	vec3 emis = vec3(0.0);
	vec3 stone = texture(roof_albedo, vec2(u, y) / 3.0).rgb;
	if (n.y > 0.5) {
		alb = texture(roof_albedo, lpos.xz / 4.0).rgb * 0.8;
		rough = 0.95;
	} else if (y < ground_floor) {
		// ---- shopfront
		float bay_w = 5.2;
		float bay = floor(u / bay_w);
		float bu = fract(u / bay_w) * bay_w;
		float h = hash(bay + icustom.z * 13.0);
		vec3 wall = icol.rgb * stone * 1.3;
		alb = wall;
		rough = 0.85;
		float pil = step(bu, 0.45) + step(bay_w - 0.45, bu);
		bool is_glass = pil < 0.5 && y > 0.45 && y < 3.0;
		if (is_glass) {
			// mullions
			float mul = step(abs(bu - bay_w * 0.5), 0.03) + step(abs(y - 2.55), 0.03);
			bool door = h > 0.55 && abs(bu - (bay_w * 0.5 + 1.2)) < 0.55 && y < 2.45;
			vec3 glass = vec3(0.05, 0.06, 0.07);
			// fake shop interior: warm light falling off with height, shelves
			float shelf = step(0.85, fract(y * 1.6)) * step(0.6, h);
			vec3 inside = mix(vec3(0.5, 0.42, 0.32), vec3(0.85, 0.75, 0.6), h) * (0.25 + 0.2 * (1.0 - y / 3.0)) * (1.0 - shelf * 0.5);
			alb = glass + inside * 0.25;
			emis = inside * 0.35 * step(0.3, h);
			rough = 0.06;
			metal = 0.35;
			if (door) {
				alb = vec3(0.04, 0.035, 0.03);
				emis = vec3(0.0);
				rough = 0.4;
				metal = 0.1;
			}
			if (mul > 0.5) {
				alb = vec3(0.08);
				rough = 0.4;
				metal = 0.6;
				emis = vec3(0.0);
			}
		} else if (pil < 0.5 && y >= 3.0 && y < 3.75) {
			// sign band with "lettering"
			vec3 sc = mix(hue(fract(icustom.y + h * 0.35)), vec3(0.55), 0.5) * 0.75;
			float lx = fract((bu - 0.8) / 0.38);
			float letters = step(0.8, bu) * step(bu, bay_w - 0.8) * step(0.25, lx) * step(abs(y - 3.375), 0.17) * step(0.35, hash(floor((bu - 0.8) / 0.38) + bay * 7.0 + icustom.z));
			alb = mix(sc, vec3(0.95, 0.93, 0.85), letters);
			emis = alb * 0.05 * step(0.6, h);
			rough = 0.5;
		} else if (y < 0.45) {
			alb = stone * 0.55;
		} else if (y > 3.75) {
			alb = stone * 0.7;
		}
	} else {
		vec2 uv = vec2(u / tile.x, (y - ground_floor) / tile.y);
		vec4 t = texture(facade_albedo, vec3(uv, float(slice)));
		float glass = 1.0 - smoothstep(0.3, 0.55, t.a);
		alb = mix(t.rgb * icol.rgb * 1.15, t.rgb, glass);
		rough = t.a;
		metal = glass * 0.35;
		nm = texture(facade_normal, vec3(uv, float(slice))).rgb;
		// cornice / parapet at the top of the building
		float top = bsize.y - y;
		if (top < 0.55) {
			alb = stone * 0.85;
			rough = 0.9;
			metal = 0.0;
			nm = vec3(0.5, 0.5, 1.0);
		} else if (top < 0.7) {
			alb = stone * 0.5;
			rough = 0.9;
			metal = 0.0;
		}
		// soot / weathering towards the bottom
		alb *= 0.85 + 0.15 * smoothstep(ground_floor, ground_floor + 8.0, y);
	}
	// ambient occlusion where the walls meet the pavement
	alb *= mix(0.55, 1.0, smoothstep(0.0, 0.8, y));
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.8;
	EMISSION = emis;
}
