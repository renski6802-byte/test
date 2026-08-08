shader_type spatial;
render_mode specular_schlick_ggx;

// 배 주위의 바다.
//
// 바다를 바다로 보이게 하는 건 파도의 크기가 아니라 겹의 수다.
// 긴 너울 위에 중간 물결이, 그 위에 잔결이 얹혀야 물처럼 읽힌다.
// 그래서 형태는 거스너 여섯 겹으로 만들고, 그보다 작은 결은 법선만 흔들어 얹는다.
//
// 여기 여섯 겹은 scripts/Ocean.gd 의 WAVES 와 반드시 같아야 한다.
// 배가 파도를 타려면 CPU 가 같은 높이를 계산할 수 있어야 하기 때문이다.

uniform vec3 deep_color : source_color = vec3(0.008, 0.032, 0.055);
uniform vec3 shallow_color : source_color = vec3(0.045, 0.135, 0.160);
uniform vec3 sky_horizon : source_color = vec3(0.62, 0.74, 0.84);
uniform vec3 sky_zenith : source_color = vec3(0.24, 0.45, 0.72);
uniform vec3 foam_color : source_color = vec3(0.90, 0.94, 0.95);
uniform vec3 sss_color : source_color = vec3(0.09, 0.36, 0.32);
uniform float choppiness = 1.0;
uniform float half_extent = 3000.0;
uniform float fade_dist = 30000.0;
uniform sampler2D ripple_normals : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;
varying vec3 wave_normal;
varying float crest;

// ── 형태를 만드는 여섯 겹 ────────────────────────────────────────
// dir, 파장(m), 진폭(m), 뾰족함
const vec2 DIRS[6] = { vec2(1.00, 0.15), vec2(0.85, 0.50), vec2(-0.50, 1.00),
					   vec2(0.30, -1.00), vec2(-1.00, -0.35), vec2(0.60, 0.80) };
const float LENS[6] = { 140.0, 78.0, 44.0, 25.0, 13.0, 7.0 };
const float AMPS[6] = { 0.90, 0.55, 0.32, 0.18, 0.090, 0.045 };
const float QS[6]   = { 0.35, 0.40, 0.45, 0.50, 0.50, 0.50 };

void gerstner(vec2 p, float t, float gain, out vec3 disp, out vec3 nrm, out float steep) {
	disp = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	steep = 0.0;

	for (int i = 0; i < 6; i++) {
		vec2 d = normalize(DIRS[i]);
		float k = 6.2831853 / LENS[i];
		float a = AMPS[i] * choppiness * gain;
		float q = QS[i];
		float ph = k * dot(d, p) - sqrt(9.81 * k) * t;
		float c = cos(ph);
		float s = sin(ph);

		disp.xz += d * (q * a * c);
		disp.y += a * s;

		// 거스너의 해석적 법선. 유한차분보다 훨씬 싸다.
		float wa = k * a;
		n.x -= d.x * wa * c;
		n.z -= d.y * wa * c;
		n.y -= q * wa * s;

		steep += wa * s;
	}
	nrm = normalize(n);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 판 가장자리에서 파도를 접는다. 먼바다 판과 이어붙는 자리라 어긋나면 안 된다.
	float edge = 1.0 - smoothstep(half_extent * 0.70, half_extent * 0.97,
		max(abs(VERTEX.x), abs(VERTEX.z)));

	vec3 disp;
	vec3 nrm;
	float steep;
	gerstner(wp.xz, TIME, edge, disp, nrm, steep);

	VERTEX += disp;
	world_pos = wp + disp;
	wave_normal = nrm;

	// 거품은 높이가 아니라 가파름에서 난다. 물마루가 무너지는 자리다.
	crest = smoothstep(0.55, 1.15, steep);
}

void fragment() {
	float dist = length(VERTEX);

	// 잔결은 가까울수록만. 멀리까지 얹으면 수평선이 지글거린다.
	float fine = clamp(1.0 - dist / 1400.0, 0.0, 1.0);
	float t = TIME;
	vec3 r1 = texture(ripple_normals, world_pos.xz / 26.0 + vec2(t * 0.010, t * 0.007)).xyz * 2.0 - 1.0;
	vec3 r2 = texture(ripple_normals, world_pos.xz / 7.5 - vec2(t * 0.021, t * 0.014)).xyz * 2.0 - 1.0;
	vec2 tilt = (r1.xz * 0.45 + r2.xz * 0.28) * fine;
	vec3 n = normalize(wave_normal + vec3(tilt.x, 0.0, tilt.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	vec3 view_dir = normalize(-VERTEX);
	vec3 nv = normalize(NORMAL);

	// 프레넬 — 내려다보면 물속이 보이고, 스칠수록 하늘을 비춘다.
	// 이 한 줄이 물을 물로 보이게 하는 가장 큰 몫이다.
	float f = clamp(dot(nv, view_dir), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - f, 5.0);

	// 비치는 하늘. 위를 볼수록 천정색.
	vec3 refl_dir = reflect(-view_dir, nv);
	vec3 world_refl = (INV_VIEW_MATRIX * vec4(refl_dir, 0.0)).xyz;
	vec3 sky = mix(sky_horizon, sky_zenith, clamp(world_refl.y * 1.6, 0.0, 1.0));

	vec3 body = mix(deep_color, shallow_color, clamp(1.0 - f * 0.85, 0.0, 1.0));

	// 물마루가 얇아지면 빛이 통과해 속이 비친다
	float sss = crest * 0.55 + smoothstep(0.2, 1.0, world_pos.y * 0.5) * 0.25;

	vec3 col = mix(body, sky, fres);
	col += sss_color * sss * fine;

	// 거품은 얼룩덜룩해야 한다. 고르게 칠하면 페인트로 보인다.
	float patch = hash(floor(world_pos.xz * 0.7));
	float foam = crest * smoothstep(0.25, 0.8, patch + crest * 0.35);
	col = mix(col, foam_color, clamp(foam, 0.0, 0.85));

	// 수평선으로 갈수록 대기에 잠긴다
	float far = clamp(dist / fade_dist, 0.0, 1.0);
	ALBEDO = mix(col, sky_horizon, far * 0.75);

	// 낮은 거칠기라야 해가 잘게 부서져 윤슬이 생긴다
	ROUGHNESS = mix(mix(0.035, 0.55, foam), 0.35, far);
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
