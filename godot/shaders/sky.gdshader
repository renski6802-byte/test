shader_type sky;

// 하늘. 색은 sky_common 의 식이 만들고, 여기서는 해와 달의 원반만 얹는다.
// 바다도 같은 식을 보므로 물에 비친 하늘이 실제 하늘과 어긋나지 않는다.

#include "res://shaders/sky_common.gdshaderinc"

uniform float sun_size = 0.99999;   // cos(반지름). 해의 실제 반지름은 0.27도다.
uniform float moon_size = 0.99999;

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = sky_color(dir);

	float day = clamp((sun_alt + 0.09) / 0.30, 0.0, 1.0);

	// 해 원반. 지평에 걸리면 붉어지고 커 보인다.
	float cs = dot(dir, sun_dir);
	float low = 1.0 - clamp(sun_alt, 0.0, 1.0);
	float disc = smoothstep(sun_size - 0.000018, sun_size + 0.000002, cs);
	vec3 disc_tint = mix(sun_tint, dusk_color, low * low * 0.9);
	col += disc_tint * disc * mix(3.0, 12.0, day);

	// 달 원반
	float cm = dot(dir, moon_dir);
	float mdisc = smoothstep(moon_size - 0.000016, moon_size + 0.000002, cm);
	col += moon_tint * mdisc * 2.2 * moon_up * (1.0 - day * 0.85);

	COLOR = col;
}
