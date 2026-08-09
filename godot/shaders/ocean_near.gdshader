shader_type spatial;
render_mode specular_schlick_ggx;

// 배 주위의 바다.
//
// 형태는 거스너 네 겹으로만 만든다. 판의 한 칸(약 8m)보다 짧은 파도를 꼭짓점으로
// 만들면 격자에 걸려 규칙적인 줄무늬가 생기기 때문이다. 그보다 잔 결은 전부
// 노멀맵이 맡는다.
//
// 여기 네 겹은 scripts/Ocean.gd 의 WAVES 와 반드시 같아야 한다.
// 배가 파도를 타려면 CPU 가 같은 높이를 계산할 수 있어야 하기 때문이다.

// 하늘은 하늘 셰이더와 똑같은 식으로 만든다. 물빛의 절반이 비친 하늘이라
// 근사치를 따로 쓰면 절대 맞지 않는다.
#include "res://shaders/sky_common.gdshaderinc"
// 뭍이 서 있는 자리에는 바다를 안 그린다.
#include "res://shaders/land_cut.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.005, 0.021, 0.040);
uniform vec3 shallow_color : source_color = vec3(0.028, 0.098, 0.126);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform vec3 sss_color : source_color = vec3(0.09, 0.36, 0.32);
uniform float choppiness = 1.0;
uniform float half_extent = 1000.0;
uniform sampler2D ripple_normals : hint_normal, filter_linear_mipmap, repeat_enable;

// 뱃머리가 가르는 물살
uniform vec2 ship_pos = vec2(0.0);
uniform vec2 ship_dir = vec2(0.0, -1.0);
uniform float ship_speed01 = 0.0;

varying vec3 world_pos;
varying vec3 wave_normal;
varying float crest;

// dir, 파장(m), 진폭(m), 뾰족함 — 방향을 넓게 벌려야 반짝임이 한 줄로 서지 않는다
const vec2 DIRS[4] = { vec2(1.00, 0.10), vec2(0.20, 1.00),
					   vec2(-0.90, 0.55), vec2(0.55, -0.95) };
const float LENS[4] = { 143.0, 81.0, 47.0, 27.0 };
const float AMPS[4] = { 0.92, 0.56, 0.30, 0.16 };
const float QS[4]   = { 0.34, 0.40, 0.45, 0.48 };

void gerstner(vec2 p, float t, float gain, out vec3 disp, out vec3 nrm, out float steep) {
	disp = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	steep = 0.0;

	for (int i = 0; i < 4; i++) {
		vec2 d = normalize(DIRS[i]);
		float k = 6.2831853 / LENS[i];
		float a = AMPS[i] * choppiness * gain;
		float q = QS[i];
		float ph = k * dot(d, p) - sqrt(9.81 * k) * t;
		float c = cos(ph);
		float s = sin(ph);

		disp.xz += d * (q * a * c);
		disp.y += a * s;

		float wa = k * a;
		n.x -= d.x * wa * c;
		n.z -= d.y * wa * c;
		n.y -= q * wa * s;

		steep += wa * s;
	}
	nrm = normalize(n);
}

vec2 rot2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 칸마다 값을 하나씩 뽑아 쓰면 바둑판이 보인다. 부드럽게 이어 붙인다.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 먼바다 판과 이어붙는 자리라 가장자리에서 파도를 길게 접는다
	float edge = 1.0 - smoothstep(half_extent * 0.55, half_extent * 0.96,
		max(abs(VERTEX.x), abs(VERTEX.z)));

	vec3 disp;
	vec3 nrm;
	float steep;
	gerstner(wp.xz, TIME, edge, disp, nrm, steep);

	VERTEX += disp;
	world_pos = wp + disp;
	wave_normal = nrm;
	crest = smoothstep(0.42, 0.95, steep);
}

