class_name Landmarks
extends Node3D

## 땅 위에 선 것들 — 등대, 망루, 마을.
##
## 해안이 색과 무늬만 있으면 항해에 눈금이 없다. 어느 물가나 똑같이 생겼으니
## "저기가 어디인가"를 해도로만 알게 된다. 곶마다 세워둔 것이 하나 있으면
## 그때부터 창밖이 좌표가 된다 — 저 등대가 상비센트다.
##
## 메시는 육지와 똑같이 축척 없는 지리 미터로 만들고, landmark.gdshader 가
## 지형과 같은 함수로 눌러 놓는다.

## 세워둘 것들. 실제 자리다.
##
## 높이(h)는 실물보다 크게 잡았다. 실제 등대(30m)는 3km 밖에서 눌리고 나면
## 1m 가 되어 아무것도 아니다. 지형도 2.6배로 부풀려 그리는 세계이므로
## 여기서도 눈에 걸릴 만큼 키운다.
##
## 밑동의 땅 높이는 적지 않는다. 손으로 짚었더니 지형과 어긋나 물 위에 떴다.
## 지을 때 지형에게 그 자리의 땅을 묻는다(CoastMesh.ground_near).
const MARKS := [
	# 상비센트 곶 — 유럽의 남서쪽 끝. 여기를 돌면 지중해 쪽이다.
	{ "kind": "등대", "lon": -8.996, "lat": 37.023, "h": 190.0 },
	# 카보 다 로카 — 유럽 대륙의 가장 서쪽
	{ "kind": "등대", "lon": -9.498, "lat": 38.780, "h": 170.0 },
	# 트라팔가르 곶
	{ "kind": "등대", "lon": -6.037, "lat": 36.181, "h": 160.0 },
	# 리스보아 — 타호 강 어귀
	{ "kind": "마을", "lon": -9.300, "lat": 38.700, "h": 140.0 },
	{ "kind": "망루", "lon": -9.360, "lat": 38.690, "h": 140.0 },
	# 사그레스 — 항해왕자의 항구
	{ "kind": "마을", "lon": -8.945, "lat": 37.005, "h": 110.0 },
	{ "kind": "마을", "lon": -7.930, "lat": 37.010, "h": 110.0 },
	# 카디스
	{ "kind": "마을", "lon": -6.290, "lat": 36.530, "h": 130.0 },
	# 탕헤르 · 세우타 — 해협 건너
	{ "kind": "마을", "lon": -5.850, "lat": 35.800, "h": 120.0 },
	{ "kind": "망루", "lon": -5.320, "lat": 35.890, "h": 150.0 },
	# 살레
	{ "kind": "마을", "lon": -6.840, "lat": 34.030, "h": 110.0 },
]

const WHITE := Color(0.86, 0.84, 0.78)
const RED := Color(0.62, 0.26, 0.20)
const STONE := Color(0.66, 0.62, 0.53)
const ROOF := Color(0.55, 0.28, 0.19)
const DARK := Color(0.24, 0.22, 0.20)

var _mesh: MeshInstance3D
var _mat: ShaderMaterial

var _coast: CoastMesh

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Marks"

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/landmark.gdshader")
	_mat.set_shader_parameter("near_scale", Geo.LAND_NEAR_SCALE)
	_mat.set_shader_parameter("far_scale", Geo.LAND_SCALE)
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 셰이더가 정점을 옮기므로 원래 상자로는 화면 밖으로 판정되어 사라진다
	_mesh.custom_aabb = AABB(Vector3(-6000, -400, -6000), Vector3(12000, 800, 12000))
	add_child(_mesh)

## 지형이 다 서고 나서 부른다. 그 자리의 땅을 물어 표지물을 세운다.
func plant(coast: CoastMesh) -> void:
	_coast = coast
	_mesh.mesh = _build()

func follow(ship_world: Vector3, ship_lon: float, ship_lat: float) -> void:
	global_transform = Transform3D(Basis.IDENTITY,
		Vector3(ship_world.x, 0.0, ship_world.z))
	if _mat:
		var here := Geo.to_metres(ship_lon, ship_lat)
		_mat.set_shader_parameter("ship_geo", Vector2(here.x, here.z))

func sky_material() -> ShaderMaterial:
	return _mat

# ── 짓기 ────────────────────────────────────────────────────────
func _build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in MARKS:
		var at := Geo.to_metres(m.lon, m.lat)
		# 등대와 망루는 높은 데 선다. 마을은 물가에 앉는다.
		var high: bool = m.kind != "마을"
		var g := _coast.ground_near(Vector2(at.x, at.z), 6000.0, high)
		if g.x == INF:
			continue
		var base := Vector2(g.x, g.z)
		var ground: float = g.y
		match m.kind:
			"등대":
				_lighthouse(st, base, ground, m.h)
			"망루":
				_tower(st, base, ground, m.h)
			_:
				_town(st, base, ground, m.h)
	st.generate_normals()
	return st.commit()

