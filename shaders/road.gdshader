shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Asphalt with painted markings. Roads run along both axes every `block` m.

uniform sampler2D asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float half_size = 176.0;
uniform float block = 44.0;
uniform float road_half = 4.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float band(float x, float a, float b, float w) { return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x)); }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz + vec2(half_size);
	vec2 m = mod(p + vec2(block * 0.5), block) - vec2(block * 0.5);
	vec2 r = abs(m);
	vec2 uv = wpos.xz / 2.1;
	vec4 a = texture(asphalt, uv);
	vec4 a2 = texture(asphalt, uv * 0.37 + vec2(0.31, 0.17));
	float macro = vnoise(wpos.xz * 0.12) * 0.6 + vnoise(wpos.xz * 0.5) * 0.4;
	vec3 col = mix(a.rgb, a2.rgb, 0.35) * (0.82 + macro * 0.3);
	float rough = mix(a.a, 0.95, 0.3);
	bool road_x = r.x < road_half;
	bool road_z = r.y < road_half;
	vec2 fw = fwidth(p) + vec2(0.001);
	// tyre wear: darker, smoother strips along each lane
	float lane_x = band(r.x, 1.05, 1.65, 0.3) + band(r.x, 2.45, 3.05, 0.3);
	float lane_z = band(r.y, 1.05, 1.65, 0.3) + band(r.y, 2.45, 3.05, 0.3);
	float wear = clamp(lane_x * float(road_x) * step(road_half, r.y) + lane_z * float(road_z) * step(road_half, r.x), 0.0, 1.0);
	col *= 1.0 - wear * 0.12;
	rough -= wear * 0.08;
	// markings
	float dbl_x = (band(r.x, 0.06, 0.16, fw.x)) * step(9.5, r.y);
	float dbl_z = (band(r.y, 0.06, 0.16, fw.y)) * step(9.5, r.x);
	float edge_x = band(r.x, 3.6, 3.75, fw.x) * float(road_x) * step(road_half + 3.0, r.y);
	float edge_z = band(r.y, 3.6, 3.75, fw.y) * float(road_z) * step(road_half + 3.0, r.x);
	float cw_x = float(road_x) * band(r.y, 4.5, 6.6, fw.y) * band(fract(p.x / 1.1), 0.45, 1.0, fw.x / 1.1) * step(r.x, 3.4);
	float cw_z = float(road_z) * band(r.x, 4.5, 6.6, fw.x) * band(fract(p.y / 1.1), 0.45, 1.0, fw.y / 1.1) * step(r.y, 3.4);
	float stop_x = float(road_x) * band(r.y, 7.0, 7.4, fw.y) * band(m.x * sign(m.y), 0.2, 3.5, fw.x);
	float stop_z = float(road_z) * band(r.x, 7.0, 7.4, fw.x) * band(-m.y * sign(m.x), 0.2, 3.5, fw.y);
	float paint_w = clamp(edge_x + edge_z + cw_x + cw_z + stop_x + stop_z, 0.0, 1.0);
	float paint_y = clamp(dbl_x * float(road_x) + dbl_z * float(road_z), 0.0, 1.0);
	// worn paint
	float worn = 0.55 + 0.45 * vnoise(wpos.xz * 3.0);
	col = mix(col, vec3(0.8, 0.62, 0.15), paint_y * worn);
	col = mix(col, vec3(0.82, 0.82, 0.8), paint_w * worn);
	rough = mix(rough, 0.6, max(paint_w, paint_y));
	// manhole covers in the middle of some lanes
	vec2 cell = floor(p / block);
	vec2 mh = vec2(block * 0.5 + 2.0, block * 0.5 + 14.0 + hash(cell) * 10.0);
	float d_mh = length(mod(p, block) - mh);
	float ring = band(d_mh, 0.0, 0.33, 0.01) * float(road_x);
	col = mix(col, vec3(0.12, 0.11, 0.1) * (0.8 + 0.4 * step(0.5, fract(d_mh * 12.0))), ring);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	NORMAL_MAP = texture(asphalt_n, uv).rgb;
	NORMAL_MAP_DEPTH = 0.7;
}
