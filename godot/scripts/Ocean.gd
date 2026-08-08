class_name Ocean
extends Node3D

## 바다 두 겹. 배 주위는 실제로 꼭짓점을 밀어 파도를 만들고, 그 너머는 판 하나로 덮는다.
## 둘 다 배를 따라다니므로 어디로 가도 바다가 끊기지 않는다.

const NEAR_EXTENT := 3000.0     ## 파도가 실제로 형태를 갖는 범위
const NEAR_SUBDIV := 256
const FAR_EXTENT := 240000.0

## 셰이더의 파도와 같은 값이어야 한다. 배가 파도를 타려면 CPU 도 같은 높이를 알아야 한다.
## [dir_x, dir_z, 파장, 진폭, 뾰족함]
const WAVES := [
	[1.00, 0.18, 62.0, 0.85, 0.55],
	[-0.55, 1.00, 34.0, 0.45, 0.50],
	[0.35, -1.00, 17.0, 0.22, 0.45],
	[-1.00, -0.45, 8.0, 0.10, 0.40],
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

func _ready() -> void:
	var near_plane := PlaneMesh.new()
	near_plane.size = Vector2(NEAR_EXTENT * 2.0, NEAR_EXTENT * 2.0)
	near_plane.subdivide_width = NEAR_SUBDIV
	near_plane.subdivide_depth = NEAR_SUBDIV

	_near_mat = ShaderMaterial.new()
	_near_mat.shader = load("res://shaders/ocean_near.gdshader")
	_near_mat.set_shader_parameter("half_extent", NEAR_EXTENT)
	_near_mat.set_shader_parameter("choppiness", choppiness)

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
	# 가까운 판 아래로 조금 내려 두 판이 다투지 않게 한다
	_far.position.y = -1.2
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

## 수평선 쪽 바다 색을 하늘에 맞춘다. 안 그러면 밤에도 먼바다만 훤하다.
func set_horizon_tint(c: Color) -> void:
	if _near_mat:
		_near_mat.set_shader_parameter("horizon_tint", c)
	if _far_mat:
		_far_mat.set_shader_parameter("horizon_tint", c)

func height_at(x: float, z: float, t: float) -> float:
	return displace_at(x, z, t).y
