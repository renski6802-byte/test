shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

// 수평선까지 이어지는 먼바다. 판 하나에 삼각형 둘이라 형태는 못 만들고,
// 법선만 흔들어 물결을 흉내낸다. 색을 만드는 방식은 가까운 바다와 같아야
// 두 판이 이어지는 자리가 안 보인다.

uniform vec3 deep_color : source_color = vec3(0.008, 0.032, 0.055);
uniform vec3 shallow_color : source_color = vec3(0.045, 0.135, 0.160);
uniform vec3 sky_horizon : source_color = vec3(0.62, 0.74, 0.84);
uniform vec3 sky_zenith : source_color = vec3(0.24, 0.45, 0.72);
uniform float choppiness = 1.0;
uniform float fade_dist = 30000.0;
uniform float detail_dist = 4500.0;

varying vec3 world_pos;

vec3 wave_normal(vec2 p, float t) {
	vec2 g = vec2(0.0);
	vec2 d0 = normalize(vec2(1.00, 0.15));
	vec2 d1 = normalize(vec2(0.85, 0.50));
	vec2 d2 = normalize(vec2(-0.50, 1.00));
	vec2 d3 = normalize(vec2(0.30, -1.00));

	float k0 = 6.2831853 / 140.0;
	float k1 = 6.2831853 / 78.0;
	float k2 = 6.2831853 / 44.0;
	float k3 = 6.2831853 / 25.0;

	g += d0 * (0.90 * choppiness * k0 * cos(k0 * dot(d0, p) - sqrt(9.81 * k0) * t));
	g += d1 * (0.55 * choppiness * k1 * cos(k1 * dot(d1, p) - sqrt(9.81 * k1) * t));
	g += d2 * (0.32 * choppiness * k2 * cos(k2 * dot(d2, p) - sqrt(9.81 * k2) * t));
	g += d3 * (0.18 * choppiness * k3 * cos(k3 * dot(d3, p) - sqrt(9.81 * k3) * t));

	return normalize(vec3(-g.x, 1.0, -g.y));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);

	float detail = clamp(1.0 - dist / detail_dist, 0.0, 1.0);
	vec3 n = normalize(mix(vec3(0.0, 1.0, 0.0), wave_normal(world_pos.xz, TIME), detail));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	vec3 view_dir = normalize(-VERTEX);
	vec3 nv = normalize(NORMAL);
	float f = clamp(dot(nv, view_dir), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - f, 5.0);

	vec3 refl_dir = reflect(-view_dir, nv);
	vec3 world_refl = (INV_VIEW_MATRIX * vec4(refl_dir, 0.0)).xyz;
	vec3 sky = mix(sky_horizon, sky_zenith, clamp(world_refl.y * 1.6, 0.0, 1.0));

	vec3 body = mix(deep_color, shallow_color, clamp(1.0 - f * 0.85, 0.0, 1.0));
	vec3 col = mix(body, sky, fres);

	float far = clamp(dist / fade_dist, 0.0, 1.0);
	ALBEDO = mix(col, sky_horizon, far * 0.75);
	ROUGHNESS = mix(0.045, 0.35, far);
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
