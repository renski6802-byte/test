shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled, shadows_disabled;

// 바다에서 본 육지.
//
// 메시는 축척 없는 지리 미터로 만들어져 있다. 여기 정점 셰이더에서 배를 중심으로
// 눌러 놓는다. 상수 배율이 아니라 거리에 따라 다른 배율이다.
//
// 상수로 누르면 육지가 배보다 열다섯 배 빨리 다가온다. 바다는 1/370 인데 육지는
// 1/25 이라, 배가 물 위로 10m 미끄러지는 동안 해안은 148m 다가오기 때문이다.
// 그래서 물가가 미끄러지듯 밀려든다.
//
// 가까운 곳은 바다에 가깝게 눌러 배와 같은 속도로 다가오게 하고, 먼 곳은
// 느슨하게 눌러 해안이 보이게 한다. 그 사이를 부드럽게 잇는다.
// 비탈이 무너지지 않도록 높이도 그 자리의 가로 배율을 따라간다.

#include "res://shaders/sky_common.gdshaderinc"
// 축척과 그 역함수는 바다 셰이더와 나눠 쓴다. 둘이 어긋나면 물가가 어긋난다.
#include "res://shaders/land_cut.gdshaderinc"

uniform sampler2D grain : hint_default_white, filter_linear_mipmap, repeat_enable;

// 물가가 파도에 잠기지 않게 깔아주는 바닥선.
//
// 물가 육지는 눌려서 3km 앞 해안이 겨우 1~2m 가 되는데, 파도 마루도
// 그만큼이라 바다가 육지를 뚫고 올라온다. 실제 높이가 floor_ref_m 을 넘는
// 땅은 반드시 물 위 floor_rise_m 이상에 서게 한다.
uniform float floor_rise_m = 3.2;
uniform float floor_ref_m = 12.0;
// 먼 해안은 상수 바닥선으로는 모자란다. 3.2m 는 300m 밖에서 0.6도라
// 파도에 묻힌다. 그래서 거리에 비례하는 몫을 함께 두어, 아무리 멀어도
// 이 각도(라디안)보다는 크게 선다.
uniform float floor_angle = 0.018;

// 높이 = 그 자리의 가로배율 × 이 값.
//
// 가까운 쪽과 먼 쪽에 다른 값을 준다. 하나로 묶으면 둘 중 하나가 망가진다 —
// 물가가 프레임을 다 먹지 않게 낮추면 안쪽 산줄기까지 눌려 하늘금이 자로 그은
// 듯 반듯해지고, 산줄기를 세우면 물가가 눈앞의 벽이 된다.
uniform float slope_ease = 2.6;       // 물가
uniform float slope_ease_far = 3.4;   // 안쪽 · 먼 해안
uniform float haze_km = 32.0;
// 파도선이 닿는 실제 높이(m). 넓게 잡으면 물가가 통째로 하얘져
// 모래해안과 물거품이 같은 색이 된다.
uniform float surf_m = 4.0;
uniform float wave_time = 0.0;

uniform vec3 sand_color : source_color = vec3(0.50, 0.45, 0.34);
uniform vec3 grass_color : source_color = vec3(0.31, 0.36, 0.21);
uniform vec3 rock_color : source_color = vec3(0.42, 0.39, 0.34);
uniform vec3 rock_dark : source_color = vec3(0.29, 0.27, 0.24);
uniform vec3 surf_color : source_color = vec3(0.93, 0.95, 0.94);

varying vec2 geo_xz;      // 지리 좌표(m). 무늬는 여기에 입힌다.
varying float geo_h;      // 실제 높이(m)
varying vec3 geo_nrm;     // 실제 지형의 법선
varying float geo_dist;   // 배에서의 지리 거리(m)

void vertex() {
	geo_xz = VERTEX.xz;
	geo_h = VERTEX.y;
	geo_nrm = normalize(NORMAL);

	vec2 d = VERTEX.xz - ship_geo;
	geo_dist = length(d);
	float s = land_scale_at(geo_dist);
	float t = smoothstep(blend_near_m, blend_far_m, geo_dist);
	float ease = mix(slope_ease, slope_ease_far, t);
	// 눌린 높이와 바닥선 중 높은 쪽. 물가에서는 바닥선이, 안쪽에서는
	// 실제 지형이 이긴다.
	float floor_m = max(floor_rise_m, geo_dist * s * floor_angle);
	float lift = floor_m * smoothstep(0.0, floor_ref_m, VERTEX.y);
	VERTEX = vec3(d.x * s, max(VERTEX.y * s * ease, lift), d.y * s);
}

void fragment() {
	vec3 n = normalize(geo_nrm);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);      // 0 평지 … 1 절벽

	// ── 잔결. 서로 안 맞는 세 배율을 겹쳐 타일 무늬를 깬다.
	vec3 g1 = texture(grain, geo_xz / 2600.0).rgb;
	vec3 g2 = texture(grain, geo_xz / 620.0).rgb;
	vec3 g3 = texture(grain, geo_xz / 140.0).rgb;
	float rough_n = g1.r * 0.55 + g2.g * 0.30 + g3.b * 0.15;

	// ── 바위인가 풀인가 모래인가.
	float rocky = clamp(COLOR.r * 0.55 + smoothstep(0.20, 0.58, slope), 0.0, 1.0);
	rocky = clamp(rocky + (rough_n - 0.5) * 0.35, 0.0, 1.0);
	float sandy = (1.0 - smoothstep(8.0, 40.0, geo_h)) * (1.0 - smoothstep(0.08, 0.24, slope));

	// ── 층리. 경사가 급한 자리에만 긋는다.
	// 온 땅에 그으면 완만한 곳이 등고선 테라스가 된다.
	float band = sin(geo_h * 0.42 + (g2.r - 0.5) * 3.4);
	float strata = smoothstep(0.30, 0.62, slope);
	vec3 rock = mix(rock_color,
		mix(rock_dark, rock_color, smoothstep(-0.35, 0.35, band)), strata);
	rock = mix(rock, rock * 1.10, g3.r);

	vec3 col = mix(grass_color * (0.72 + 0.56 * rough_n), rock, rocky);
	col = mix(col, sand_color * (0.82 + 0.36 * g2.b), sandy * (1.0 - rocky * 0.7));

	// ── 물가의 흰 파도선. 밀려왔다 빠지는 만큼 높이가 오르내린다.
	float tide = 0.62 + 0.38 * sin(wave_time * 0.9 + geo_xz.x * 0.0016 + geo_xz.y * 0.0011);
	float surf = 1.0 - smoothstep(0.0, surf_m * tide, geo_h);
	surf *= smoothstep(0.55, 0.15, slope);          // 절벽에는 안 걸린다
	surf *= 0.45 + 0.55 * g3.g;
	col = mix(col, surf_color, clamp(surf, 0.0, 0.55));

	// ── 대기 원근. 지리 거리로 직접 건다.
	float haze = 1.0 - exp(-(geo_dist * 0.001) / max(haze_km, 1.0));
	vec3 look = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	vec3 air = sky_color(look) * 0.92;

	ALBEDO = mix(col, air, clamp(haze * 0.95, 0.0, 0.95));
	// 빛은 진짜 지형의 법선으로 받는다. 눌린 법선으로 받으면 빛을 스치듯 받아
	// 새까매진다. 눌린 세계는 그리기 위한 장치일 뿐이다.
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.96, 0.72, rocky) * (1.0 - surf * 0.35);
	SPECULAR = mix(0.08, 0.24, surf);
	METALLIC = 0.0;
}