## 등대. 위로 갈수록 가늘어지는 흰 탑에 붉은 띠, 꼭대기에 검은 등실.
func _lighthouse(st: SurfaceTool, base: Vector2, ground: float, h: float) -> void:
	var r := h * 0.080
	_cyl(st, base, ground, ground + h * 0.86, r, r * 0.62, WHITE, 10)
	# 붉은 띠 두 줄 — 이것이 있어야 멀리서도 등대로 읽힌다
	_cyl(st, base, ground + h * 0.30, ground + h * 0.42, r * 0.90, r * 0.85, RED, 10)
	_cyl(st, base, ground + h * 0.58, ground + h * 0.70, r * 0.78, r * 0.74, RED, 10)
	# 등실 — 조금 넓게 내밀어 처마를 만든다
	_cyl(st, base, ground + h * 0.86, ground + h * 1.0, r * 0.95, r * 0.80, DARK, 10)
	_cyl(st, base, ground + h * 1.0, ground + h * 1.06, r * 0.5, 0.0, DARK, 8)

## 망루. 위가 조금 벌어진 네모난 돌탑.
func _tower(st: SurfaceTool, base: Vector2, ground: float, h: float) -> void:
	var r := h * 0.16
	_cyl(st, base, ground, ground + h * 0.88, r, r * 0.88, STONE, 4)
	_cyl(st, base, ground + h * 0.88, ground + h, r * 1.15, r * 1.10, STONE, 4)

## 마을. 흰 벽에 붉은 기와를 인 집 여럿과 그 사이에 솟은 종탑 하나.
##
## 한 채씩 알아볼 거리가 아니다. 눈에 남는 것은 무리의 실루엣과, 그 위로
## 하나만 솟은 탑이다. 그래서 그렇게 짓는다.
func _town(st: SurfaceTool, base: Vector2, ground: float, h: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.x) * 7919 + int(base.y)
	var spread := h * 1.15
	for i in 11:
		var off := Vector2(rng.randf_range(-spread, spread),
			rng.randf_range(-spread * 0.6, spread * 0.6))
		var bh := h * rng.randf_range(0.24, 0.38)
		var bw := h * rng.randf_range(0.20, 0.30)
		# 위로만 흔든다. 아래로 흔들면 집이 땅에 파묻힌다.
		var lift := ground + rng.randf_range(0.0, h * 0.06)
		_cyl(st, base + off, lift, lift + bh, bw, bw, WHITE, 4)
		# 기와지붕
		_cyl(st, base + off, lift + bh, lift + bh + h * 0.10, bw * 1.18, 0.0, ROOF, 4)
	# 종탑
	var tw := h * 0.16
	_cyl(st, base, ground, ground + h, tw, tw * 0.92, WHITE, 4)
	_cyl(st, base, ground + h, ground + h * 1.16, tw * 1.1, 0.0, ROOF, 4)

# ── 손 ──────────────────────────────────────────────────────────
## 밑동이 base 에 있는 원기둥(또는 각기둥) 하나.
##
## 정점의 xz 는 지리 좌표 그대로 넣고, 그 물건이 선 자리를 UV2 에 실어 보낸다.
## 셰이더가 둘의 차이로 "물건 안에서의 자리"를 알아내 가로만 부풀린다.
func _cyl(st: SurfaceTool, base: Vector2, y0: float, y1: float,
		r0: float, r1: float, col: Color, sides: int) -> void:
	var ring := func(r: float, y: float, i: int) -> Vector3:
		var a := TAU * float(i) / float(sides) + (PI * 0.25 if sides == 4 else 0.0)
		return Vector3(base.x + cos(a) * r, y, base.y + sin(a) * r)

	st.set_color(col)
	st.set_uv2(base)
	for i in sides:
		var j := (i + 1) % sides
		var a0: Vector3 = ring.call(r0, y0, i)
		var b0: Vector3 = ring.call(r0, y0, j)
		var a1: Vector3 = ring.call(r1, y1, i)
		var b1: Vector3 = ring.call(r1, y1, j)
		if r1 > 0.0001:
			st.add_vertex(a0); st.add_vertex(a1); st.add_vertex(b1)
			st.add_vertex(a0); st.add_vertex(b1); st.add_vertex(b0)
			# 위를 덮는다
			var top := Vector3(base.x, y1, base.y)
			st.add_vertex(top); st.add_vertex(b1); st.add_vertex(a1)
		else:
			# 뿔 — 지붕과 등대 꼭대기
			var tip := Vector3(base.x, y1, base.y)
			st.add_vertex(a0); st.add_vertex(tip); st.add_vertex(b0)
