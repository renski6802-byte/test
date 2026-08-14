// 육지와 바다를 나누는 일. 육지 셰이더와 바다 셰이더가 함께 본다.
//
// 왜 이런 게 필요하냐면 — 바다와 육지가 서로 다른 축척으로 그려지기 때문이다.
// 바다는 1/370, 육지는 물가에서 1/40, 먼 쪽은 1/25. 그래서 바다 판은 해안선을
// 지나쳐 뭍 위까지 통째로 깔리고, 겨우 1~2m 로 눌린 육지를 파도 마루가 뚫고
// 올라온다. 육지가 물거품 조각처럼 흩어져 보이던 것이 그것이다.
//
// 여기서는 바다 조각 하나하나에 대고 "이 자리에 그려질 육지는 어디인가" 를
// 되물어, 뭍이면 바다를 안 그린다. 되묻는 일이 곧 축척의 역함수다.

uniform vec2 ship_geo = vec2(0.0);    // 배의 자리(축척 없는 지리 미터)
uniform vec2 ship_world = vec2(0.0);  // 배의 자리(그려지는 세계 미터)

uniform float near_scale = 0.025;     // 1/40. 물가 코앞의 배율
uniform float far_scale = 0.04;       // 1/25. 먼 쪽 배율
uniform float blend_near_m = 2000.0;
uniform float blend_far_m = 18000.0;

// 해안선. Geo.gd 의 poly_iberia / poly_africa 를 그대로 받는다(경위도).
uniform vec2 coast_ib[37];
uniform vec2 coast_af[16];
uniform vec2 geo_origin = vec2(-8.1, 36.5);   // ORIGIN_LON, ORIGIN_LAT
uniform float km_lat = 111.19;

// 높이에 먹이는 값. 물가와 안쪽이 다르다 — land.gdshader 의 주석 참고.
uniform float slope_ease = 2.6;
uniform float slope_ease_far = 3.4;

float land_scale_at(float r) {
	return mix(near_scale, far_scale, smoothstep(blend_near_m, blend_far_m, r));
}

float land_ease_at(float r) {
	return mix(slope_ease, slope_ease_far, smoothstep(blend_near_m, blend_far_m, r));
}

// 지리 좌표의 한 점을 그려지는 자리로 옮긴다.
//
// 땅 위에 세우는 것은 무엇이든 이 함수를 거쳐야 한다. 등대가 지형과 다른
// 식으로 눌리면 절벽 옆이 아니라 허공에 뜬다.
vec3 warp_land(vec2 geo_xz, float h) {
	vec2 d = geo_xz - ship_geo;
	float r = length(d);
	float s = land_scale_at(r);
	return vec3(d.x * s, h * s * land_ease_at(r), d.y * s);
}

// 그려진 거리 R 을 주면 원래 지리 거리 r 을 돌려준다.
// R(r) = r · s(r) 는 r 에 대해 단조증가라 이분법으로 안전하게 뒤집힌다.
float geo_r_of_drawn(float R) {
	float lo = 0.0;
	float hi = 400000.0;
	for (int i = 0; i < 14; i++) {
		float mid = (lo + hi) * 0.5;
		if (mid * land_scale_at(mid) < R) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	return (lo + hi) * 0.5;
}

// 축척 없는 지리 미터 → 경위도. Geo.geo_of_metres 와 같은 식이어야 한다.
vec2 geo_of_metres(vec2 p) {
	float lat = geo_origin.y + (-p.y) / (km_lat * 1000.0);
	float lon = geo_origin.x + p.x / (111.32 * cos(radians(lat)) * 1000.0);
	return vec2(lon, lat);
}

// 짝홀 규칙. Geo.in_poly 와 같은 식이어야 물가가 어긋나지 않는다.
bool in_coast_ib(vec2 g) {
	bool inside = false;
	int n = coast_ib.length();
	int j = n - 1;
	for (int i = 0; i < n; i++) {
		vec2 pi = coast_ib[i];
		vec2 pj = coast_ib[j];
		if ((pi.y > g.y) != (pj.y > g.y)) {
			if (g.x < (pj.x - pi.x) * (g.y - pi.y) / (pj.y - pi.y) + pi.x) {
				inside = !inside;
			}
		}
		j = i;
	}
	return inside;
}

bool in_coast_af(vec2 g) {
	bool inside = false;
	int n = coast_af.length();
	int j = n - 1;
	for (int i = 0; i < n; i++) {
		vec2 pi = coast_af[i];
		vec2 pj = coast_af[j];
		if ((pi.y > g.y) != (pj.y > g.y)) {
			if (g.x < (pj.x - pi.x) * (g.y - pi.y) / (pj.y - pi.y) + pi.x) {
				inside = !inside;
			}
		}
		j = i;
	}
	return inside;
}

// 그려지는 세계의 이 자리에는 뭍이 서 있는가.
bool land_stands_at(vec2 world_xz) {
	vec2 d = world_xz - ship_world;
	float R = length(d);
	if (R < 0.001) {
		return false;
	}
	vec2 g = geo_of_metres(ship_geo + (d / R) * geo_r_of_drawn(R));
	return in_coast_ib(g) || in_coast_af(g);
}
