class_name Ocean
extends Node3D

## 바다 두 겹. 배 주위는 실제로 꼭짓점을 밀어 파도를 만들고, 그 너머는 판 하나로 덮는다.
## 둘 다 배를 따라다니므로 어디로 가도 바다가 끊기지 않는다.

## 판의 한 칸이 파도보다 크면 파도가 격자에 걸려 규칙적인 줄무늬가 된다.
## 그래서 범위를 좁히고 칸을 잘게 썬다. 1600 / 256 이면 한 칸이 12.5m 라,
## 가장 짧은 파도(27m)도 두 칸 넘게 쓴다.
const NEAR_EXTENT := 1600.0     ## 파도가 실제로 형태를 갖는 범위
const NEAR_SUBDIV := 256
const FAR_EXTENT := 240000.0
## 먼바다는 판이 아니라 고리다. 가까운 바다 밑에 깔면 파도 골로 뚫고 올라오고,
## 아래로 내리면 이어지는 자리에 턱이 생긴다. 아예 겹치지 않게 하는 편이 낫다.
const FAR_INNER := NEAR_EXTENT * 0.98

## 셰이더의 파도와 같은 값이어야 한다. 배가 파도를 타려면 CPU 도 같은 높이를 알아야 한다.
## [dir_x, dir_z, 파장(m), 진폭(m), 뾰족함]
## 27m 아래는 노멀맵이 맡는다. 꼭짓점으로 만들면 격자무늬가 되기 때문이다.
const WAVES := [
	[1.00, 0.10, 143.0, 0.92, 0.34],
	[0.20, 1.00, 81.0, 0.56, 0.40],
	[-0.90, 0.55, 47.0, 0.30, 0.45],
	[0.55, -0.95, 27.0, 0.16, 0.48],
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
##
## 사인 몇 개를 더해 만들면 간섭무늬가 남아 등고선처럼 보인다. 물이 아니라 지형도가
## 된다. 그래서 격자에 난수를 깔고 부드럽게 이어 붙이는 방식으로 굽는다.
## 옥타브의 주기가 텍스처 크기를 정확히 나눠야 타일 경계가 이어진다.
static func _ripple_normals(size: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250808

	var h := PackedFloat32Array()
	h.resize(size * size)

	for oc in [[4, 1.00], [8, 0.52], [16, 0.27], [32, 0.14], [64, 0.07]]:
		var n: int = oc[0]
		var amp: float = oc[1]
		var grid := PackedFloat32Array()
		grid.resize(n * n)
		for i in n * n:
			grid[i] = rng.randf()

		var step := float(size) / float(n)
		for y in size:
			var fy := float(y) / step
			var y0 := int(fy) % n
			var y1 := (y0 + 1) % n
			var ty: float = fy - floor(fy)
			ty = ty * ty * (3.0 - 2.0 * ty)
			for x in size:
				var fx := float(x) / step
				var x0 := int(fx) % n
				var x1 := (x0 + 1) % n
				var tx: float = fx - floor(fx)
				tx = tx * tx * (3.0 - 2.0 * tx)
				var a := lerpf(grid[y0 * n + x0], grid[y0 * n + x1], tx)
				var b := lerpf(grid[y1 * n + x0], grid[y1 * n + x1], tx)
				h[y * size + x] += lerpf(a, b, ty) * amp

	var img := Image.create_empty(size, size, true, Image.FORMAT_RGB8)
	var at := func(x: int, y: int) -> float:
		return h[(y % size + size) % size * size + (x % size + size) % size]

	for y in size:
		for x in size:
			var hx: float = at.call(x + 1, y) - at.call(x - 1, y)
			var hy: float = at.call(x, y + 1) - at.call(x, y - 1)
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

	_far_mat = ShaderMaterial.new()
	_far_mat.shader = load("res://shaders/ocean_far.gdshader")
	_far_mat.set_shader_parameter("choppiness", choppiness)
	_far_mat.set_shader_parameter("ripple_normals", ripples)

	_far = MeshInstance3D.new()
	_far.name = "FarSea"
	_far.mesh = _ring(FAR_INNER, FAR_EXTENT * 0.5)
	_far.material_override = _far_mat
	# 안쪽 테두리가 가까운 바다 판의 잔잔한 가장자리 밑으로 조금 들어간다.
	# 같은 높이면 그 띠에서 두 면이 깜빡이므로 손톱만큼 내린다.
	_far.position.y = -0.05
	add_child(_far)

## 가운데가 뚫린 네모 고리. 가까운 바다 판이 차지한 자리는 비워둔다.
static func _ring(inner: float, outer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		for v in [a, b, c, a, c, d]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)

	var i := inner
	var o := outer
	var p := func(x: float, z: float) -> Vector3: return Vector3(x, 0.0, z)
	quad.call(p.call(-o, -o), p.call(o, -o), p.call(i, -i), p.call(-i, -i))
	quad.call(p.call(o, -o), p.call(o, o), p.call(i, i), p.call(i, -i))
	quad.call(p.call(o, o), p.call(-o, o), p.call(-i, i), p.call(i, i))
	quad.call(p.call(-o, o), p.call(-o, -o), p.call(-i, -i), p.call(-i, i))

	return st.commit()

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

## 뱃머리가 가르는 물살을 그리려면 셰이더가 배의 자리와 방향을 알아야 한다.
## speed01 은 0~1 로 줄인 속력. 멈추면 항적도 사라진다.
func set_ship(world_xz: Vector3, dir_xz: Vector2, speed01: float) -> void:
	if not _near_mat:
		return
	_near_mat.set_shader_parameter("ship_pos", Vector2(world_xz.x, world_xz.z))
	_near_mat.set_shader_parameter("ship_dir", dir_xz.normalized())
	_near_mat.set_shader_parameter("ship_speed01", clampf(speed01, 0.0, 1.0))

## 물에 비칠 하늘색을 넘겨준다. 물빛의 절반은 비친 하늘이다.
func set_sky(horizon: Color, zenith: Color) -> void:
	for m in [_near_mat, _far_mat]:
		if m:
			m.set_shader_parameter("sky_horizon", horizon)
			m.set_shader_parameter("sky_zenith", zenith)

func height_at(x: float, z: float, t: float) -> float:
	return displace_at(x, z, t).y
