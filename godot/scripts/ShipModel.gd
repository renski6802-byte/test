class_name ShipModel
extends RefCounted

## 자리를 채워두는 캐러벨. 길이 26m 남짓, 이 시대 배답게 고물이 높다. -Z 가 뱃머리.
## 나중에 진짜 모델로 갈아끼울 곳이라 원시 도형만으로 세운다.

const KEEL_Y := -2.2

## 갑판 테두리 (x, z) 와 그 자리의 갑판 높이. 뱃머리와 고물이 솟는 시어(sheer)를 준다.
const RING := [
	[Vector2(0.0, -13.0), 4.6],
	[Vector2(2.6, -9.5), 3.7],
	[Vector2(3.9, -3.5), 3.1],
	[Vector2(4.2, 2.5), 3.0],
	[Vector2(3.9, 8.0), 3.3],
	[Vector2(2.9, 12.0), 4.2],
	[Vector2(-2.9, 12.0), 4.2],
	[Vector2(-3.9, 8.0), 3.3],
	[Vector2(-4.2, 2.5), 3.0],
	[Vector2(-3.9, -3.5), 3.1],
	[Vector2(-2.6, -9.5), 3.7],
]

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Ship"

	root.add_child(_hull())
	root.add_child(_strake())

	# 선미루 — 고물이 높은 것이 이 시대 배의 인상이다
	root.add_child(_box(Vector3(6.2, 3.4, 6.0), Vector3(0, 5.9, 8.8), Color("5f4c2e")))
	root.add_child(_box(Vector3(5.0, 1.8, 3.6), Vector3(0, 4.4, -9.6), Color("5f4c2e")))

	root.add_child(_mast(Vector3(0, 3.0, 1.0), 21.0, 0.46))
	root.add_child(_mast(Vector3(0, 3.2, -7.0), 14.5, 0.34))

	var rig := Node3D.new()
	rig.name = "Sails"
	# 큰 돛 두 장과 앞돛 한 장. 활대까지 같이 건다.
	rig.add_child(_yard(Vector3(0, 20.5, 1.0), 15.0))
	rig.add_child(_sail(Vector3(0, 16.0, 1.0), Vector2(14.4, 8.6), 1.5))
	rig.add_child(_yard(Vector3(0, 11.4, 1.0), 12.0))
	rig.add_child(_sail(Vector3(0, 8.4, 1.0), Vector2(11.4, 5.6), 1.1))
	rig.add_child(_yard(Vector3(0, 15.2, -7.0), 10.0))
	rig.add_child(_sail(Vector3(0, 11.8, -7.0), Vector2(9.4, 6.4), 1.0))
	root.add_child(rig)

	var pennant := _box(Vector3(0.12, 0.8, 2.4), Vector3(0, 23.6, 2.2), Color("b33a2e"))
	pennant.name = "Pennant"
	root.add_child(pennant)
	return root

static func _hull() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n := RING.size()
	var deck: Array = []
	var keel: Array = []
	for r in RING:
		var xz: Vector2 = r[0]
		var y: float = r[1]
		deck.append(Vector3(xz.x, y, xz.y))
		keel.append(Vector3(xz.x * 0.30, KEEL_Y, xz.y * 0.88))

	for i in n:
		var j := (i + 1) % n
		st.add_vertex(deck[i]); st.add_vertex(keel[i]); st.add_vertex(keel[j])
		st.add_vertex(deck[i]); st.add_vertex(keel[j]); st.add_vertex(deck[j])

	var mid_deck := Vector3(0, 3.0, 0)
	var mid_keel := Vector3(0, KEEL_Y, 0)
	for i in n:
		var j := (i + 1) % n
		st.add_vertex(mid_deck); st.add_vertex(deck[j]); st.add_vertex(deck[i])
		st.add_vertex(mid_keel); st.add_vertex(keel[i]); st.add_vertex(keel[j])

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Hull"
	mi.mesh = st.commit()
	mi.material_override = _mat(Color("46351f"), 0.85)
	return mi

## 뱃전을 따라 도는 밝은 띠. 이것 하나로 배가 납작해 보이지 않는다.
static func _strake() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := RING.size()
	for i in n:
		var j := (i + 1) % n
		var a: Vector2 = RING[i][0]
		var b: Vector2 = RING[j][0]
		var ay: float = RING[i][1]
		var by: float = RING[j][1]
		var a_top := Vector3(a.x * 1.01, ay - 0.15, a.y * 1.01)
		var a_bot := Vector3(a.x * 1.01, ay - 0.95, a.y * 1.01)
		var b_top := Vector3(b.x * 1.01, by - 0.15, b.y * 1.01)
		var b_bot := Vector3(b.x * 1.01, by - 0.95, b.y * 1.01)
		st.add_vertex(a_top); st.add_vertex(a_bot); st.add_vertex(b_bot)
		st.add_vertex(a_top); st.add_vertex(b_bot); st.add_vertex(b_top)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Strake"
	mi.mesh = st.commit()
	mi.material_override = _mat(Color("8a6f42"), 0.8)
	return mi

## 바람을 먹어 배부른 가로돛. 평평한 판이면 종이처럼 보인다.
static func _sail(pos: Vector3, sz: Vector2, belly: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cols := 8
	var rows := 5
	var pt := func(i: int, j: int) -> Vector3:
		var u := float(i) / float(cols)
		var v := float(j) / float(rows)
		# 아래로 갈수록 조금 좁아진다
		var w: float = sz.x * lerpf(1.0, 0.86, v)
		var x := (u - 0.5) * w
		var y := (0.5 - v) * sz.y
		var z := -belly * sin(PI * u) * sin(PI * v * 0.85 + 0.25)
		return Vector3(x, y, z)

	for j in rows:
		for i in cols:
			var p00: Vector3 = pt.call(i, j)
			var p10: Vector3 = pt.call(i + 1, j)
			var p11: Vector3 = pt.call(i + 1, j + 1)
			var p01: Vector3 = pt.call(i, j + 1)
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = pos
	var m := _mat(Color("e8dfc6"), 0.72)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi

static func _yard(pos: Vector3, length: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = length
	cyl.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position = pos
	mi.rotation.z = PI * 0.5
	mi.material_override = _mat(Color("6d5c3c"), 0.9)
	return mi

static func _mast(base: Vector3, height: float, radius: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.5
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position = base + Vector3(0, height * 0.5, 0)
	mi.material_override = _mat(Color("7c6a46"), 0.9)
	return mi

static func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(col, 0.88)
	return mi

static func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m
