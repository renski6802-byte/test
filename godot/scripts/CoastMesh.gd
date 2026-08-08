class_name CoastMesh
extends RefCounted

## 해안선 자료를 바다에서 본 땅으로 세운다.
##
## 안쪽은 그릴 필요가 없다. 배에서 보이는 건 물가에서 솟아오르는 능선뿐이라,
## 해안선을 따라 띠 두 장(물가→능선, 능선→고원)만 세우면 충분하다.

## 안쪽으로 들어가는 거리도 지리 거리라 세계 축척을 같이 받아야 한다.
## 안 그러면 해안선만 줄어들고 땅은 그대로라 하늘을 덮는 판이 된다.
const RIDGE_INLAND := 2600.0 * Geo.WORLD_SCALE
const PLATEAU_INLAND := 26000.0 * Geo.WORLD_SCALE

static func build() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for coast in [Geo.COAST_IB, Geo.COAST_AF]:
		_add_coast(st, coast)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Coast"
	mi.mesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("39402f")
	mat.roughness = 0.94
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi

static func _add_coast(st: SurfaceTool, coast: Array) -> void:
	var n := coast.size()
	if n < 2:
		return

	# 각 점마다 물가·능선·고원 세 자리를 구해둔다
	var shore: Array = []
	var ridge: Array = []
	var plateau: Array = []

	for i in n:
		var g: Vector2 = coast[i]
		var here := Geo.to_world(g.x, g.y)

		# 해안선이 뻗는 방향
		var a: Vector2 = coast[max(i - 1, 0)]
		var b: Vector2 = coast[min(i + 1, n - 1)]
		var pa := Geo.to_world(a.x, a.y)
		var pb := Geo.to_world(b.x, b.y)
		var dir := (pb - pa)
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3(0, 0, -1)
		dir = dir.normalized()

		# 진행 방향의 수직. 어느 쪽이 뭍인지는 실제로 찍어보고 정한다.
		var nrm := Vector3(-dir.z, 0.0, dir.x)
		var probe := Geo.to_geo(here + nrm * 3000.0)
		if not Geo.on_land(probe.x, probe.y):
			nrm = -nrm

		var h := Geo.coast_height(g.x, g.y)
		shore.append(here)
		ridge.append(here + nrm * RIDGE_INLAND + Vector3(0, h, 0))
		plateau.append(here + nrm * PLATEAU_INLAND + Vector3(0, h * 0.62, 0))

	for i in range(n - 1):
		_quad(st, shore[i], shore[i + 1], ridge[i + 1], ridge[i])
		_quad(st, ridge[i], ridge[i + 1], plateau[i + 1], plateau[i])

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
