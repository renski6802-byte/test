class_name CompassView
extends Control

## 침로와 바람을 한 다이얼에 겹쳐 그린다.
##
## 위쪽이 "지금 보고 있는 쪽"이다. 자유 시점을 넣은 이상 화면과 나침반이 따로
## 놀면 더 헷갈린다. 고개를 오른쪽으로 돌리면 나침반도 같이 돈다.
##
## 대신 뱃머리를 잃으면 조타를 못 하므로 배 모양 표식을 따로 그려 같이 돌린다.
## 한 눈에 셋이 읽힌다 — 위쪽이 보는 쪽, 화살촉이 북쪽, 배 표식이 뱃머리.

func _ready() -> void:
	resized.connect(queue_redraw)

var heading := 0.0
var wind_bearing := 0.0
var ordered := 0.0
var view := 0.0          ## 카메라가 보고 있는 방위(도). 이쪽이 화면 위다.

func set_state(hdg: float, wind: float, order := NAN, view_brg := NAN) -> void:
	var ord: float = hdg if is_nan(order) else order
	var vb: float = hdg if is_nan(view_brg) else view_brg
	if is_equal_approx(hdg, heading) and is_equal_approx(wind, wind_bearing) \
			and is_equal_approx(ord, ordered) and is_equal_approx(vb, view):
		return
	heading = hdg
	wind_bearing = wind
	ordered = ord
	view = vb
	queue_redraw()

## 방위 하나를 다이얼 위의 방향으로. 보고 있는 쪽이 위(-y)다.
func _dir(bearing: float) -> Vector2:
	var a := deg_to_rad(bearing - view)
	return Vector2(sin(a), -cos(a))

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

	# 눈금은 방위에 고정되어 있고, 시점이 돌면 통째로 돈다
	for i in 16:
		var dir := _dir(float(i) * 22.5)
		var major := i % 4 == 0
		var inner: float = rad - (12.0 if major else 7.0)
		draw_line(c + dir * inner, c + dir * (rad - 5.0), Pal.BAND_FAINT, 1.0)

	var font := get_theme_default_font()
	if font:
		var np := c + _dir(0.0) * (rad - 19.0)
		draw_string(font, np + Vector2(-8.0, 4.0), "북",
			HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Pal.BAND_SOFT)

	# 바람 — 불어오는 쪽에서 배로
	var wd := _dir(wind_bearing)
	draw_line(c - wd * (rad - 14.0), c + wd * (rad - 20.0), ring, 2.0)
	var tip := c + wd * (rad - 12.0)
	var side := Vector2(wd.y, -wd.x)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - wd * 8.0 + side * 4.5, tip - wd * 8.0 - side * 4.5]), ring)

	# 지시한 침로 — 뱃머리가 아직 그쪽으로 도는 중이면 눈금 하나가 앞서 있다
	var turn := fposmod(ordered - heading + 180.0, 360.0) - 180.0
	if absf(turn) > 0.6:
		var od := _dir(ordered)
		draw_line(c + od * (rad - 13.0), c + od * (rad - 3.0), Pal.HUD_GOLD, 2.4)

	# 뱃머리 표식. 시점을 돌리면 이것이 돈다.
	var hd := _dir(heading)
	var hs := Vector2(hd.y, -hd.x)
	draw_colored_polygon(PackedVector2Array([
		c + hd * 11.0,
		c + hs * 5.0 - hd * 7.0,
		c - hd * 3.0,
		c - hs * 5.0 - hd * 7.0,
	]), Pal.BAND_INK)
