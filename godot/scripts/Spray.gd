class_name Spray
extends Node3D

## 뱃머리가 물을 가를 때 튀는 물보라.
##
## 셰이더가 그리는 항적은 수면에 눕는 무늬라 배가 물을 "밀고 있다"는 느낌까지는
## 못 준다. 그건 수면 위로 솟는 알갱이가 있어야 나온다. 그래서 둘을 같이 쓴다.
##
## GPU 입자가 아니라 CPU 입자인 이유는 웹(호환성 렌더러)에서 돌려야 하기 때문이다.

const BOW_Z := -11.5            ## 뱃머리 조금 안쪽. 여기서 물이 갈라진다
const SIDE_X := 2.1

var _emitters: Array[CPUParticles3D] = []
var _base: Array = []            ## 속도 1 에서 얼마나 튀는가의 기준값
var _speed := 0.0

func _ready() -> void:
	# 좌우 뱃전으로 튀는 물방울
	for s in [-1.0, 1.0]:
		var p := _make(
			Vector3(SIDE_X * s, 0.35, BOW_Z),
			Vector3(0.62 * s, 0.66, -0.42),
			30, 0.8, 0.55)
		p.spread = 22.0
		p.initial_velocity_min = 2.8
		p.initial_velocity_max = 6.0
		add_child(p)
		_keep(p)

	# 뱃머리 바로 아래에서 부서지는 흰 물살. 낮고 얇게 깔린다.
	var f := _make(Vector3(0.0, 0.10, BOW_Z - 0.6), Vector3(0.0, 0.45, -1.0),
		22, 0.95, 0.9)
	f.spread = 44.0
	f.initial_velocity_min = 1.0
	f.initial_velocity_max = 2.6
	f.gravity = Vector3(0.0, -6.0, 0.0)
	f.emission_box_extents = Vector3(2.0, 0.12, 0.5)
	add_child(f)
	_keep(f)

## 속도에 따라 흔들 값들은 원래 값을 적어 둬야 한다. 매 프레임 곱하면
## 값이 눈덩이처럼 불어난다.
func _keep(p: CPUParticles3D) -> void:
	_emitters.append(p)
	_base.append({
		"vmin": p.initial_velocity_min, "vmax": p.initial_velocity_max,
		"life": p.lifetime,
		"smin": p.scale_amount_min, "smax": p.scale_amount_max,
	})

func _make(pos: Vector3, dir: Vector3, amount: int, life: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.direction = dir.normalized()
	p.amount = amount
	p.lifetime = life
	# 배는 계속 움직이므로 입자는 태어난 자리에 남아야 한다.
	# 배를 따라다니면 물보라가 아니라 뱃머리에 붙은 장식이 된다.
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.5, 0.2, 0.9)
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.8
	p.scale_amount_min = size * 0.55
	p.scale_amount_max = size

	# 태어날 땐 물덩이, 사라질 땐 물안개
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.65))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.15))
	p.scale_amount_curve = curve

	# 물보라는 물이 아니라 물안개다. 불투명하게 칠하면 배 뒤에 흰 구름이 달린다.
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	g.set_color(1, Color(0.86, 0.92, 0.96, 0.0))
	g.add_point(0.12, Color(1.0, 1.0, 1.0, 0.72))
	g.add_point(0.45, Color(0.95, 0.98, 1.0, 0.40))
	p.color_ramp = g

	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	p.mesh = q

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.97, 0.99, 1.0)
	m.albedo_texture = _puff()
	m.disable_receive_shadows = true
	q.material = m

	p.emitting = false
	return p

## 알갱이 하나의 모양. 사각형 판을 그대로 쓰면 하얀 네모가 날아다닌다.
## 가운데가 진하고 가장자리로 갈수록 사라지는 동그란 얼룩이어야 물안개로 보인다.
static var _puff_tex: ImageTexture

static func _puff() -> ImageTexture:
	if _puff_tex:
		return _puff_tex
	var n := 48
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) / float(n) - Vector2(0.5, 0.5)
			var r := d.length() * 2.0
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex

## 빠를수록 높이, 멀리, 오래 튄다. 멈추면 아예 끊는다.
##
## 전에는 speed_scale 하나만 만졌다. 그러면 빠를 때 물방울이 "많이" 나올 뿐
## 무게가 안 생긴다 — 물은 뱃머리에서 떠밀려 뒤로 흐르다 가라앉아야 한다.
## 그래서 속도에 따라 튀는 세기와 사는 시간, 알갱이 크기를 함께 올린다.
func set_speed01(v: float) -> void:
	_speed = clampf(v, 0.0, 1.0)
	var on := _speed > 0.08
	for i in _emitters.size():
		var p: CPUParticles3D = _emitters[i]
		p.emitting = on
		if not on:
			continue
		# 느릴 때 같은 세기로 튀면 정박 중에도 물이 끓는 것처럼 보인다
		p.speed_scale = lerpf(0.55, 1.35, _speed)
		p.lifetime_randomness = 0.4
		var base: Dictionary = _base[i]
		# 뱃머리가 세게 파고들수록 물이 높이 솟는다
		p.initial_velocity_min = base.vmin * lerpf(0.6, 2.1, _speed)
		p.initial_velocity_max = base.vmax * lerpf(0.7, 2.4, _speed)
		# 오래 남아야 뒤로 흘러가다 가라앉는 것이 보인다
		p.lifetime = base.life * lerpf(0.7, 1.9, _speed)
		# 덩어리도 굵어진다
		p.scale_amount_min = base.smin * lerpf(0.75, 1.5, _speed)
		p.scale_amount_max = base.smax * lerpf(0.8, 1.7, _speed)
