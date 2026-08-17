shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled, shadows_disabled;

// 땅 위에 선 것들 — 등대, 망루, 마을.
//
// 메시는 육지와 똑같이 축척 없는 지리 미터로 만들어져 있고, 여기서 land.gdshader
// 와 같은 함수(warp_land)로 눌러 놓는다. 다른 식으로 누르면 등대가 절벽 옆이
// 아니라 허공에 뜬다. 그래서 그 함수는 둘이 나눠 쓰는 include 에 있다.

#include "res://shaders/sky_common.gdshaderinc"
#include "res://shaders/land_cut.gdshaderinc"

// 가로도 세로와 같은 값으로 부풀린다.
//
// 세로는 지형처럼 land_ease(2.6배)를 먹는데 가로가 그대로면 탑이 2.6배
// 홀쭉해진다. 그래서 가로에도 같은 값을 준다 — 모양이 그대로 유지된다.
//
// 여기에 8 을 줬더니 반대가 됐다. 멀리서는 그럭저럭이었지만 가까이 가니
// 망루가 탑이 아니라 물통이었다. 눈에 걸리게 하는 것은 굵기가 아니라 크기고,
// 크기는 Landmarks.gd 에서 실물보다 크게 잡는 것으로 이미 하고 있다.
uniform float girth = 2.6;

uniform float haze_km = 95.0;
uniform float haze_max = 0.80;

// 구워둔 재질. 한 메시에 회벽·기와·돌이 섞여 있으므로 어느 것을 쓸지는
// 정점이 COLOR.a 에 실어 보낸다 — 0 회벽, 0.5 기와, 1 돌.
uniform sampler2D stucco_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stucco_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 geo_nrm;
varying float geo_dist;
varying vec3 tint;
varying float kind;
varying vec2 skin;

void vertex() {
	// COLOR 에 그 물건의 색을 실어 보낸다. 여러 채를 메시 하나에 담기 때문이다.
	tint = COLOR.rgb;
	kind = COLOR.a;
	skin = UV;
	geo_nrm = normalize(NORMAL);

	// UV2.x 에 그 물건이 선 자리(지리)를 담아두면 좋겠지만 vec2 하나로는
	// 모자라, 밑동의 지리 좌표를 UV2 에 실어 보낸다. 정점의 지리 좌표에서
	// 밑동을 뺀 것이 그 물건 안에서의 자리다.
	vec2 base_geo = UV2;
	vec2 local = VERTEX.xz - base_geo;

	geo_dist = length(base_geo - ship_geo);
	// 밑동은 지형과 똑같이 눌러 자리를 잡고,
	vec3 w = warp_land(base_geo, VERTEX.y);
	// 그 자리에서 제 몸을 가로로만 부풀려 세운다.
	float s = land_scale_at(geo_dist);
	VERTEX = vec3(w.x + local.x * s * girth, w.y, w.z + local.y * s * girth);
}

void fragment() {
	// 셋 중 하나를 고른다. 분기 대신 섞는다 — 어차피 값이 0 · 0.5 · 1 이라
	// 가중치가 하나만 살아남는다.
	float w_tile = 1.0 - min(abs(kind - 0.5) * 2.0, 1.0);
	float w_rock = smoothstep(0.5, 1.0, kind);
	float w_stu = max(0.0, 1.0 - w_tile - w_rock);

	vec3 skin_col = texture(stucco_tex, skin).rgb * w_stu
		+ texture(tile_tex, skin).rgb * w_tile
		+ texture(rock_tex, skin).rgb * w_rock;
	vec3 skin_n = texture(stucco_nrm, skin).rgb * w_stu
		+ texture(tile_nrm, skin).rgb * w_tile
		+ texture(rock_nrm, skin).rgb * w_rock;

	float haze = 1.0 - exp(-(geo_dist * 0.001) / max(haze_km, 1.0));
	vec3 look = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	vec3 air = sky_color(look) * 0.92;

	// 재질이 색을 내고 tint 는 색기만 얹는다(붉은 띠, 이끼 낀 벽 따위).
	ALBEDO = mix(skin_col * tint, air, clamp(haze, 0.0, haze_max));

	// 접선이 없는 메시라 세로축을 접선으로 삼는다. 벽은 대체로 서 있는
	// 면이라 이걸로 충분하다. 멀어지면 지운다 — 지글거림을 막는다.
	vec3 b = skin_n * 2.0 - 1.0;
	float k = 0.7 * (1.0 - smoothstep(900.0, 6000.0, geo_dist));
	vec3 n = normalize(geo_nrm + vec3(b.x, b.y, 0.0) * k);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.92, 0.78, w_tile);
	SPECULAR = 0.1;
	METALLIC = 0.0;
}
