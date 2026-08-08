class_name ShipModel
extends RefCounted

## 자리를 채워두는 캐러벨. 나중에 진짜 모델로 갈아끼울 자리다.
## 길이 24m 남짓, 이 시대 배답게 고물이 높다. -Z 가 뱃머리.

const DECK_Y := 2.2
const KEEL_Y := -1.8

## 갑판 테두리 (x, z). 뱃머리가 뾰족하고 고물은 각지게.
const RING := [
	Vector2(0.0, -12.5), Vector2(2.2, -9.0), Vector2(3.3, -3.0),
	Vector2(3.5, 3.0), Vector2(3.2, 8.0), Vector2(2.4, 11.5),
	Vector2(-2.4, 11.5), Vector2(-3.2, 8.0), Vector2(-3.5, 3.0),
	Vector2(-3.3, -3.0), Vector2(-2.2, -9.0),
]

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Ship"

	root.add_child(_hull())
	root.add_child(_box(Vector3(5.2, 3.0, 5.4), Vector3(0, DECK_Y + 1.5, 8.6), Color("5a4830")))
	root.add_child(_box(Vector3(4.2, 1.6, 3.2), Vector3(0, DECK_Y + 0.8, -8.4), Color("5a4830")))

	# 돛대
	root.add_child(_mast(Vector3(0, DECK_Y, 0.5), 19.0, 0.42))
	root.add_child(_mast(Vector3(0, DECK_Y, -6.5), 13.5, 0.32))

	# 돛 — 바람에 따라 기울일 수 있도록 따로 매달아 둔다
	var rig := Node3D.new()
	rig.name = "Sails"
	rig.add_child(_sail(Vector3(0, DECK_Y + 13.0, 0.5), Vector2(13.0, 9.5)))
	rig.add_child(_sail(Vector3(0, DECK_Y + 6.4, 0.5), Vector2(10.5, 5.4)))
	rig.add_child(_sail(Vector3(0, DECK_Y + 9.4, -6.5), Vector2(8.5, 6.4)))
	root.add_child(rig)

	# 삼각기
	var flag := _box(Vector3(0.15, 0.9, 2.6), Vector3(0, DECK_Y + 19.4, 1.6), Color("b33a2e"))
	flag.name = "Pennant"
	root.add_child(flag)
	return root

static func _hull() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n := RING.size()
	var deck: Array = []
	var keel: Array = []
	for r in RING:
		deck.append(Vector3(r.x, DECK_Y, r.y))
		keel.append(Vector3(r.x * 0.34, KEEL_Y, r.y * 0.90))

	# 뱃전
	for i in n:
		var j := (i + 1) % n
		st.add_vertex(deck[i]); st.add_vertex(keel[i]); st.add_vertex(keel[j])
		st.add_vertex(deck[i]); st.add_vertex(keel[j]); st.add_vertex(deck[j])

	# 갑판과 배 밑
	var mid_deck := Vector3(0, DECK_Y, 0)
	var mid_keel := Vector3(0, KEEL_Y, 0)
	for i in n:
		var j := (i + 1) % n
		st.add_vertex(mid_deck); st.add_vertex(deck[j]); st.add_vertex(deck[i])
		st.add_vertex(mid_keel); st.add_vertex(keel[i]); st.add_vertex(keel[j])

	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.name = "Hull"
	mi.mesh = st.commit()
	mi.material_override = _mat(Color("4e3d26"), 0.85)
	return mi

static func _mast(base: Vector3, height: float, radius: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.55
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position = base + Vector3(0, height * 0.5, 0)
	mi.material_override = _mat(Color("7c6a46"), 0.9)
	return mi

static func _sail(pos: Vector3, size: Vector2) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = pos
	var mat := _mat(Color("ede4cd"), 0.75)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
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
