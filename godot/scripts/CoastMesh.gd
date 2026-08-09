class_name CoastMesh
extends Node3D

## 해안선 자료를 바다에서 본 땅으로 세운다.
##
## 안쪽은 그릴 필요가 없다. 배에서 보이는 건 물가에서 솟아오르는 능선뿐이라,
## 해안선을 따라 띠 두 장(물가→능선, 능선→고원)만 세우면 충분하다.
##
## 육지는 바다와 다른 축척을 쓴다. 그래서 메시를 축척 없는 지리 미터로 만들어
## 두고, 매 프레임 배를 기준으로 눌러 놓는다. 가로만 누르고 높이는 그대로 둔다 —
## 실제 300m 절벽이 화면에서도 300m 로 서야 배(26m) 옆에서 위압적으로 보인다.

var _mesh: MeshInstance3D

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Land"
	_mesh.mesh = _build()
	var mat := StandardMaterial3D.new()
	# 색은 지형 종류마다 다르므로 꼭짓점에 실어 보낸다
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.94
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	add_child(_mesh)

## 배가 어디에 있는지 알려주면 그 자리를 기준으로 육지를 눌러 놓는다.
##
## 배에서 지리적으로 D 만큼 떨어진 해안은 화면에서 D × LAND_SCALE 만큼 떨어진다.
## 배 자신은 바다 축척을 쓰므로 둘의 접근 속도가 다른데, 육지가 보이면 배속이
## 저절로 내려가서 눈에 띄지 않는다.
func follow(ship_world: Vector3, ship_lon: float, ship_lat: float) -> void:
	var ls := Geo.LAND_SCALE
	var b := Basis(Vector3(ls, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, ls))
	var here := Geo.to_metres(ship_lon, ship_lat)
	var flat := Vector3(ship_world.x, 0.0, ship_world.z)
	global_transform = Transform3D(b, flat - b * here)

func _build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for coast in [Geo.COAST_IB, Geo.COAST_AF]:
		_add_coast(st, coast, Geo.coast_types(coast))
	st.generate_normals()
	return st.commit()

static func _add_coast(st: SurfaceTool, coast: Array, kinds: Array) -> void:
	var n := coast.size()
	if n < 2:
		return

	var shore: Array = []
	var ridge: Array = []
	var plateau: Array = []
	var tint: Array = []

	for i in n:
		var g: Vector2 = coast[i]
		var here := Geo.to_metres(g.x, g.y)
		var kind: int = kinds[i] if i < kinds.size() else Geo.LOW
		var t: Array = Geo.TERRAIN[kind]

		# 해안선이 뻗는 방향
		var a: Vector2 = coast[max(i - 1, 0)]
		var b: Vector2 = coast[min(i + 1, n - 1)]
		var dir := Geo.to_metres(b.x, b.y) - Geo.to_metres(a.x, a.y)
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3(0, 0, -1)
		dir = dir.normalized()

		# 진행 방향의 수직. 어느 쪽이 뭍인지는 실제로 찍어보고 정한다.
		var nrm := Vector3(-dir.z, 0.0, dir.x)
		var probe := Geo.to_geo(Geo.to_world(g.x, g.y) + nrm * 3000.0 * Geo.WORLD_SCALE)
		if not Geo.on_land(probe.x, probe.y):
			nrm = -nrm

		var h := Geo.coast_height(g.x, g.y, kind)
		shore.append(here)
		ridge.append(here + nrm * float(t[2]) + Vector3(0, h, 0))
		# 안쪽 띠는 능선보다 조금 높아야 한다. 낮으면 갑판처럼 위에서 내려다보게 되고,
		# 바다에서 보이는 건 능선의 실루엣뿐이어야 한다.
		plateau.append(here + nrm * float(t[3]) + Vector3(0, h * 1.15, 0))
		tint.append(t[4])

	for i in range(n - 1):
		_quad(st, shore[i], shore[i + 1], ridge[i + 1], ridge[i],
			tint[i], tint[i + 1])
		_quad(st, ridge[i], ridge[i + 1], plateau[i + 1], plateau[i],
			tint[i], tint[i + 1])

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color) -> void:
	# 물가 쪽을 조금 어둡게 해 젖은 바위처럼 보이게 한다
	var wet_a := ca.darkened(0.28)
	var wet_b := cb.darkened(0.28)
	for v in [[a, wet_a], [b, wet_b], [c, cb], [a, wet_a], [c, cb], [d, ca]]:
		st.set_color(v[1])
		st.add_vertex(v[0])
