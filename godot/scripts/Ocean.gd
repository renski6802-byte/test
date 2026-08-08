class_name Ocean
extends Node3D

## 바다 두 겹. 배 주위는 실제로 꼭짓점을 밀어 파도를 만들고, 그 너머는 판 하나로 덮는다.
## 둘 다 배를 따라다니므로 어디로 가도 바다가 끊기지 않는다.

const NEAR_EXTENT := 3000.0     ## 파도가 실제로 형태를 갖는 범위
const NEAR_SUBDIV := 256
const FAR_EXTENT := 240000.0

## 셰이더의 파도와 같은 값이어야 한다. 배가 파도를 타려면 CPU 도 같은 높이를 알아야 한다.
## [dir_x, dir_z, 파장(m), 진폭(m), 뾰족함]
## 긴 너울이 크고 잔물결로 갈수록 작아진다. 이 기울기가 바다를 바다로 보이게 한다.
const WAVES := [
	[1.00, 0.15, 140.0, 0.90, 0.35],
	[0.85, 0.50, 78.0, 0.55, 0.40],
	[-0.50, 1.00, 44.0, 0.32, 0.45],
	[0.30, -1.00, 25.0, 0.18, 0.50],
	[-1.00, -0.35, 13.0, 0.090, 0.50],
	[0.60, 0.80, 7.0, 0.045, 0.50],
]

var choppiness := 1.0:
	set(v):
		choppiness = v
		if _near_mat:
			_near_mat.set_shader_parameter("choppiness", v)
		if _far_mat:
			_far_mat.set_shader_parameter("choppiness", v)

var _near: MeshInstance3D
var _far: MeshInstance3D
var _near_mat: ShaderMaterial
var _far_mat: ShaderMaterial

## 잔결용 타일 노멀맵. 파장 1m 아래를 셰이더에서 직접 계산하면 화면 픽셀보다 작아
## 반드시 줄무늬로 튄다. 텍스처로 구우면 밉맵이 알아서 걸러준다.
static func _ripple_normals(size: int) -> ImageTexture:
	var img := Image.create_empty(size, size, true, Image.FORMAT_RGB8)
	# 정수 주파수만 써야 타일 경계가 이어진다
	var comps := [
		[1.0, 2.0, 0.55, 0.0], [3.0, 1.0, 0.40, 1.1], [2.0, 4.0, 0.30, 2.3],
		[5.0, 3.0, 0.22, 0.7], [4.0, 7.0, 0.16, 3.1], [8.0, 5.0, 0.11, 1.9],
		[11.0, 9.0, 0.07, 0.4], [13.0, 6.0, 0.05, 2.7],
	]

	var height := func(u: float, v: float) -> float:
		var h := 0.0
		for c in comps:
			h += c[2] * sin(TAU * (c[0] * u + c[1] * v) + c[3])
		return h

	var d := 1.0 / float(size)
	for y in size:
		for x in size:
			var u := float(x) * d
			var v := float(y) * d
			var hx: float = height.call(u + d, v) - height.call(u - d, v)
			var hy: float = height.call(u, v + d) - height.call(u, v - d)
			var n := Vector3(-hx * 6.0, 1.0, -hy * 6.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _ready() -> void:
	var near_plane := PlaneMesh.new()
	near_plane.size = Vector2(NEAR_EXTENT * 2.0, NEAR_EXTENT * 2.0)
	near_plane.subdivide_width = NEAR_SUBDIV
	near_plane.subdivide_depth = NEAR_SUBDIV

	_near_mat = ShaderMaterial.new()
	_near_mat.shader = load("res://shaders/ocean_near.gdshader")
	_near_mat.set_shader_parameter("half_extent", NEAR_EXTENT)
	_near_mat.set_shader_parameter("choppiness", choppiness)
	var ripples := _ripple_normals(256)
	_near_mat.set_shader_parameter("ripple_normals", ripples)

	_near = MeshInstance3D.new()
	_near.name = "NearSea"
	_near.mesh = near_plane
	_near.material_override = _near_mat
	# 파도가 넘실대는 판이라 컬링 상자를 넉넉히 잡아준다
	_near.custom_aabb = AABB(
		Vector3(-NEAR_EXTENT, -40.0, -NEAR_EXTENT),
		Vector3(NEAR_EXTENT * 2.0, 80.0, NEAR_EXTENT * 2.0))
	add_child(_near)

	var far_plane := PlaneMesh.new()
	far_plane.size = Vector2(FAR_EXTENT, FAR_EXTENT)

	_far_mat = ShaderMaterial.new()
	_far_mat.shader = load("res://shaders/ocean_far.gdshader")
	_far_mat.set_shader_parameter("choppiness", choppiness)

	_far = MeshInstance3D.new()
	_far.name = "FarSea"
	_far.mesh = far_plane
	_far.material_override = _far_mat
	# 파도 골이 이 판보다 깊이 내려가면 먼바다 판이 뚫고 올라와 평평한 조각으로 보인다.
	# 진폭 총합(약 2.1m)보다 넉넉히 아래로 내려둔다.
	_far.position.y = -5.0
	add_child(_far)

## 배를 따라 바다를 옮긴다. 파도는 세계 좌표로 계산하므로 판이 움직여도 흐르지 않는다.
func follow(world_xz: Vector3) -> void:
	_near.position.x = world_xz.x
	_near.position.z = world_xz.z
	_far.position.x = world_xz.x
	_far.position.z = world_xz.z

## 셰이더와 같은 파도의 변위. 배를 띄우는 데 쓴다.
func displace_at(x: float, z: float, t: float) -> Vector3:
	var p := Vector2(x, z)
	var out := Vector3.ZERO
	for w in WAVES:
		var d := Vector2(w[0], w[1]).normalized()
		var k: float = TAU / float(w[2])
		var amp: float = float(w[3]) * choppiness
		var q: float = float(w[4])
		var ph: float = k * d.dot(p) - sqrt(9.81 * k) * t
		var c := cos(ph)
		out.x += d.x * q * amp * c
		out.z += d.y * q * amp * c
		out.y += amp * sin(ph)
	return out

## 물에 비칠 하늘색을 넘겨준다. 물빛의 절반은 비친 하늘이다.
func set_sky(horizon: Color, zenith: Color) -> void:
	for m in [_near_mat, _far_mat]:
		if m:
			m.set_shader_parameter("sky_horizon", horizon)
			m.set_shader_parameter("sky_zenith", zenith)

func height_at(x: float, z: float, t: float) -> float:
	return displace_at(x, z, t).y
