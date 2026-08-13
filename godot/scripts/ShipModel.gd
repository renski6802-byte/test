class_name ShipModel
extends RefCounted

## 배.
##
## 상자를 쌓아 만들지 않는다. 늑골 단면(station)을 뱃머리에서 고물까지 늘어놓고
## 그 사이를 이어 껍질을 만든다. 실제로 배를 짓는 순서와 같고, 그래서 치수만
## 바꾸면 다른 배가 저절로 나온다 — 카라벨도 나우도 같은 코드에서 나온다.
##
## 좌표: -Z 가 뱃머리, +Z 가 고물, +X 가 우현. y=0 이 흘수선이다.

## 단면을 몇 개 뜨고, 하나를 몇 겹으로 나눌 것인가.
const STATIONS := 26
const RINGS := 14
## 갑판이 앉는 높이(0=용골, 1=뱃전 꼭대기). 이 위가 뱃전 난간이다.
const V_DECK := 0.84

## 배 한 척의 치수. 이것만 갈면 다른 선급이 된다.
const CARAVEL := {
	"loa": 26.0,          # 전장
	"beam": 8.4,          # 최대 폭
	"draft": 2.2,         # 흘수선 아래 깊이
	"freeboard": 3.0,     # 흘수선 위 갑판 높이(중앙)
	"sheer_bow": 1.7,     # 뱃머리가 솟는 높이
	"sheer_stern": 1.3,   # 고물이 솟는 높이
	"stem_rake": 2.0,     # 뱃머리가 앞으로 내미는 거리
	"transom": 0.46,      # 고물 폭 (최대 폭에 대한 비율)
	"bulwark": 0.95,      # 갑판 위 난간 높이
}

# ── 선형 ────────────────────────────────────────────────────────
## t 는 고물(0)에서 뱃머리(1)까지.

## 그 자리의 z. 뱃머리 쪽은 이물대가 앞으로 기울어 조금 더 나간다.
static func _z_at(t: float, s: Dictionary) -> float:
	var half: float = s.loa * 0.5
	return lerpf(half, -half, t)

## 그 자리의 반폭(半幅). 가운데가 가장 넓고 양끝이 여윈다.
##
## 고물은 트랜섬이 있어 폭이 남지만 뱃머리는 이물대 한 줄로 모인다.
static func _half_w(t: float, s: Dictionary) -> float:
	var w: float = s.beam * 0.5
	# 가운데(t≈0.45)가 최대. 사인 곡선을 밑에 깔고 양끝을 따로 줄인다.
	var body := pow(sin(clampf(t, 0.0, 1.0) * PI), 0.62)
	var aft: float = lerpf(float(s.transom), 1.0, smoothstep(0.0, 0.34, t))
	var fwd := lerpf(0.04, 1.0, smoothstep(1.0, 0.62, t))
	return w * body * aft * fwd

## 갑판의 높이. 배는 양끝이 솟는다(시어) — 이게 없으면 뗏목처럼 보인다.
static func _deck_y(t: float, s: Dictionary) -> float:
	var bow: float = s.sheer_bow * pow(smoothstep(0.55, 1.0, t), 1.6)
	var stern: float = s.sheer_stern * pow(smoothstep(0.42, 0.0, t), 1.5)
	return s.freeboard + bow + stern

## 용골의 높이. 가운데가 가장 깊고 양끝이 들린다(로커).
static func _keel_y(t: float, s: Dictionary) -> float:
	var rise := pow(smoothstep(0.62, 1.0, t), 1.7) * 0.62 \
		+ pow(smoothstep(0.30, 0.0, t), 1.6) * 0.42
	return -s.draft * (1.0 - rise)

## 단면의 살집. 가운데는 배가 불러 바닥이 평평하고(지수가 작다),
## 양끝은 V 자로 여윈다(지수가 크다).
static func _fullness(t: float) -> float:
	var mid := 1.0 - absf(t - 0.46) / 0.54
	return lerpf(1.55, 0.52, clampf(mid, 0.0, 1.0))

