shader_type sky;

// 하늘. 색은 sky_common 의 식이 만들고, 여기서는 해와 달의 원반만 얹는다.
// 바다도 같은 식을 보므로 물에 비친 하늘이 실제 하늘과 어긋나지 않는다.

#include "res://shaders/sky_common.gdshaderinc"

// cos(반지름). 실제 해와 달은 반지름 0.27도로, 새끼손톱 끝만 하다.
// 해는 조금만 키운다 — 많이 키우면 곧바로 가짜로 보인다.
// 달은 눈에 남는 크기가 실제보다 훨씬 크므로 두 배 반 넘게 키웠다.
uniform float sun_size = 0.9999756;    // 반지름 0.40도
uniform float moon_size = 0.9999210;   // 반지름 0.72도

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = sky_color(dir);

	float day = clamp((sun_alt + 0.09) / 0.30, 0.0, 1.0);

	// 해 원반. 지평에 걸리면 붉어지고 커 보인다.
	float cs = dot(dir, sun_dir);
	float low = 1.0 - clamp(sun_alt, 0.0, 1.0);
	float disc = smoothstep(sun_size - 0.0000090, sun_size + 0.0000010, cs);
	vec3 disc_tint = mix(sun_tint, dusk_color, low * low * 0.9);
	// 원반을 후광보다 확실히 밝게 둬야 무리에 잡아먹히지 않는다
	col += disc_tint * disc * mix(6.0, 26.0, day);

	// 달 원반
	float cm = dot(dir, moon_dir);
	float mdisc = smoothstep(moon_size - 0.0000260, moon_size + 0.0000030, cm);
	col += moon_tint * mdisc * 3.2 * moon_up * (1.0 - day * 0.85);

	COLOR = col;
}
