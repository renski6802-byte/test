shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

// 바다는 평평한 판 하나다. 물결은 꼭짓점을 밀지 않고 법선만 흔들어 만든다.
// 그래야 수평선까지 판 하나로 덮으면서도 값이 싸다.

uniform vec3 deep_color : source_color = vec3(0.020, 0.062, 0.105);
uniform vec3 near_color : source_color = vec3(0.095, 0.255, 0.330);
uniform vec3 horizon_tint : source_color = vec3(0.560, 0.670, 0.760);
uniform float choppiness = 1.0;
uniform float fade_dist = 42000.0;
uniform float detail_dist = 6500.0;

varying vec3 world_pos;

void wave_grad(vec2 p, float t, out float dx, out float dz) {
	vec2 d0 = normalize(vec2(1.0, 0.18));
	vec2 d1 = normalize(vec2(-0.55, 1.0));
	vec2 d2 = normalize(vec2(0.35, -1.0));
	vec2 d3 = normalize(vec2(-1.0, -0.45));

	float k0 = 6.2831853 / 52.0;
	float k1 = 6.2831853 / 26.0;
	float k2 = 6.2831853 / 12.0;
	float k3 = 6.2831853 / 5.5;

	// 파장이 길수록 느리게 흐른다 (깊은 물 분산 관계)
	float c0 = cos(dot(d0, p) * k0 + t * sqrt(9.81 * k0)) * 0.55 * choppiness * k0;
	float c1 = cos(dot(d1, p) * k1 + t * sqrt(9.81 * k1)) * 0.32 * choppiness * k1;
	float c2 = cos(dot(d2, p) * k2 + t * sqrt(9.81 * k2)) * 0.17 * choppiness * k2;
	float c3 = cos(dot(d3, p) * k3 + t * sqrt(9.81 * k3)) * 0.09 * choppiness * k3;

	dx = d0.x * c0 + d1.x * c1 + d2.x * c2 + d3.x * c3;
	dz = d0.y * c0 + d1.y * c1 + d2.y * c2 + d3.y * c3;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);

	// 멀어질수록 물결을 접는다. 안 그러면 수평선이 지글거린다.
	float detail = clamp(1.0 - dist / detail_dist, 0.0, 1.0);
	float dx;
	float dz;
	wave_grad(world_pos.xz, TIME, dx, dz);
	vec3 n = normalize(vec3(-dx * detail, 1.0, -dz * detail));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float fade = clamp(dist / fade_dist, 0.0, 1.0);
	vec3 col = mix(near_color, deep_color, clamp(dist / 2500.0, 0.0, 1.0));
	ALBEDO = mix(col, horizon_tint, fade * 0.9);
	ROUGHNESS = mix(0.05, 0.45, fade);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
