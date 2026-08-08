shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

// 수평선까지 이어지는 먼바다. 판 하나에 삼각형 둘이고, 파도는 법선만 흔들어 흉내낸다.
// 이 거리에서는 파도의 형태가 눈에 안 들어오므로 그걸로 충분하다.

uniform vec3 deep_color : source_color = vec3(0.012, 0.044, 0.078);
uniform vec3 near_color : source_color = vec3(0.050, 0.150, 0.205);
uniform vec3 horizon_tint : source_color = vec3(0.560, 0.670, 0.760);
uniform float choppiness = 1.0;
uniform float fade_dist = 42000.0;
uniform float detail_dist = 7000.0;

varying vec3 world_pos;

void wave_grad(vec2 p, float t, out float dx, out float dz) {
	vec2 d0 = normalize(vec2(1.00, 0.18));
	vec2 d1 = normalize(vec2(-0.55, 1.00));
	vec2 d2 = normalize(vec2(0.35, -1.00));
	vec2 d3 = normalize(vec2(-1.00, -0.45));

	float k0 = 6.2831853 / 62.0;
	float k1 = 6.2831853 / 34.0;
	float k2 = 6.2831853 / 17.0;
	float k3 = 6.2831853 / 8.0;

	float c0 = cos(k0 * dot(d0, p) - sqrt(9.81 * k0) * t) * 0.85 * choppiness * k0;
	float c1 = cos(k1 * dot(d1, p) - sqrt(9.81 * k1) * t) * 0.45 * choppiness * k1;
	float c2 = cos(k2 * dot(d2, p) - sqrt(9.81 * k2) * t) * 0.22 * choppiness * k2;
	float c3 = cos(k3 * dot(d3, p) - sqrt(9.81 * k3) * t) * 0.10 * choppiness * k3;

	dx = d0.x * c0 + d1.x * c1 + d2.x * c2 + d3.x * c3;
	dz = d0.y * c0 + d1.y * c1 + d2.y * c2 + d3.y * c3;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);

	// 멀수록 물결을 접는다. 안 그러면 수평선이 지글거린다.
	float detail = clamp(1.0 - dist / detail_dist, 0.0, 1.0);
	float dx;
	float dz;
	wave_grad(world_pos.xz, TIME, dx, dz);
	vec3 n = normalize(vec3(-dx * detail, 1.0, -dz * detail));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float fade = clamp(dist / fade_dist, 0.0, 1.0);
	vec3 col = mix(near_color, deep_color, clamp(dist / 2500.0, 0.0, 1.0));
	ALBEDO = mix(col, horizon_tint, fade * 0.82);
	ROUGHNESS = mix(0.13, 0.42, fade);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
