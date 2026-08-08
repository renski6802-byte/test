class_name PortraitView
extends Control

## 말하는 사람의 옆얼굴. 정면보다 어긋날 여지가 적고, 시대 메달 초상의 감각이 난다.
## 자리를 채워두는 그림이라 나중에 진짜 초상으로 갈아끼울 곳이다.

func _ready() -> void:
	# 컨테이너가 크기를 정해준 뒤 다시 그려야 한다. 안 그러면 배치 전 크기로 한 번 그린 게 남는다.
	resized.connect(queue_redraw)

var who := "주앙":
	set(v):
		if who != v:
			who = v
			queue_redraw()

## 100 x 124 기준으로 잡은 옆얼굴 실루엣 (오른쪽을 본다)
const BUST := [
	Vector2(18, 124), Vector2(21, 104), Vector2(29, 95), Vector2(37, 90),
	Vector2(37, 76), Vector2(31, 71), Vector2(27, 61), Vector2(27, 49),
	Vector2(32, 39), Vector2(42, 33), Vector2(55, 33), Vector2(63, 39),
	Vector2(67, 47), Vector2(71, 55), Vector2(75, 59), Vector2(79, 65),
	Vector2(72, 67), Vector2(75, 71), Vector2(70, 77), Vector2(66, 85),
	Vector2(57, 91), Vector2(49, 93), Vector2(58, 97), Vector2(68, 102),
	Vector2(78, 112), Vector2(82, 124),
]

const CAP := [
	Vector2(26, 47), Vector2(30, 36), Vector2(41, 30), Vector2(56, 30),
	Vector2(65, 36), Vector2(66, 44), Vector2(56, 37), Vector2(41, 36),
	Vector2(31, 41),
]

const TURBAN := [
	Vector2(24, 48), Vector2(25, 37), Vector2(33, 29), Vector2(47, 26),
	Vector2(60, 29), Vector2(67, 37), Vector2(67, 46), Vector2(58, 38),
	Vector2(44, 35), Vector2(31, 40),
]

func _draw() -> void:
	var r := size
	if r.x < 4.0 or r.y < 4.0:
		return

	draw_rect(Rect2(Vector2.ZERO, r), Pal.BAND_2)

	var moor := who == "유수프"
	var s: float = minf(r.x / 88.0, r.y / 112.0)
	var off := Vector2((r.x - 100.0 * s) * 0.5, r.y - 124.0 * s)

	# 배경 아치
	var arch := PackedVector2Array()
	arch.append(Vector2(8, 124))
	for i in 17:
		var a := PI + PI * float(i) / 16.0
		arch.append(Vector2(50.0 + cos(a) * 42.0, 62.0 + sin(a) * 44.0))
	arch.append(Vector2(92, 124))
	_fill(arch, Pal.BAND, s, off)

	_fill(_pack(BUST), Pal.BAND_INK.lerp(Color('c9b48a'), 0.30), s, off)
	_fill(_pack(TURBAN if moor else CAP),
		Color("c7bca0") if moor else Color("3b2c1c"), s, off)

	# 이름
	var font := get_theme_default_font()
	if font:
		draw_string(font, Vector2(0.0, r.y - 4.0), who,
			HORIZONTAL_ALIGNMENT_CENTER, r.x, 11, Pal.BAND_FAINT)

func _pack(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p)
	return out

func _fill(pts: PackedVector2Array, col: Color, s: float, off: Vector2) -> void:
	if pts.size() < 3:
		return
	var scaled := PackedVector2Array()
	for p in pts:
		scaled.append(p * s + off)
	Draw2D.fill_poly(get_canvas_item(), scaled, col)
