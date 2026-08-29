shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 bolt_color : source_color = vec4(0.25, 0.72, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 20.0) = 8.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float jitter_amount : hint_range(0.0, 0.4) = 0.10;
uniform float animation_speed : hint_range(0.0, 60.0) = 28.0;
uniform float bolt_segments : hint_range(2.0, 40.0) = 18.0;

float hash_value(float value) {
	return fract(sin(value * 127.1) * 43758.5453123);
}

void vertex() {
	float frame = floor(TIME * animation_speed);
	float segment = floor(UV.y * bolt_segments);
	float next_segment = segment + 1.0;
	float blend = smoothstep(0.0, 1.0, fract(UV.y * bolt_segments));
	vec2 current_jitter = vec2(hash_value(segment + frame * 31.0), hash_value(segment + frame * 47.0 + 11.0)) - vec2(0.5);
	vec2 next_jitter = vec2(hash_value(next_segment + frame * 31.0), hash_value(next_segment + frame * 47.0 + 11.0)) - vec2(0.5);
	float endpoint_mask = sin(UV.y * 3.14159265);
	VERTEX.xz += mix(current_jitter, next_jitter, blend) * jitter_amount * endpoint_mask;
}

void fragment() {
	float frame = floor(TIME * animation_speed);
	float random_flicker = 0.72 + hash_value(frame + UV.y * 7.0) * 0.28;
	float traveling_arc = 0.75 + 0.25 * sin(UV.y * 92.0 - TIME * 64.0 + UV.x * 13.0);
	float edge_glow = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.7);
	float intensity = random_flicker * traveling_arc;
	ALBEDO = bolt_color.rgb * intensity;
	EMISSION = bolt_color.rgb * emission_strength * intensity;
	ALPHA = opacity * intensity * (0.58 + edge_glow * 0.42);
}