void fragment() {
	// 물가. 여기서 자르지 않으면 바다가 해안선을 지나 뭍 위까지 깔린다.
	if (land_stands_at(world_pos.xz)) {
		discard;
	}
	float dist = length(VERTEX);
	float t = TIME;

	// ── 잔결. 주기가 서로 안 맞는 세 배율을 각각 다른 각도로 겹쳐 타일 무늬를 깬다
	float f1 = clamp(1.0 - dist / 2600.0, 0.0, 1.0);
	float f2 = clamp(1.0 - dist / 900.0, 0.0, 1.0);
	float f3 = clamp(1.0 - dist / 260.0, 0.0, 1.0);

	vec3 r1 = texture(ripple_normals, rot2(world_pos.xz, 0.0) / 41.0
		+ vec2(t * 0.008, t * 0.005)).xyz * 2.0 - 1.0;
	vec3 r2 = texture(ripple_normals, rot2(world_pos.xz, 0.93) / 13.7
		- vec2(t * 0.017, t * 0.011)).xyz * 2.0 - 1.0;
	vec3 r3 = texture(ripple_normals, rot2(world_pos.xz, -1.71) / 4.3
		+ vec2(t * 0.031, -t * 0.024)).xyz * 2.0 - 1.0;

	vec2 tilt = r1.xz * 0.20 * f1 + r2.xz * 0.15 * f2 + r3.xz * 0.11 * f3;

	// 법선을 둘로 나눈다.
	//
	// 잔결을 그대로 색에 먹이면 물결 하나하나가 하늘을 통째로 비춰서
	// 바다가 아니라 파랑-하양 레이스가 된다. 실제로는 그 잔결이 만드는 건
	// 색이 아니라 반짝임이다. 그래서 색은 큰 물결만 보고, 반짝임만 잔결까지 본다.
	vec3 n_fine = normalize(wave_normal + vec3(tilt.x, 0.0, tilt.y));
	vec3 n_body = normalize(wave_normal + vec3(tilt.x, 0.0, tilt.y) * 0.26);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_fine, 0.0)).xyz);

	vec3 view_dir = normalize(-VERTEX);
	vec3 nv = normalize((VIEW_MATRIX * vec4(n_body, 0.0)).xyz);

	// ── 프레넬. 내려다보면 물속이 보이고, 스칠수록 하늘을 비춘다.
	// 멀수록 물결이 잘게 흩어져 거울 노릇을 못 하므로 반사를 눌러준다.
	// 이걸 안 눌러서 수평선이 하늘보다 밝아졌었다.
	// 거리에 따라 두 가지가 따로 사그라든다.
	//  - 반짝임(glint)은 금방 죽는다. 멀면 화면 한 점에 물결 수천 개가 겹쳐
	//    서로 상쇄되기 때문이다. 이게 안 죽어서 중거리에 흰 띠가 생겼다.
	//  - 하늘을 비추는 힘(grazing)은 멀리까지 살아 있어야 한다. 수평선의 바다는
	//    실제로 하늘의 절반쯤 밝다. 이걸 같이 죽였더니 수평선만 새까매졌다.
	float grazing = clamp(dist / 1300.0, 0.0, 1.0);
	float glint_fade = clamp(dist / 450.0, 0.0, 1.0);
	float f = clamp(dot(nv, view_dir), 0.0, 1.0);
	float fres = (0.02 + 0.98 * pow(1.0 - f, 5.0)) * mix(1.0, 0.75, grazing);

	vec3 refl_dir = reflect(-view_dir, nv);
	vec3 world_refl = (INV_VIEW_MATRIX * vec4(refl_dir, 0.0)).xyz;
	// 물에 비친 하늘은 하늘 자체보다 조금 어둡다
	vec3 sky = sky_color(world_refl) * 0.78;

	vec3 body = mix(deep_color, shallow_color, clamp(1.0 - f * 0.85, 0.0, 1.0));
	// 물마루가 얇아지면 빛이 통과해 속이 비친다
	body += sss_color * crest * 0.5 * f2;

	// ── 뱃머리가 가르는 물살. 켈빈 항적처럼 뒤로 벌어지는 V.
	vec2 rel = world_pos.xz - ship_pos;
	float along = dot(rel, ship_dir);
	float side = dot(rel, vec2(-ship_dir.y, ship_dir.x));
	float wake = 0.0;
	if (along < 6.0 && ship_speed01 > 0.01) {
		float back = max(0.0, -along);
		// 배 바로 뒤에 휘저어진 물. 좁게 시작해 천천히 벌어지고 금세 잦아든다.
		float churn = exp(-pow(abs(side) / (4.5 + back * 0.075), 2.0)) * exp(-back / 34.0);
		// 좌우로 벌어지는 두 팔. 이건 선이라서 가늘어야 팔로 보인다.
		float arm = abs(abs(side) - 2.5 - back * 0.30);
		float arms = exp(-arm * 0.85) * exp(-back / 90.0) * 0.55;
		wake = (churn * 0.7 + arms) * ship_speed01;
		// 고르게 칠하면 페인트로 보인다. 굵게 한 번, 잘게 한 번 얼룩을 준다.
		float churny = vnoise(world_pos.xz * 0.55 + vec2(t * 0.15, 0.0))
			* 0.65 + vnoise(world_pos.xz * 2.1 - vec2(0.0, t * 0.4)) * 0.35;
		wake *= 0.35 + 0.85 * churny;
	}

	// ── 거품. 고르게 칠하면 페인트로 보이므로 얼룩덜룩하게.
	float patch = vnoise(world_pos.xz * 0.7);
	float foam = crest * smoothstep(0.25, 0.8, patch + crest * 0.35);
	foam = clamp(foam + wake, 0.0, 0.75);

	// ── 물빛은 두 갈래다.
	//
	// 물속에서 나오는 빛과 거품은 재질이라 햇빛을 받아야 하지만(ALBEDO),
	// 표면에 비친 하늘은 이미 빛 그 자체라 다시 비추면 안 된다(EMISSION).
	// 비친 하늘까지 ALBEDO 에 넣고 있었다. 그래서 해와 하늘빛을 한 번 더 받아
	// 두 번 밝아졌고, 프레넬이 큰 먼바다일수록 그 배수가 커졌다.
	// 먼바다가 하늘만큼 밝았던 가장 큰 이유가 이것이다.
	ALBEDO = mix(body, foam_color, foam);
	EMISSION = sky * fres * (1.0 - foam);

	// 가까이는 거울처럼, 멀리는 잘게 흩어지게. 이 경사가 흰 수평선을 막는다.
	// 너무 매끈하면 해가 물결마다 통째로 비쳐 하얀 레이스가 깔린다.
	ROUGHNESS = mix(mix(0.20, 0.62, foam), 0.55, glint_fade);
	METALLIC = 0.0;
	// 가까운 물결은 거울처럼 해를 튕기지만, 먼 물결은 화면 한 점에 수천 개가
	// 겹쳐 서로 상쇄된다. 이걸 안 줄이면 해가 낮을 때 수평선 전체가 반짝임 길이 된다.
	SPECULAR = mix(0.42, 0.0, glint_fade);
}