## 단면 위의 한 점. v 는 용골(0)에서 뱃전 꼭대기(1)까지.
static func _section(t: float, v: float, s: Dictionary) -> Vector3:
	var w := _half_w(t, s)
	var ky := _keel_y(t, s)
	var dy := _deck_y(t, s)
	var top: float = dy + s.bulwark
	# 옆으로 벌어지는 모양
	var x := w * pow(clampf(v, 0.0, 1.0), _fullness(t))
	# 뱃전은 안쪽으로 살짝 오므린다(텀블홈). 이게 있어야 통나무로 안 보인다.
	x *= 1.0 - 0.11 * smoothstep(0.70, 1.0, v)
	var y := lerpf(ky, top, v)
	var z := _z_at(t, s)
	# 이물대가 앞으로 기운다 — 위로 갈수록 더 나간다
	z -= s.stem_rake * smoothstep(0.60, 1.0, t) * v
	return Vector3(x, y, z)

# ── 짓기 ────────────────────────────────────────────────────────
static func build(spec: Dictionary = CARAVEL) -> Node3D:
	var s := CARAVEL.duplicate()
	for k in spec:
		s[k] = spec[k]

	var root := Node3D.new()
	root.name = "Ship"

	root.add_child(_hull(s))
	root.add_child(_deck(s))
	root.add_child(_bulwark_inner(s))
	root.add_child(_transom(s))
	# 폭은 v(용골 0 … 뱃전 1) 단위다. 0.1 이면 뱃전 아래를 통째로 덮어
	# 선체가 새까매진다 — 띠는 얇아야 띠로 보인다.
	root.add_child(_wale(s, 0.63, 0.020, Color("3d2f1e")))
	root.add_child(_wale(s, 0.78, 0.016, Color("3d2f1e")))
	root.add_child(_castle(s, 0.0, 0.30, 2.5, "선미루"))
	root.add_child(_castle(s, 0.80, 1.0, 1.7, "선수루"))
	root.add_child(_rudder(s))

	_rigging(root, s)
	return root

