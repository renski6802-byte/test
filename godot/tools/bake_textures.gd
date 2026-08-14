extends SceneTree

## 재질 지도를 구워 파일로 남긴다.
##
##   godot --headless --path godot --script res://tools/bake_textures.gd
##
## 왜 받아오지 않고 굽는가 —
## 이 환경의 망 정책이 Poly Haven·ambientCG 를 막는다. GitHub 원본 파일과
## npm 만 열려 있는데, 거기서 긁어오는 텍스처는 출처와 저작권이 흐리다.
## 그리고 우리 세계는 텍스처를 UV 가 아니라 지리 좌표로 입힌다 — 수백 km 를
## 가로지르며 같은 장을 되풀이하므로 사진은 타일 자국이 그대로 드러난다.
## 여러 배율의 잡음을 겹쳐 만드는 편이 이 문제에 원래 더 맞는다.
##
## 굽는 것: 판자 · 돛천 · 회벽 · 기와 · 모래 · 풀 · 바위.
## 각각 색(albedo)과 요철(normal) 두 장. 요철은 높이밭에서 미분해 만든다.

const SIZE := 512
const OUT := "res://assets/tex/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_bake("plank", _plank)
	_bake("canvas", _canvas)
	_bake("stucco", _stucco)
	_bake("tile", _tile)
	_bake("sand", _sand)
	_bake("grass", _grass)
	_bake("rock", _rock)
	print("구움: ", SIZE, "px × 7종")
	quit()

## 한 종류를 굽는다. 넘겨받은 함수가 그 자리의 [색, 높이] 를 돌려준다.
func _bake(name: String, fn: Callable) -> void:
	var alb := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var hgt := PackedFloat32Array()
	hgt.resize(SIZE * SIZE)

	for y in SIZE:
		for x in SIZE:
			var r: Array = fn.call(float(x) / SIZE, float(y) / SIZE)
			alb.set_pixel(x, y, r[0])
			hgt[y * SIZE + x] = r[1]

	alb.save_png(OUT + name + "_albedo.png")
	_normal_from_height(hgt).save_png(OUT + name + "_normal.png")

## 높이밭을 기울기로 바꿔 법선 지도를 만든다.
## 가장자리는 감아 돌린다 — 이어 붙였을 때 자국이 남지 않도록.
func _normal_from_height(h: PackedFloat32Array, strength := 2.4) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var l: float = h[y * SIZE + (x - 1 + SIZE) % SIZE]
			var r: float = h[y * SIZE + (x + 1) % SIZE]
			var u: float = h[((y - 1 + SIZE) % SIZE) * SIZE + x]
			var d: float = h[((y + 1) % SIZE) * SIZE + x]
			var n := Vector3((l - r) * strength, (u - d) * strength, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return img

# ── 잡음 ────────────────────────────────────────────────────────
## 되풀이 주기가 있는 난수. 주기를 넘기면 같은 값이 나와야 이어 붙일 수 있다.
static func _hash(x: int, y: int, period: int, seed: int) -> float:
	var xi := ((x % period) + period) % period
	var yi := ((y % period) + period) % period
	var h := xi * 374761393 + yi * 668265263 + seed * 144665
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)

## 주기가 있는 값 잡음.
static func _vnoise(p: Vector2, period: int, seed := 0) -> float:
	var x0 := int(floor(p.x))
	var y0 := int(floor(p.y))
	var fx: float = p.x - x0
	var fy: float = p.y - y0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(x0, y0, period, seed)
	var b := _hash(x0 + 1, y0, period, seed)
	var c := _hash(x0, y0 + 1, period, seed)
	var d := _hash(x0 + 1, y0 + 1, period, seed)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)

## 여러 배율을 겹친 잡음. base 는 한 변에 몇 칸을 깔 것인가.
static func _fbm(uv: Vector2, base: int, octaves: int, seed := 0) -> float:
	var sum := 0.0
	var amp := 0.5
	var norm := 0.0
	var freq := base
	for i in octaves:
		sum += _vnoise(uv * float(freq), freq, seed + i * 71) * amp
		norm += amp
		amp *= 0.5
		freq *= 2
	return sum / norm

# ── 판자 ────────────────────────────────────────────────────────
## 선체와 갑판. 가로로 누운 널 여섯 장, 이음매에 홈, 결은 널을 따라 흐른다.
func _plank(u: float, v: float) -> Array:
	var rows := 6.0
	var fv := v * rows
	var board := int(floor(fv))
	var t: float = fv - board                      # 널 안에서의 자리(0…1)

	# 널마다 색이 조금씩 다르다. 이게 없으면 한 장짜리 판때기로 보인다.
	var tone := _hash(board, 0, int(rows), 11)
	var base := Color(0.52, 0.40, 0.26).lerp(Color(0.40, 0.30, 0.19), tone)

	# 결 — 널을 따라 길게 늘인 잡음
	var grain := _fbm(Vector2(u * 1.5, fv * 9.0), 24, 4, board * 7)
	var fine := _fbm(Vector2(u * 2.0, fv * 6.0), 96, 2, board * 13)
	var wood: float = 0.80 + 0.34 * grain + 0.10 * fine

	# 옹이 — 널마다 한둘. 결이 그 둘레를 돈다.
	var knot_u := _hash(board, 3, 64, 29)
	var kd := Vector2((u - knot_u) * 1.6, (t - 0.5) * 0.42).length()
	var knot: float = 1.0 - smoothstep(0.0, 0.085, kd)
	wood -= knot * (0.34 + 0.14 * sin(kd * 160.0))

	# 이음매 홈
	var seam: float = smoothstep(0.055, 0.0, t) + smoothstep(0.945, 1.0, t)
	var h: float = 0.62 + 0.24 * grain - seam * 0.55 - knot * 0.22
	# 못 자국 — 널 끝에 두 개씩
	var nail: float = 1.0 - smoothstep(0.0, 0.012,
		Vector2(fposmod(u + 0.06, 0.5) - 0.06, t - 0.16).length())
	h -= nail * 0.35

	var col := base * clampf(wood - seam * 0.42 - nail * 0.25, 0.15, 1.35)
	return [col.clamp(), h]

