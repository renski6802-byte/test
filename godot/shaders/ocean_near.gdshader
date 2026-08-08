shader_type spatial;
render_mode specular_schlick_ggx;

// 배 주위의 바다. 꼭짓점을 실제로 밀어 파도의 형태를 만든다.
// 거스너 파도 넷을 겹치므로 물마루가 뾰족해지고 골이 완만해진다 — 진짜 물결의 모양이다.
//
// 여기 숫자는 scripts/Ocean.gd 의 WAVES 와 반드시 같아야 한다.
// 배가 파도를 타려면 CPU 가 같은 높이를 계산할 수 있어야 하기 때문이다.

uniform vec3 deep_color : source_color = vec3(0.012, 0.044, 0.078);
uniform vec3 near_color : source_color = vec3(0.050, 0.150, 0.205);
uniform vec3 horizon_tint : source_color = vec3(0.560, 0.670, 0.760);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform float choppiness = 1.0;
uniform float fade_dist = 42000.0;
uniform float half_extent = 1500.0;   // 이 판의 반지름. 가장자리에서 파도를 0으로 죽인다.

varying vec3 world_pos;
varying float crest;

vec3 gerstner(vec2 p, float t, out float height_only) {
	vec3 sum = vec3(0.0);
	height_only = 0.0;

	// dir, 파장, 진폭, 뾰족함
	vec2 d0 = normalize(vec2(1.00, 0.18));
	vec2 d1 = normalize(vec2(-0.55, 1.00));
	vec2 d2 = normalize(vec2(0.35, -1.00));
	vec2 d3 = normalize(vec2(-1.00, -0.45));

	float k0 = 6.2831853 / 62.0;
	float k1 = 6.2831853 / 34.0;
	float k2 = 6.2831853 / 17.0;
	float k3 = 6.2831853 / 8.0;

	float a0 = 0.85 * choppiness;
	float a1 = 0.45 * choppiness;
	float a2 = 0.22 * choppiness;
	float a3 = 0.10 * choppiness;

	float p0 = k0 * dot(d0, p) - sqrt(9.81 * k0) * t;
	float p1 = k1 * dot(d1, p) - sqrt(9.81 * k1) * t;
	float p2 = k2 * dot(d2, p) - sqrt(9.81 * k2) * t;
	float p3 = k3 * dot(d3, p) - sqrt(9.81 * k3) * t;

	sum.xz += d0 * (0.55 * a0) * cos(p0);
	sum.xz += d1 * (0.50 * a1) * cos(p1);
	sum.xz += d2 * (0.45 * a2) * cos(p2);
	sum.xz += d3 * (0.40 * a3) * cos(p3);

	height_only = a0 * sin(p0) + a1 * sin(p1) + a2 * sin(p2) + a3 * sin(p3);
	sum.y = height_only;
	return sum;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 판 가장자리에서는 파도를 접는다. 먼바다 판과 이어붙는 자리라 어긋나면 안 된다.
	float edge = 1.0 - smoothstep(half_extent * 0.72, half_extent * 0.98,
		max(abs(VERTEX.x), abs(VERTEX.z)));

	float h;
	vec3 disp = gerstner(wp.xz, TIME, h) * edge;

	// 법선은 이웃한 두 점을 실제로 밀어보고 구한다
	float hx;
	float hz;
	vec3 dx = gerstner(wp.xz + vec2(1.2, 0.0), TIME, hx) * edge;
	vec3 dz = gerstner(wp.xz + vec2(0.0, 1.2), TIME, hz) * edge;
	vec3 px = vec3(1.2, 0.0, 0.0) + dx - disp;
	vec3 pz = vec3(0.0, 0.0, 1.2) + dz - disp;
	vec3 n = normalize(cross(pz, px));

	VERTEX += disp;
	NORMAL = n;
	world_pos = wp + disp;

	// 물마루 꼭대기에만 거품을 얹는다. 문턱이 낮으면 바다가 통째로 하얘진다.
	crest = smoothstep(1.00, 1.48, h * edge);
}

void fragment() {
	float dist = length(VERTEX);
	float fade = clamp(dist / fade_dist, 0.0, 1.0);

	vec3 col = mix(near_color, deep_color, clamp(dist / 2500.0, 0.0, 1.0));
	col = mix(col, foam_color, crest * 0.62);
	ALBEDO = mix(col, horizon_tint, fade * 0.82);

	ROUGHNESS = mix(mix(0.13, 0.62, crest), 0.42, fade);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
