shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

// 수평선까지 이어지는 먼바다. 가까운 바다 판이 끝나는 자리부터 시작하는 고리라,
// 형태는 못 만들고 법선만 흔들어 물결을 흉내낸다.
//
// 색을 만드는 방식은 ocean_near 와 한 줄씩 맞춰야 한다. 한쪽만 하늘을 더 섞으면
// 이어지는 자리에 띠가 생긴다. 예전에 먼바다가 하얗게 뜬 것도 여기서 하늘을
// 한 번 더 덧칠했기 때문이다.

#include "res://shaders/sky_common.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.005, 0.021, 0.040);
uniform vec3 shallow_color : source_color = vec3(0.028, 0.098, 0.126);
uniform float choppiness = 1.0;
uniform sampler2D ripple_normals : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

// ocean_near 의 DIRS/LENS/AMPS 와 같은 네 겹
const vec2 DIRS[4] = { vec2(1.00, 0.10), vec2(0.20, 1.00),
					   vec2(-0.90, 0.55), vec2(0.55, -0.95) };
const float LENS[4] = { 143.0, 81.0, 47.0, 27.0 };
const float AMPS[4] = { 0.92, 0.56, 0.30, 0.16 };

vec2 rot2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

vec3 swell_normal(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 d = normalize(DIRS[i]);
		float k = 6.2831853 / LENS[i];
		g += d * (AMPS[i] * choppiness * k * cos(k * dot(d, p) - sqrt(9.81 * k) * t));
	}
	return normalize(vec3(-g.x, 1.0, -g.y));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);
	float t = TIME;

	// 너울은 몇 km 안쪽에서만 형태가 남는다. 그 너머는 잔잔한 판으로 수렴시킨다.
	float detail = clamp(1.0 - dist / 5200.0, 0.0, 1.0);
	vec3 n = normalize(mix(vec3(0.0, 1.0, 0.0), swell_normal(world_pos.xz, t), detail));

	// 이어지는 자리에서 잔결이 뚝 끊기지 않도록 near 와 같은 배율·같은 감쇠를 쓴다
	float f1 = clamp(1.0 - dist / 2600.0, 0.0, 1.0);
	float f2 = clamp(1.0 - dist / 900.0, 0.0, 1.0);
	vec2 tilt = vec2(0.0);
	if (f1 > 0.001) {
		vec3 r1 = texture(ripple_normals, rot2(world_pos.xz, 0.0) / 41.0
			+ vec2(t * 0.008, t * 0.005)).xyz * 2.0 - 1.0;
		vec3 r2 = texture(ripple_normals, rot2(world_pos.xz, 0.93) / 13.7
			- vec2(t * 0.017, t * 0.011)).xyz * 2.0 - 1.0;
		tilt = r1.xz * 0.20 * f1 + r2.xz * 0.15 * f2;
	}

	// near 와 같이 색용·반짝임용 법선을 나눈다
	vec3 n_fine = normalize(n + vec3(tilt.x, 0.0, tilt.y));
	vec3 n_body = normalize(n + vec3(tilt.x, 0.0, tilt.y) * 0.26);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_fine, 0.0)).xyz);

	vec3 view_dir = normalize(-VERTEX);
	vec3 nv = normalize((VIEW_MATRIX * vec4(n_body, 0.0)).xyz);

	// near 와 똑같이. 멀수록 물결이 잘게 흩어져 거울 노릇을 못 하므로 반사를 누른다.
	float grazing = clamp(dist / 1300.0, 0.0, 1.0);
	float f = clamp(dot(nv, view_dir), 0.0, 1.0);
	float fres = (0.02 + 0.98 * pow(1.0 - f, 5.0)) * mix(1.0, 0.75, grazing);

	vec3 refl_dir = reflect(-view_dir, nv);
	vec3 world_refl = (INV_VIEW_MATRIX * vec4(refl_dir, 0.0)).xyz;
	vec3 sky = sky_color(world_refl) * 0.78;

	vec3 body = mix(deep_color, shallow_color, clamp(1.0 - f * 0.85, 0.0, 1.0));

	// near 와 같이 재질과 비친 하늘을 나눈다. 비친 하늘은 이미 빛이라
	// 다시 햇빛을 받으면 안 된다. 수평선을 하늘로 녹이는 일은 환경 안개가 맡는다.
	ALBEDO = body;
	EMISSION = sky * fres;
	ROUGHNESS = mix(0.20, 0.55, grazing);
	METALLIC = 0.0;
	// 가까운 물결은 거울처럼 해를 튕기지만, 먼 물결은 화면 한 점에 수천 개가
	// 겹쳐 서로 상쇄된다. 이걸 안 줄이면 해가 낮을 때 수평선 전체가 반짝임 길이 된다.
	SPECULAR = 0.0;   // 먼바다는 늘 상쇄 거리 밖이다
}
