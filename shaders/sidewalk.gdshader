shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Raised blocks: curb stones, slab sidewalk, and pavers inside the block.

uniform sampler2D walk : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D walk_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D curb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D pavers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pavers_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float half_size = 176.0;
uniform float block = 44.0;
uniform float road_half = 4.0;
uniform float walk_w = 3.0;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz + vec2(half_size);
	vec2 m = mod(p, block);
	vec2 d = min(m, vec2(block) - m) - vec2(road_half);
	float e = min(d.x, d.y);
	vec3 col;
	float rough;
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (wn.y > 0.5) {
		if (e < 0.3) {
			col = texture(curb, wpos.xz / 2.0).rgb * 1.15;
			rough = 0.8;
		} else if (e < walk_w) {
			vec4 t = texture(walk, wpos.xz / 1.8);
			col = t.rgb;
			rough = t.a;
			nm = texture(walk_n, wpos.xz / 1.8).rgb;
			// darker grime along the curb and near buildings
			col *= mix(0.8, 1.0, smoothstep(0.3, 0.9, e)) * mix(1.0, 0.85, smoothstep(walk_w - 0.6, walk_w, e));
		} else {
			vec4 t = texture(pavers, wpos.xz / 2.0);
			col = t.rgb;
			rough = t.a;
			nm = texture(pavers_n, wpos.xz / 2.0).rgb;
		}
	} else {
		vec2 suv = (abs(wn.x) > 0.5 ? wpos.zy : wpos.xy) / 2.0;
		col = texture(curb, suv).rgb * 1.05;
		rough = 0.85;
		col *= mix(0.6, 1.0, smoothstep(0.0, 0.12, wpos.y));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.8;
}
