class_name CoastMesh
extends Node3D

## 해안선 자료를 바다에서 본 땅으로 세운다.
##
## 예전엔 해안선 점 오십 개로 띠 두 장을 세웠다. 실루엣만 있고 표면이 없어서
## 바다에 셰이더를 붙이기 전과 같은 상태였다. 지금은 해안선을 따라 조밀한 격자를
## 깔고 노이즈로 능선과 골짜기를 실제로 깎는다. 표면은 land.gdshader 가 맡는다.
##
## 육지는 바다와 다른 축척을 쓴다. 그래서 메시를 축척 없는 지리 미터로 만들어
## 두고, 매 프레임 배를 기준으로 눌러 놓는다. 가로만 누르고 높이는 따로 누른다.

const ALONG_STEP := 500.0        ## 해안을 따라 몇 미터마다 자를 것인가(지리)
const ROWS := 22                 ## 물가에서 안쪽으로 몇 겹
## 가장 안쪽까지의 거리(지리). 짧으면 땅의 끝이 하늘과 만나 자른 자국이 보인다.
## 멀리까지 깔아두고 대기 원근으로 녹인다.
const INLAND_MAX := 60000.0
## 해안선을 노이즈로 흔들면 곶과 만이 생겨 보기 좋지만, 눈에 보이는 물가와
## 충돌 판정선이 어긋나 배가 육지 위로 올라간다. 흔들기는 능선에만 맡긴다.
const SHORE_WANDER := 0.0

var _mesh: MeshInstance3D
var _mat: ShaderMaterial

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Land"
	_mesh.mesh = _build()

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/land.gdshader")
	_mat.set_shader_parameter("grain", _grain(256))
	_mat.set_shader_parameter("near_scale", Geo.LAND_NEAR_SCALE)
	_mat.set_shader_parameter("far_scale", Geo.LAND_SCALE)
	_mesh.material_override = _mat
	# 그림자를 끈다. 눌린 육지는 배 바로 옆에 선 벽이나 마찬가지여서, 켜두면
	# 한낮에도 배가 육지 그늘에 들어가 새까매진다.
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 셰이더가 정점을 옮기므로 원래 상자로는 화면 밖으로 판정되어 사라진다
	_mesh.custom_aabb = AABB(Vector3(-6000, -400, -6000), Vector3(12000, 800, 12000))
	add_child(_mesh)

## 배가 어디에 있는지 알려주면 그 자리를 기준으로 육지를 눌러 놓는다.
## 누르는 일은 셰이더가 한다. 여기서는 배 자리로 옮기고 그 자리를 알려주기만 한다.
func follow(ship_world: Vector3, ship_lon: float, ship_lat: float, t: float) -> void:
	global_transform = Transform3D(Basis.IDENTITY,
		Vector3(ship_world.x, 0.0, ship_world.z))
	if _mat:
		var here := Geo.to_metres(ship_lon, ship_lat)
		_mat.set_shader_parameter("ship_geo", Vector2(here.x, here.z))
		_mat.set_shader_parameter("wave_time", t)

## 하늘 셰이더와 같은 값을 봐야 육지가 물러나는 색이 하늘과 어긋나지 않는다.
func sky_material() -> ShaderMaterial:
	return _mat

# ── 노이즈 ──────────────────────────────────────────────────────
## 자리만 넣으면 늘 같은 값이 나오는 난수. 지형을 저장하지 않고 다시 만들 수 있다.
static func _hash2(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFFFF) / 16777215.0

static func _vnoise(p: Vector2) -> float:
	var i := Vector2(floor(p.x), floor(p.y))
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash2(int(i.x), int(i.y))
	var b := _hash2(int(i.x) + 1, int(i.y))
	var c := _hash2(int(i.x), int(i.y) + 1)
	var d := _hash2(int(i.x) + 1, int(i.y) + 1)
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