# ── 돛천 ────────────────────────────────────────────────────────
## 씨실과 날실이 엇갈린 올, 그리고 폭마다 꿰맨 이음선.
func _canvas(u: float, v: float) -> Array:
	var weave: float = sin(u * TAU * 190.0) * sin(v * TAU * 190.0)
	var slub := _fbm(Vector2(u, v), 40, 3, 5)          # 굵기가 고르지 않은 실
	# 천을 폭마다 이어 붙인 자리
	var seam: float = smoothstep(0.018, 0.0, absf(fposmod(u, 0.25) - 0.125) - 0.108)
	var soil := _fbm(Vector2(u, v), 6, 3, 91)          # 오래 쓴 천의 얼룩

	var base := Color(0.86, 0.82, 0.70).lerp(Color(0.70, 0.66, 0.55), soil * 0.55)
	var shade: float = 0.94 + 0.06 * weave + 0.10 * (slub - 0.5)
	var col := base * (shade - seam * 0.10)
	return [col.clamp(), 0.5 + 0.05 * weave + 0.18 * (slub - 0.5) + seam * 0.35]

# ── 회벽 ────────────────────────────────────────────────────────
## 이베리아의 흰 벽. 고르지 않게 바른 자국과 군데군데 벗겨진 자리.
func _stucco(u: float, v: float) -> Array:
	var broad := _fbm(Vector2(u, v), 5, 4, 3)          # 크게 바른 결
	var fine := _fbm(Vector2(u, v), 60, 3, 17)         # 잔 오돌토돌
	var pit: float = smoothstep(0.72, 0.86, _fbm(Vector2(u, v), 22, 2, 41))

	var white := Color(0.90, 0.87, 0.80)
	var bare := Color(0.66, 0.58, 0.48)                # 벗겨져 드러난 흙
	var col: Color = white.lerp(bare, pit * 0.7) * (0.93 + 0.12 * broad + 0.06 * fine)
	return [col.clamp(), 0.55 + 0.18 * broad + 0.10 * fine - pit * 0.30]

# ── 기와 ────────────────────────────────────────────────────────
## 반원통을 엇갈려 인 지붕.
func _tile(u: float, v: float) -> Array:
	var rows := 7.0
	var cols := 9.0
	var fv := v * rows
	var row := int(floor(fv))
	var tv: float = fv - row
	# 한 줄씩 반 칸 밀어 인다
	var fu: float = u * cols + (0.5 if row % 2 == 1 else 0.0)
	var col_i := int(floor(fu))
	var tu: float = fu - col_i

	# 반원통 — 가운데가 솟고 양옆이 골이다
	var arc: float = sin(clampf(tu, 0.0, 1.0) * PI)
	var lap: float = smoothstep(0.0, 0.16, tv)          # 아래 줄에 겹쳐 덮은 자리

	var tone := _hash(col_i, row, 64, 23)
	var base := Color(0.62, 0.32, 0.20).lerp(Color(0.45, 0.24, 0.17), tone)
	var moss: float = smoothstep(0.70, 0.92, _fbm(Vector2(u, v), 9, 3, 77))
	base = base.lerp(Color(0.36, 0.36, 0.24), moss * 0.5)

	var shade: float = 0.62 + 0.46 * arc
	shade *= 0.72 + 0.28 * lap                          # 겹친 아래가 그늘진다
	return [(base * shade).clamp(), arc * 0.7 + lap * 0.25]

# ── 땅 ──────────────────────────────────────────────────────────
func _sand(u: float, v: float) -> Array:
	var ripple: float = sin((u * 9.0 + _fbm(Vector2(u, v), 4, 2, 9) * 3.0) * TAU)
	var grit := _fbm(Vector2(u, v), 150, 2, 61)
	var col := Color(0.72, 0.65, 0.50) * (0.90 + 0.10 * ripple + 0.14 * (grit - 0.5))
	return [col.clamp(), 0.5 + 0.14 * ripple + 0.22 * (grit - 0.5)]

func _grass(u: float, v: float) -> Array:
	var clump := _fbm(Vector2(u, v), 7, 4, 31)
	var blade := _fbm(Vector2(u * 1.0, v * 4.0), 110, 2, 53)
	var col: Color = Color(0.30, 0.38, 0.19).lerp(Color(0.46, 0.46, 0.26), clump)
	col *= 0.86 + 0.28 * blade
	return [col.clamp(), 0.45 + 0.30 * clump + 0.22 * (blade - 0.5)]

func _rock(u: float, v: float) -> Array:
	var strata: float = sin((v * 6.0 + _fbm(Vector2(u, v), 5, 3, 13) * 2.2) * TAU)
	var crack: float = smoothstep(0.80, 0.93, _fbm(Vector2(u, v), 16, 4, 67))
	var col: Color = Color(0.47, 0.44, 0.39).lerp(Color(0.33, 0.31, 0.28),
		smoothstep(-0.3, 0.5, strata))
	col = col * (0.92 + 0.14 * _fbm(Vector2(u, v), 90, 2, 5)) - Color(1, 1, 1) * crack * 0.16
	return [col.clamp(), 0.55 + 0.20 * strata - crack * 0.45]
