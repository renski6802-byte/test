class_name CompassView
extends Control

## 침로와 바람을 한 다이얼에 겹쳐 그린다.
##
## 뱃머리는 언제나 위를 향한다. 그래서 바람 화살표가 놓인 자리가 곧 "내 배에 대한" 바람이고,
## 자유 시점이라 화면의 위쪽이 앞이 아니게 되어도 침로를 잃지 않는다.
## 숫자를 읽지 않아도 되도록 고리 색이 순풍(초록)에서 역풍(빨강)으로 물든다.

func _ready() -> void:
	resized.connect(queue_redraw)

var heading := 0.0
var wind_bearing := 0.0
var ordered := 0.0

func set_state(hdg: float, wind: float, order := NAN) -> void:
	var ord: float = hdg if is_nan(order) else order
	if is_equal_approx(hdg, heading) and is_equal_approx(wind, wind_bearing) \
			and is_equal_approx(ord, ordered):
		return
	heading = hdg
	wind_bearing = wind
	ordered = ord
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var rad: float = minf(size.x, size.y) * 0.5 - 3.0
	if rad < 8.0:
		return

	var rel := cos(deg_to_rad(heading - wind_bearing))
	var k := (rel + 1.0) * 0.5
	var ring := Color(0.74, 0.27, 0.23).lerp(Color(0.27, 0.72, 0.55), k)

	draw_arc(c, rad, 0.0, TAU, 48, Pal.BAND_RULE, 1.0, true)
	draw_arc(c, rad - 2.5, 0.0, TAU, 48, ring, 3.2, true)

	# 눈금은 침로에 따라 돈다 — 뱃머리가 위로 고정이므로
	var rot := deg_to_rad(-heading)
	for i in 16:
		var a := rot + float(i) * PI / 8.0
		var major := i % 4 == 0
		var inner: float = rad - (12.0 if major else 7.0)
		var dir := Vector2(sin(a), -cos(a))
		draw_line(c + dir * inner, c + dir * (rad - 5.0), Pal.BAND_FAINT, 1.0)

	var font := get_theme_default_font()
	if font:
		var np := c + Vector2(sin(rot), -cos(rot)) * (rad - 19.0)
		draw_string(font, np + Vector2(-8.0, 4.0), "북",
			HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Pal.BAND_SOFT)

	# 바람 — 상대 방위 자리에 꽂는다
	var wa := deg_to_rad(wind_bearing - heading)
	var wd := Vector2(sin(wa), -cos(wa))
	draw_line(c - wd * (rad - 14.0), c + wd * (rad - 20.0), ring, 2.0)
	var tip := c + wd * (rad - 12.0)
	var side := Vector2(wd.y, -wd.x)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - wd * 8.0 + side * 4.5, tip - wd * 8.0 - side * 4.5]), ring)

	# 지시한 침로 — 뱃머리가 아직 그쪽으로 도는 중이면 눈금 하나가 앞서 있다.
	# 이게 없으면 배가 왜 계속 도는지 알 수 없다.
	var turn := fposmod(ordered - heading + 180.0, 360.0) - 180.0
	if absf(turn) > 0.6:
		var oa := deg_to_rad(turn)
		var od := Vector2(sin(oa), -cos(oa))
		draw_line(c + od * (rad - 13.0), c + od * (rad - 3.0), Pal.HUD_GOLD, 2.4)

	# 뱃머리는 언제나 위
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -11), c + Vector2(5, 7), c + Vector2(0, 3), c + Vector2(-5, 7),
	]), Pal.BAND_INK)