static func _fbm(p: Vector2, octaves: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var q := p
	for _i in octaves:
		sum += _vnoise(q) * amp
		q *= 2.03
		amp *= 0.5
	return sum

## 셰이더가 쓸 타일 노이즈. 세 채널에 서로 다른 결을 담는다.
static func _grain(size: int) -> ImageTexture:
	var img := Image.create_empty(size, size, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991117
	# 옥타브의 주기가 텍스처 크기를 정확히 나눠야 타일 경계가 이어진다
	var layers := [[6, 12, 24], [10, 20, 40], [16, 32, 64]]
	var grids: Array = []
	for chan in layers:
		var per_chan: Array = []
		for n in chan:
			var g := PackedFloat32Array()
			g.resize(n * n)
			for i in n * n:
				g[i] = rng.randf()
			per_chan.append([n, g])
		grids.append(per_chan)

	var sample := func(cell: Array, u: float, v: float) -> float:
		var n: int = cell[0]
		var g: PackedFloat32Array = cell[1]
		var fx := u * float(n)
		var fy := v * float(n)
		var x0 := int(fx) % n
		var y0 := int(fy) % n
		var x1 := (x0 + 1) % n
		var y1 := (y0 + 1) % n
		var tx: float = fx - floor(fx)
		var ty: float = fy - floor(fy)
		tx = tx * tx * (3.0 - 2.0 * tx)
		ty = ty * ty * (3.0 - 2.0 * ty)
		return lerpf(lerpf(g[y0 * n + x0], g[y0 * n + x1], tx),
			lerpf(g[y1 * n + x0], g[y1 * n + x1], tx), ty)

	for y in size:
		var v := float(y) / float(size)
		for x in size:
			var u := float(x) / float(size)
			var c := Color()
			for ch in 3:
				var s := 0.0
				var amp := 0.6
				for cell in grids[ch]:
					s += sample.call(cell, u, v) * amp
					amp *= 0.5
				c[ch] = clampf(s / 1.05, 0.0, 1.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ── 형태 ────────────────────────────────────────────────────────
## 안쪽으로 t(0~1) 만큼 들어간 자리의 높이 비율. 지형 종류가 모양을 정한다.
static func _profile(t: float, kind: int) -> float:
	match kind:
		Geo.CLIFF:
			# 물가에서 곧장 솟았다가 완만해진다
			return smoothstep(0.0, 0.09, t) * (0.82 + 0.18 * t)
		Geo.MOUNTAIN:
			return smoothstep(0.0, 0.42, t) * (0.55 + 0.45 * t)
		Geo.SAND:
			return pow(t, 0.75)
		_:
			return smoothstep(0.0, 0.30, t) * (0.75 + 0.25 * t)

static func _ridge_strength(kind: int) -> float:
	match kind:
		Geo.CLIFF:
			return 0.55
		Geo.MOUNTAIN:
			return 0.95
		Geo.SAND:
			return 0.18
		_:
			return 0.40

## 이 자리에서 뭍 쪽으로 얼마나 뻗을 수 있는가(m).
##
## 곶에서는 두 구간의 뭍 방향이 90도 어긋난다. 그런데도 모두 60km 씩 밀어붙이면
## 상비센트 곶 같은 데서 안쪽 줄이 부챗살처럼 퍼져 나가, 바다 한가운데에
## 130m 짜리 절벽이 서 버린다. 실제로 뭍인 데까지만 뻗게 자른다.
static func _reach(at: Vector3, nrm: Vector3) -> float:
	var lo := 0.0
	var hi := INLAND_MAX
	var g := Geo.geo_of_metres(at.x + nrm.x * hi, at.z + nrm.z * hi)
	if Geo.on_land(g.x, g.y):
		return hi
	for _i in 7:                      # 이분법. 60km 를 500m 아래까지 좁힌다.
		var mid := (lo + hi) * 0.5
		var q := Geo.geo_of_metres(at.x + nrm.x * mid, at.z + nrm.z * mid)
		if Geo.on_land(q.x, q.y):
			lo = mid
		else:
			hi = mid
	return maxf(lo, 1200.0)

func _build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for coast in [Geo.COAST_IB, Geo.COAST_AF]:
		_add_coast(st, coast, Geo.coast_types(coast))
	return st.commit()

## 해안선을 따라 조밀한 격자를 깔고 깎는다.
static func _add_coast(st: SurfaceTool, coast: Array, kinds: Array) -> void:
	var n := coast.size()
	if n < 2:
		return

	# 해안선을 일정 간격으로 다시 뜬다. 원본 점 사이가 10~20km 라 그대로는 너무 성기다.
	var pts: Array = []          # {pos, nrm, kind, amp}
	for i in range(n - 1):
		var g0: Vector2 = coast[i]
		var g1: Vector2 = coast[i + 1]
		var p0 := Geo.to_metres(g0.x, g0.y)
		var p1 := Geo.to_metres(g1.x, g1.y)
		var span := p0.distance_to(p1)
		var steps: int = maxi(1, int(span / ALONG_STEP))

		var k0: int = kinds[i] if i < kinds.size() else Geo.LOW
		var k1: int = kinds[i + 1] if i + 1 < kinds.size() else k0
		var t0: Array = Geo.TERRAIN[k0]
		var t1: Array = Geo.TERRAIN[k1]

		# 어느 쪽이 뭍인지 실제로 찍어보고 정한다
		var dir := (p1 - p0)
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3(0, 0, -1)
		var nrm := Vector3(-dir.z, 0.0, dir.x)
		var mid := (g0 + g1) * 0.5
		var probe := Geo.to_geo(Geo.to_world(mid.x, mid.y) + nrm * 3000.0 * Geo.WORLD_SCALE)
		if not Geo.on_land(probe.x, probe.y):
			nrm = -nrm

		for s in steps:
			var f := float(s) / float(steps)
			var pos := p0.lerp(p1, f)
			var kind: int = k0 if f < 0.5 else k1
			var lo: float = lerpf(float(t0[0]), float(t1[0]), f)
			var hi: float = lerpf(float(t0[1]), float(t1[1]), f)
			var wobble := _fbm(Vector2(pos.x, pos.z) / 5200.0, 3)
			var amp: float = lerpf(lo, hi, wobble) * Geo.LAND_HEIGHT_SCALE
			# 해안선 자체를 흔들어 곶과 만을 만든다
			var wander := (_fbm(Vector2(pos.x, pos.z) / 9000.0, 2) - 0.5) * 2.0
			var at: Vector3 = pos + nrm * wander * SHORE_WANDER
			pts.append({
				"pos": at,
				"nrm": nrm,
				"kind": kind,
				"amp": amp,
				"reach": _reach(at, nrm),
			})

	if pts.size() < 2:
		return

	# 격자를 세운다. 안쪽으로 갈수록 간격을 넓혀 물가 가까이를 촘촘하게.
	var cols := pts.size()
	var grid: Array = []
	for r in ROWS:
		var t := float(r) / float(ROWS - 1)
		var inland := INLAND_MAX * pow(t, 1.8)
		var row: Array = []
		for c in cols:
			var e: Dictionary = pts[c]
			var base: Vector3 = e.pos + e.nrm * (inland * e.reach / INLAND_MAX)
			var h: float = e.amp * _profile(t, e.kind)
			# 능선과 골짜기. 물가에서는 0 이라야 해안선이 깨끗하다.
			var mask := smoothstep(0.0, 0.14, t)
			var q := Vector2(base.x, base.z)
			var ridge := (_fbm(q / 3400.0, 4) - 0.45) * 2.0
			var fine := (_fbm(q / 900.0, 3) - 0.5) * 0.9
			h += (ridge + fine) * e.amp * _ridge_strength(e.kind) * mask
			row.append(Vector3(base.x, maxf(h, 0.0), base.z))
		grid.append(row)

	# 법선은 격자 이웃에서 바로 구한다. generate_normals 는 이 크기에서 느리다.
	var nrms: Array = []
	for r in ROWS:
		var row: Array = []
		for c in cols:
			var p: Vector3 = grid[r][c]
			var pa: Vector3 = grid[r][maxi(c - 1, 0)]
			var pb: Vector3 = grid[r][mini(c + 1, cols - 1)]
			var pc: Vector3 = grid[maxi(r - 1, 0)][c]
			var pd: Vector3 = grid[mini(r + 1, ROWS - 1)][c]
			var nv := (pb - pa).cross(pd - pc).normalized()
			if nv.y < 0.0:
				nv = -nv
			row.append(nv if nv.length() > 0.001 else Vector3.UP)
		nrms.append(row)

	# 바위 비율을 꼭짓점 색에 실어 셰이더에 넘긴다
	var rock_of := func(kind: int) -> float:
		match kind:
			Geo.CLIFF:
				return 0.85
			Geo.MOUNTAIN:
				return 0.65
			Geo.SAND:
				return 0.05
			_:
				return 0.25

	for r in range(ROWS - 1):
		for c in range(cols - 1):
			var kc: float = rock_of.call(pts[c].kind)
			var kn: float = rock_of.call(pts[c + 1].kind)
			_tri(st, grid[r][c], nrms[r][c], kc, grid[r][c + 1], nrms[r][c + 1], kn,
				grid[r + 1][c + 1], nrms[r + 1][c + 1], kn)
			_tri(st, grid[r][c], nrms[r][c], kc, grid[r + 1][c + 1], nrms[r + 1][c + 1], kn,
				grid[r + 1][c], nrms[r + 1][c], kc)

static func _tri(st: SurfaceTool, a: Vector3, na: Vector3, ka: float,
		b: Vector3, nb: Vector3, kb: float, c: Vector3, nc: Vector3, kc: float) -> void:
	st.set_color(Color(ka, 0, 0)); st.set_normal(na); st.add_vertex(a)
	st.set_color(Color(kb, 0, 0)); st.set_normal(nb); st.add_vertex(b)
	st.set_color(Color(kc, 0, 0)); st.set_normal(nc); st.add_vertex(c)