## 껍질. 단면을 죽 늘어놓고 이웃끼리 이어 붙인다.
static func _hull(s: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for i in STATIONS:
		var t := float(i) / float(STATIONS - 1)
		var col: Array = []
		for j in RINGS:
			col.append(_section(t, float(j) / float(RINGS - 1), s))
		grid.append(col)

	for i in STATIONS - 1:
		for j in RINGS - 1:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d: Vector3 = grid[i][j + 1]
			_quad(st, a, b, c, d)
			# 좌현은 거울상. 감는 방향이 뒤집히므로 순서를 바꾼다.
			_quad(st, _flip(d), _flip(c), _flip(b), _flip(a))

	st.generate_normals()
	return _mesh(st, "Hull", Color("7a6040"), 0.84)

## 갑판. 좌우 뱃전 사이를 덮는다.
static func _deck(s: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in STATIONS - 1:
		var t0 := float(i) / float(STATIONS - 1)
		var t1 := float(i + 1) / float(STATIONS - 1)
		var a := _section(t0, V_DECK, s)
		var b := _section(t1, V_DECK, s)
		_quad(st, a, b, _flip(b), _flip(a))
	st.generate_normals()
	return _mesh(st, "Deck", Color("a08b5e"), 0.88)

## 난간 안쪽 벽과 그 위를 덮는 테두리.
static func _bulwark_inner(s: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in STATIONS - 1:
		var t0 := float(i) / float(STATIONS - 1)
		var t1 := float(i + 1) / float(STATIONS - 1)
		for side in [1.0, -1.0]:
			var a0 := _inset(_section(t0, V_DECK, s), side)
			var a1 := _inset(_section(t0, 1.0, s), side)
			var b0 := _inset(_section(t1, V_DECK, s), side)
			var b1 := _inset(_section(t1, 1.0, s), side)
			if side > 0.0:
				_quad(st, a1, b1, b0, a0)
			else:
				_quad(st, a0, b0, b1, a1)
			# 난간 위를 덮는 테두리
			var o0 := _section(t0, 1.0, s)
			var o1 := _section(t1, 1.0, s)
			if side > 0.0:
				_quad(st, o0, o1, b1, a1)
			else:
				_quad(st, _flip(a1), _flip(b1), _flip(o1), _flip(o0))
	st.generate_normals()
	return _mesh(st, "Bulwark", Color("94553a"), 0.86)

## 고물의 평평한 면. 이 시대 배의 인상이 여기서 난다.
static func _transom(s: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RINGS - 1:
		var v0 := float(j) / float(RINGS - 1)
		var v1 := float(j + 1) / float(RINGS - 1)
		var a := _section(0.0, v0, s)
		var b := _section(0.0, v1, s)
		_quad(st, a, b, _flip(b), _flip(a))
	st.generate_normals()
	return _mesh(st, "Transom", Color("6f5433"), 0.86)

## 뱃전을 도는 두꺼운 띠(웨일). 배가 납작해 보이지 않게 잡아준다.
static func _wale(s: Dictionary, v: float, half: float, col: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in STATIONS - 1:
		var t0 := float(i) / float(STATIONS - 1)
		var t1 := float(i + 1) / float(STATIONS - 1)
		var a0 := _bulge(_section(t0, v - half, s))
		var a1 := _bulge(_section(t0, v + half, s))
		var b0 := _bulge(_section(t1, v - half, s))
		var b1 := _bulge(_section(t1, v + half, s))
		_quad(st, a1, b1, b0, a0)
		_quad(st, _flip(a0), _flip(b0), _flip(b1), _flip(a1))
	st.generate_normals()
	return _mesh(st, "Wale", col, 0.92)

## 선수루·선미루. 갑판 위에 한 층 더 올린다.
static func _castle(s: Dictionary, t0: float, t1: float, rise: float,
		name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	var steps := 8

	var floor_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_st := SurfaceTool.new()
	wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pt := func(t: float, up: float) -> Vector3:
		var p := _section(t, V_DECK, s)
		return Vector3(p.x * 0.88, p.y + up, p.z)

	for i in steps:
		var ta: float = lerpf(t0, t1, float(i) / float(steps))
		var tb: float = lerpf(t0, t1, float(i + 1) / float(steps))
		var a: Vector3 = pt.call(ta, rise)
		var b: Vector3 = pt.call(tb, rise)
		_quad(floor_st, a, b, _flip(b), _flip(a))
		# 옆벽
		var a0: Vector3 = pt.call(ta, 0.0)
		var b0: Vector3 = pt.call(tb, 0.0)
		_quad(wall_st, a, b, b0, a0)
		_quad(wall_st, _flip(a0), _flip(b0), _flip(b), _flip(a))

	# 층의 앞뒤를 막는다
	var edge: float = t1 if t0 < 0.5 else t0
	var e_top: Vector3 = pt.call(edge, rise)
	var e_bot: Vector3 = pt.call(edge, 0.0)
	_quad(wall_st, e_top, _flip(e_top), _flip(e_bot), e_bot)

	floor_st.generate_normals()
	wall_st.generate_normals()
	node.add_child(_mesh(floor_st, "바닥", Color("a08b5e"), 0.88))
	node.add_child(_mesh(wall_st, "벽", Color("7d5e38"), 0.86))
	return node

## 고물에 달린 키.
static func _rudder(s: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z: float = s.loa * 0.5 + 0.25
	var pts := [
		Vector3(0.0, 1.2, z), Vector3(0.0, 1.2, z + 0.9),
		Vector3(0.0, -s.draft * 0.95, z + 1.5), Vector3(0.0, -s.draft * 0.95, z + 0.2),
	]
	var th := 0.16
	for side in [th, -th]:
		var q := []
		for p in pts:
			q.append(Vector3(side, p.y, p.z))
		_quad(st, q[0], q[1], q[2], q[3])
		_quad(st, q[3], q[2], q[1], q[0])
	st.generate_normals()
	return _mesh(st, "Rudder", Color("6b5335"), 0.88)

# ── 돛대와 돛 ───────────────────────────────────────────────────
## 돛은 돛 단계에 따라 켜고 끈다. Sails 아래에 단계별로 묶어 둔다.
static func _rigging(root: Node3D, s: Dictionary) -> void:
	var deck_at := func(t: float) -> Vector3:
		var p := _section(t, V_DECK, s)
		return Vector3(0.0, p.y, p.z)

	var main_base: Vector3 = deck_at.call(0.50)
	var fore_base: Vector3 = deck_at.call(0.76)
	var miz_base: Vector3 = deck_at.call(0.20)

	var main_h := 20.0
	var fore_h := 13.5
	var miz_h := 12.0

	root.add_child(_mast(main_base, main_h, 0.48, "큰돛대"))
	root.add_child(_mast(fore_base, fore_h, 0.34, "앞돛대"))
	root.add_child(_mast(miz_base, miz_h, 0.30, "뒷돛대"))
	root.add_child(_top(main_base + Vector3(0, main_h * 0.72, 0), 1.5))

	# 기움돛대
	var stem := _section(1.0, V_DECK, s)
	root.add_child(_spar(stem + Vector3(0, 0.3, 0.4),
		stem + Vector3(0, 3.6, -8.5), 0.24, Color("7c6a46"), "기움돛대"))

	var rig := Node3D.new()
	rig.name = "Sails"
	root.add_child(rig)

	# [돛대밑, 활대높이, 폭, 높이, 배부름, 최소 돛단계]
	var plan := [
		[main_base, main_h * 0.70, 14.6, 8.8, 1.6, 1],   # 큰돛 — 미속부터
		[fore_base, fore_h * 0.74, 10.2, 6.2, 1.1, 2],   # 앞돛 — 순항부터
		[main_base, main_h * 0.97, 9.6, 5.0, 0.9, 3],    # 중간돛 — 전속에서만
		[miz_base, miz_h * 0.80, 8.0, 5.4, 0.9, 3],      # 뒷돛 — 전속에서만
	]
	for e in plan:
		var base: Vector3 = e[0]
		var y: float = base.y + e[1]
		var w: float = e[2]
		var h: float = e[3]
		var belly: float = e[4]
		var stage: int = e[5]
		var at := Vector3(0.0, y, base.z)

		root.add_child(_yard(at, w * 1.06))
		# 몇 단계부터 펴는지는 메타에 적는다. 이름에 적었더니 같은 이름이
		# 겹칠 때 Godot 이 조용히 바꿔 달아, 접혀야 할 돛이 펴져 있었다.
		var set_sail := _sail(at + Vector3(0, -h * 0.5 - 0.3, 0),
			Vector2(w, h), belly)
		set_sail.set_meta("stage", stage)
		set_meta_kind(set_sail, "펼침")
		rig.add_child(set_sail)
		# 접었을 때 활대에 말려 있는 돛뭉치
		var furled := _furled(at + Vector3(0, -0.45, 0), w * 0.92)
		furled.set_meta("stage", stage)
		set_meta_kind(furled, "접힘")
		rig.add_child(furled)

	_ropes(root, s, main_base, main_h, fore_base, fore_h, miz_base, miz_h)

	var pennant := _sail(Vector3(0, main_base.y + main_h + 1.0, main_base.z - 0.9),
		Vector2(2.2, 0.7), 0.25)
	pennant.name = "Pennant"
	pennant.material_override = _mat(Color("b33a2e"), 0.8, true)
	root.add_child(pennant)

static func set_meta_kind(n: Node, kind: String) -> void:
	n.set_meta("kind", kind)

## 돛 단계에 맞춰 편 돛과 접은 돛을 갈아 끼운다.
static func set_sail_stage(root: Node3D, stage: int) -> void:
	var rig := root.get_node_or_null("Sails")
	if rig == null:
		return
	for c in rig.get_children():
		if not c.has_meta("stage"):
			continue
		var need: int = c.get_meta("stage")
		var set_out: bool = stage >= need
		c.visible = set_out if c.get_meta("kind", "") == "펼침" else not set_out

## 삭구. 돛대를 좌우로 잡아주는 줄과 앞뒤로 잡아주는 줄.
static func _ropes(root: Node3D, s: Dictionary, main_b: Vector3, main_h: float,
		fore_b: Vector3, fore_h: float, miz_b: Vector3, miz_h: float) -> void:
	var node := Node3D.new()
	node.name = "삭구"
	root.add_child(node)

	var side_at := func(t: float, out: float) -> Vector3:
		var p := _section(t, V_DECK, s)
		return Vector3(p.x * out, p.y, p.z)

	# 옆줄(시라우드) — 돛대 꼭대기에서 뱃전 서너 곳으로
	var shroud := func(base: Vector3, h: float, t_from: float, t_to: float, n: int) -> void:
		var top := base + Vector3(0, h * 0.86, 0)
		for i in n:
			var f: float = float(i) / float(maxi(n - 1, 1))
			var t: float = lerpf(t_from, t_to, f)
			for sgn in [1.0, -1.0]:
				var anchor: Vector3 = side_at.call(t, 0.98)
				anchor.x *= sgn
				node.add_child(_spar(top, anchor, 0.055, Color("2b2318"), "줄"))

	shroud.call(main_b, main_h, 0.40, 0.60, 3)
	shroud.call(fore_b, fore_h, 0.68, 0.84, 2)
	shroud.call(miz_b, miz_h, 0.12, 0.28, 2)

	# 앞뒤로 잡는 줄(스테이)
	var stem := _section(1.0, 1.0, s)
	node.add_child(_spar(main_b + Vector3(0, main_h * 0.88, 0),
		Vector3(0, stem.y + 0.2, stem.z - 1.2), 0.06, Color("2b2318"), "앞줄"))
	node.add_child(_spar(fore_b + Vector3(0, fore_h * 0.9, 0),
		Vector3(0, stem.y + 1.6, stem.z - 5.5), 0.055, Color("2b2318"), "앞줄"))
	var aft := _section(0.0, 1.0, s)
	node.add_child(_spar(main_b + Vector3(0, main_h * 0.9, 0),
		Vector3(0, aft.y + 0.2, aft.z), 0.055, Color("2b2318"), "뒷줄"))

# ── 조각들 ──────────────────────────────────────────────────────
static func _mast(base: Vector3, height: float, radius: float,
		name: String) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.45
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = cyl
	mi.position = base + Vector3(0, height * 0.5 - 0.4, 0)
	mi.material_override = _mat(Color("7c6a46"), 0.9)
	return mi

## 망대. 돛대 위에 앉는 통.
static func _top(at: Vector3, r: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r * 0.55
	cyl.height = 1.0
	cyl.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.name = "망대"
	mi.mesh = cyl
	mi.position = at
	mi.material_override = _mat(Color("6b5636"), 0.9)
	return mi

static func _yard(at: Vector3, length: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.15
	cyl.height = length
	cyl.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.name = "활대"
	mi.mesh = cyl
	mi.position = at
	mi.rotation.z = PI * 0.5
	mi.material_override = _mat(Color("6d5c3c"), 0.9)
	return mi

## 두 점을 잇는 막대. 돛대 줄과 기움돛대에 쓴다.
static func _spar(a: Vector3, b: Vector3, r: float, col: Color,
		name: String) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 4
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = cyl
	mi.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
	mi.material_override = _mat(col, 0.95)
	return mi

## 바람을 먹어 배부른 가로돛. 평평한 판이면 종이처럼 보인다.
static func _sail(pos: Vector3, sz: Vector2, belly: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 10
	var rows := 6
	var pt := func(i: int, j: int) -> Vector3:
		var u := float(i) / float(cols)
		var v := float(j) / float(rows)
		var w: float = sz.x * lerpf(1.0, 0.88, v)
		var x := (u - 0.5) * w
		# 활대에 매인 위쪽은 팽팽하고 아래는 늘어진다
		var sag: float = sin(PI * u) * sz.y * 0.06 * v
		var y := (0.5 - v) * sz.y - sag
		var z := -belly * sin(PI * u) * sin(PI * v * 0.85 + 0.28)
		return Vector3(x, y, z)
	for j in rows:
		for i in cols:
			_quad(st, pt.call(i, j), pt.call(i, j + 1),
				pt.call(i + 1, j + 1), pt.call(i + 1, j))
	st.generate_normals()
	var mi := _mesh(st, "돛", Color("d8cbaa"), 0.78)
	mi.position = pos
	mi.material_override = _mat(Color("d8cbaa"), 0.78, true)
	return mi

## 접어 활대에 말아둔 돛.
static func _furled(at: Vector3, length: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = length
	cyl.radial_segments = 7
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position = at
	mi.rotation.z = PI * 0.5
	mi.material_override = _mat(Color("cfc3a2"), 0.85)
	return mi

# ── 손 ──────────────────────────────────────────────────────────
static func _flip(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, p.z)

## 뱃전에서 살짝 안으로. 난간 안쪽 벽에 쓴다.
static func _inset(p: Vector3, side: float) -> Vector3:
	return Vector3(absf(p.x) * 0.90 * side, p.y, p.z)

## 뱃전에서 살짝 밖으로. 웨일에 쓴다.
static func _bulge(p: Vector3) -> Vector3:
	return Vector3(p.x + (0.09 if p.x >= 0.0 else -0.09), p.y, p.z)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

static func _mesh(st: SurfaceTool, name: String, col: Color,
		rough: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = _mat(col, rough)
	return mi

static func _mat(col: Color, rough: float, two_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
