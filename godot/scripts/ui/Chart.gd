class_name ChartView
extends Control

## 해역 전체를 담은 해도. 항구와 해안선은 처음부터 다 적혀 있고,
## 내가 지나온 자리는 그 위에 항적으로 남는다.

func _ready() -> void:
	# 항정선이 도곽 밖으로 뻗지 않도록 가둔다
	clip_contents = true
	resized.connect(queue_redraw)

var voyage: Voyage
var track: PackedVector2Array = PackedVector2Array()   ## 지나온 자리 (경위도)

func add_track(lon: float, lat: float) -> void:
	track.append(Vector2(lon, lat))
	if visible:
		queue_redraw()

## 안에 있는 점에서 한 방향으로 뻗을 때, 종이 가장자리까지의 거리.
static func _to_edge(from: Vector2, dir: Vector2, paper: Rect2) -> float:
	var t := 1.0e9
	if absf(dir.x) > 0.0001:
		var tx := (paper.position.x - from.x) / dir.x
		var tx2 := (paper.end.x - from.x) / dir.x
		t = minf(t, maxf(tx, tx2))
	if absf(dir.y) > 0.0001:
		var ty := (paper.position.y - from.y) / dir.y
		var ty2 := (paper.end.y - from.y) / dir.y
		t = minf(t, maxf(ty, ty2))
	return maxf(t, 0.0)

func _draw() -> void:
	if voyage == null:
		return

	# 해역 비율을 지키며 가운데에 앉힌다
	var aspect := float(Geo.CHART_W) / float(Geo.CHART_H)
	var w: float = minf(size.x, size.y * aspect)
	var h: float = w / aspect
	var origin := (size - Vector2(w, h)) * 0.5
	var scale := w / float(Geo.CHART_W)

	var to_local := func(lon: float, lat: float) -> Vector2:
		return origin + Geo.to_chart_px(lon, lat) * scale

	draw_rect(Rect2(origin, Vector2(w, h)), Pal.CHART_SEA)

	# 항정선망 — 나침도에서 32방위로 뻗는 그물. 종이 밖으로는 안 나간다.
	var paper := Rect2(origin, Vector2(w, h))
	for rose in [Vector2(-8.6, 37.6), Vector2(-10.2, 35.2)]:
		var rc: Vector2 = to_local.call(rose.x, rose.y)
		for i in 32:
			var a := float(i) * PI / 16.0
			var dir := Vector2(cos(a), sin(a))
			draw_line(rc, rc + dir * _to_edge(rc, dir, paper), Pal.HATCH, 1.0)

	for poly in [Geo.poly_iberia(), Geo.poly_africa()]:
		var pts := PackedVector2Array()
		for g in poly:
			pts.append(to_local.call(g.x, g.y))
		Draw2D.fill_poly(get_canvas_item(), pts, Pal.CHART_LAND)

	# 바다에서 본 것들
	for f in voyage.features:
		if not voyage.seen_features.has(f.id):
			continue
		var p: Vector2 = to_local.call(f.lon, f.lat)
		draw_circle(p, 2.2, Pal.VERMILION if f.kind == "암초" else Pal.VERDIGRIS)

	# 항적
	if track.size() > 1:
		var prev: Vector2 = to_local.call(track[0].x, track[0].y)
		for i in range(1, track.size()):
			var cur: Vector2 = to_local.call(track[i].x, track[i].y)
			draw_line(prev, cur, Color(Pal.BRASS, 0.55), 1.4)
			prev = cur

	# 항구. 아직 못 가 본 데는 옅게 둔다 — 가려서가 아니라 아직 안 밟아서다.
	var font := get_theme_default_font()
	for p in Geo.ports():
		var seen: bool = voyage.visited.has(p.name)
		var ink: Color = Pal.BRASS if seen else Color(Pal.BRASS, 0.45)
		var q: Vector2 = to_local.call(p.lon, p.lat)
		draw_arc(q, 4.5, 0.0, TAU, 16, ink, 1.6, true)
		if seen:
			draw_circle(q, 1.8, ink)
		if font:
			draw_string(font, q + Vector2(-40.0, 16.0), p.name,
				HORIZONTAL_ALIGNMENT_CENTER, 80, 11, ink)

	# 내 배
	var c: Vector2 = to_local.call(voyage.lon, voyage.lat)
	var a2 := deg_to_rad(voyage.heading)
	var fwd := Vector2(sin(a2), -cos(a2))
	var side := Vector2(fwd.y, -fwd.x)
	draw_colored_polygon(PackedVector2Array([
		c + fwd * 8.0, c - fwd * 4.0 + side * 4.5, c - fwd * 4.0 - side * 4.5,
	]), Pal.VERMILION)

	draw_rect(Rect2(origin, Vector2(w, h)), Pal.BAND_RULE, false, 1.0)
