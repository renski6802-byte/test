// 하늘빛을 만드는 식. 하늘과 바다가 **같은 식 하나**를 본다.
//
// 물빛의 절반은 비친 하늘이다. 전에는 물이 sky_horizon·sky_zenith 두 색만 아는
// 근사치를 보고 있어서 실제 하늘과 맞을 수가 없었다. 게다가 그 근사치는 사방이
// 똑같아서, 비칠 대상이 균일하니 물도 균일해졌다.
//
// 여기서 방향을 아는 하늘을 만든다. 해 쪽은 허옇게 뜨고, 해에서 90도 떨어진
// 쪽이 가장 짙고, 새벽·석양의 따뜻한 색은 해 있는 쪽 지평에만 깔린다.

group_uniforms sky_light;
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.86);   // 해가 있는 쪽(세계 좌표, 정규화)
uniform vec3 moon_dir = vec3(0.0, -0.5, 0.86);
uniform float sun_alt = 0.5;                     // 해의 고도 sin값. 밤이면 음수.
uniform float moon_up = 0.0;                     // 달이 떠 있는 정도 0~1

group_uniforms sky_palette;
uniform vec3 day_zenith : source_color = vec3(0.146, 0.320, 0.660);
uniform vec3 day_horizon : source_color = vec3(0.560, 0.700, 0.850);
uniform vec3 dusk_color : source_color = vec3(0.900, 0.470, 0.230);
uniform vec3 night_zenith : source_color = vec3(0.072, 0.106, 0.196);
uniform vec3 night_horizon : source_color = vec3(0.118, 0.156, 0.246);
uniform vec3 sun_tint : source_color = vec3(1.000, 0.930, 0.800);
uniform vec3 moon_tint : source_color = vec3(0.640, 0.740, 1.000);

// 앞으로 몰리는 산란(미). 해 둘레의 후광이 여기서 나온다.
float sky_hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566371 * pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5));
}

// dir 은 세계 좌표의 단위 방향. 해 원반은 여기서 그리지 않는다 —
// 물에 비친 해는 이미 빛의 반사(스페큘러)로 그려지므로 두 번 그리게 된다.
vec3 sky_color(vec3 dir) {
	float up = clamp(dir.y, -1.0, 1.0);

	// 지평에 가까울수록 1. 아래쪽(바다에 가린 자리)도 지평색으로 이어둔다.
	float horizon_t = pow(1.0 - clamp(abs(up), 0.0, 1.0), 3.0);

	float day = clamp((sun_alt + 0.09) / 0.30, 0.0, 1.0);
	float dusk = clamp(1.0 - abs(sun_alt) / 0.22, 0.0, 1.0);

	vec3 zen = mix(night_zenith, day_zenith, day);
	vec3 hor = mix(night_horizon, day_horizon, day);
	vec3 col = mix(zen, hor, horizon_t);

	float cs = dot(dir, sun_dir);

	// 레일리 산란의 성질 — 해 쪽과 그 정반대가 밝고, 90도 떨어진 쪽이 가장 짙다.
	// 하늘이 방향마다 다른 것은 대부분 이 항 때문이고, 물이 살아 보이는 것도 이것이다.
	float aniso = 0.5 + 0.5 * cs * cs;
	col *= mix(1.0, mix(0.74, 1.10, aniso), day);

	// 해 둘레의 후광. 해가 낮을수록 넓고 세다.
	// 물도 이 식을 보므로 세게 잡으면 바다가 통째로 은색이 된다.
	// 물 위의 반짝임은 빛의 반사가 따로 맡는다.
	float low = 1.0 - clamp(sun_alt, 0.0, 1.0);
	// 봉우리가 1을 넘으면 톤매핑이 하얗게 뭉개서 원반을 삼킨다.
	// 무리는 "빛나는 기운"까지만 하고, 하얀 심은 원반이 맡는다.
	col += hor * sky_hg(cs, 0.86) * (0.018 + 0.10 * low) * day;

	// 지평 근처의 뿌연 띠. 대기를 길게 지나오면 색이 빠진다.
	col = mix(col, mix(col, hor, 0.55), horizon_t * horizon_t * day * 0.8);

	// 새벽·석양. 해 있는 쪽 지평에만 앉는다. 이걸 사방에 깔면 하늘이 통째로 물든다.
	float warm = dusk * horizon_t * smoothstep(-0.25, 0.60, cs);
	col = mix(col, dusk_color, warm * 0.78);

	// 달빛 후광. 밤에만.
	float cm = dot(dir, moon_dir);
	col += moon_tint * pow(clamp(cm, 0.0, 1.0), 20.0) * 0.16 * moon_up * (1.0 - day);
	col += moon_tint * sky_hg(cm, 0.55) * 0.035 * moon_up * (1.0 - day);

	// 수평선 아래는 볼 일이 거의 없지만, 바다 끝과 이어지는 자리라 곱게 떨어뜨린다.
	col *= mix(1.0, 0.55, clamp(-up * 3.0, 0.0, 1.0));

	return max(col, vec3(0.0));
}
