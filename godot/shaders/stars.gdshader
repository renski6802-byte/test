shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_add;

// 별 하나가 사각형 한 장이다. 꼭짓점 넷이 모두 같은 자리(별의 방향)에 있고,
// 여기서 화면 쪽으로 펼쳐 동그란 점으로 만든다. 그래야 어디서 보든 동그랗다.
//
// UV   = 네 귀퉁이 (-1..1)
// UV2.x = 펼칠 크기, UV2.y = 반짝임에 쓸 씨앗
// COLOR = 별빛 색(B-V 에서 뽑은 것)과 밝기

uniform float night = 1.0;      // 밤의 정도 0~1. 낮에는 별이 안 보인다.
uniform float twinkle = 0.5;

varying vec2 corner;
varying float bright;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void vertex() {
	corner = UV;

	// 별은 무한히 멀다. 크기를 시야 공간에서 더해야 거리와 무관하게 일정해진다.
	vec3 view_center = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// 대기가 두꺼운 지평 근처에서는 어두워지고 더 심하게 흔들린다
	vec3 world_dir = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float alt = clamp(world_dir.y, 0.0, 1.0);
	float extinction = smoothstep(-0.02, 0.22, world_dir.y);

	float seed = UV2.y;
	float tw = 1.0 + twinkle * (1.0 - alt) * 0.9
		* sin(TIME * (2.1 + hash11(seed) * 5.0) + seed * 37.0);

	bright = COLOR.a * night * extinction * max(tw, 0.25);

	view_center.xy += UV * UV2.x * (0.8 + 0.35 * clamp(tw, 0.0, 2.0));
	POSITION = PROJECTION_MATRIX * vec4(view_center, 1.0);
}

void fragment() {
	// 가운데가 진하고 가장자리로 갈수록 사라지는 점. 사각형이 보이면 안 된다.
	float r = length(corner);
	float core = exp(-r * r * 5.0);
	// 밝은 별은 십자로 살짝 번진다
	float spike = exp(-abs(corner.x) * 9.0) + exp(-abs(corner.y) * 9.0);
	float a = core + spike * 0.06 * smoothstep(0.55, 1.0, bright);

	ALBEDO = COLOR.rgb * a * bright * 2.9;
	ALPHA = 1.0;
}
