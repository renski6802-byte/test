shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled, shadows_disabled;

// 바다에서 본 육지.
//
// 형태는 CoastMesh 가 깎아서 넘겨준다. 여기서는 그 위에 표면을 만든다 —
// 높이와 경사에 따라 바위·풀·모래가 섞이고, 물가에는 흰 파도선이 서고,
// 멀어질수록 하늘빛에 잠긴다.
//
// 안개는 환경 안개로 못 한다. 육지는 바다와 다른 축척(1/25)이라 26km 앞의
// 해안이 세계 좌표로는 1km 밖에 안 되기 때문이다. 그래서 여기서 지리 거리로
// 되돌려 직접 건다.

#include "res://shaders/sky_common.gdshaderinc"

uniform sampler2D grain : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float land_scale = 0.04;      // 세계 거리를 지리 거리로 되돌리는 값
uniform float height_scale = 0.125;   // 높이에 걸린 축척. 실제 미터로 되돌릴 때 쓴다
uniform float haze_km = 32.0;         // 이 거리에서 절반쯤 하늘빛에 잠긴다
uniform float surf_top = 0.7;         // 파도선이 닿는 높이(세계 미터)
uniform float wave_time = 0.0;

uniform vec3 sand_color : source_color = vec3(0.72, 0.66, 0.50);
uniform vec3 grass_color : source_color = vec3(0.31, 0.36, 0.21);
uniform vec3 rock_color : source_color = vec3(0.42, 0.39, 0.34);
uniform vec3 rock_dark : source_color = vec3(0.29, 0.27, 0.24);
uniform vec3 surf_color : source_color = vec3(0.93, 0.95, 0.94);

varying vec3 world_pos;
varying vec3 world_nrm;   // 빛을 받는 법선(눌린 세계 기준)
varying vec3 geo_nrm;     // 실제 지형의 법선(누르기 전)
varying float kind_rock;   // 0 모래·풀 … 1 바위
varying float geo_h;       // 실제 높이(m)

vec3 grain3(vec2 p, float s) {
	return texture(grain, p / s).rgb;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	geo_nrm = normalize(NORMAL);
	// 가로만 눌린 행렬이다. 법선을 그냥 곱하면 x·z 가 같이 줄어 경사가 사라지고
	// 온 땅이 평지가 된다. 축척의 역수를 먹여야 눌린 만큼 가팔라진 법선이 나온다.
	world_nrm = normalize(vec3(NORMAL.x / land_scale, NORMAL.y, NORMAL.z / land_scale));
	kind_rock = COLOR.r;
	geo_h = VERTEX.y / max(height_scale, 1e-4);
}

void fragment() {
	// 지리 좌표로 되돌려서 무늬를 입힌다. 그래야 축척을 바꿔도 무늬 크기가 안 변한다.
	vec2 gp = world_pos.xz / max(land_scale, 1e-5);

	vec3 n = normalize(world_nrm);
	// 바위냐 풀이냐는 실제 지형의 경사로 정한다. 눌린 법선으로 정하면
	// 어디나 절벽이 되어 온 땅이 바위가 된다.
	float slope = 1.0 - clamp(normalize(geo_nrm).y, 0.0, 1.0);

	// ── 잔결. 서로 안 맞는 세 배율을 겹쳐 타일 무늬를 깬다.
	vec3 g1 = grain3(gp, 2600.0);
	vec3 g2 = grain3(gp, 620.0);
	vec3 g3 = grain3(gp, 140.0);
	float rough_n = g1.r * 0.55 + g2.g * 0.30 + g3.b * 0.15;

	// ── 바위인가 풀인가 모래인가.
	// 가파르면 바위가 드러나고, 낮고 평평하면 모래가 깔린다.
	float rocky = clamp(kind_rock * 0.55 + smoothstep(0.18, 0.55, slope), 0.0, 1.0);
	rocky = clamp(rocky + (rough_n - 0.5) * 0.35, 0.0, 1.0);
	float sandy = (1.0 - smoothstep(6.0, 34.0, geo_h)) * (1.0 - smoothstep(0.10, 0.30, slope));

	// ── 절벽면의 층리. 실제 높이를 기준으로 그어야 층이 수평으로 눕는다.
	float band = sin(geo_h * 0.42 + (g2.r - 0.5) * 3.4);
	vec3 rock = mix(rock_dark, rock_color, smoothstep(-0.35, 0.35, band));
	rock = mix(rock, rock * 1.12, g3.r);

	vec3 col = mix(grass_color * (0.72 + 0.56 * rough_n), rock, rocky);
	col = mix(col, sand_color * (0.82 + 0.36 * g2.b), sandy * (1.0 - rocky * 0.7));

	// ── 물가의 흰 파도선. 밀려왔다 빠지는 만큼 높이가 오르내린다.
	float tide = 0.62 + 0.38 * sin(wave_time * 0.9 + gp.x * 0.0016 + gp.y * 0.0011);
	float surf = 1.0 - smoothstep(0.0, surf_top * tide, world_pos.y);
	surf *= smoothstep(0.55, 0.15, slope);          // 절벽에는 안 걸린다
	surf *= 0.45 + 0.55 * g3.g;                     // 고르게 칠하면 페인트로 보인다
	col = mix(col, surf_color, clamp(surf, 0.0, 0.85));

	// ── 대기 원근. 지리 거리로 되돌려 건다.
	float geo_km = length(VERTEX) / max(land_scale, 1e-5) * 0.001;
	float haze = 1.0 - exp(-geo_km / max(haze_km, 1.0));
	vec3 look = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	// 하늘과 같은 식을 보므로 육지가 물러나는 색이 하늘과 어긋나지 않는다
	vec3 air = sky_color(look) * 0.92;

	ALBEDO = mix(col, air, clamp(haze * 0.95, 0.0, 0.95));
	// 빛은 실제 지형의 법선으로 받는다. 눌린 법선으로 받으면 온 땅이 빛을
	// 스치듯 받아 새까매진다. 눌린 세계는 그리기 위한 장치일 뿐이므로,
	// 빛만은 진짜 땅처럼 받아야 땅으로 보인다.
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(geo_nrm), 0.0)).xyz);
	ROUGHNESS = mix(0.96, 0.72, rocky) * (1.0 - surf * 0.35);
	SPECULAR = mix(0.08, 0.28, surf);
	METALLIC = 0.0;
}
