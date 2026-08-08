class_name ChartView
extends Control

## 내가 그린 해도. 지나간 자리만 채워지고, 안 간 곳은 빗금 친 빈 종이로 남는다.

func _ready() -> void:
	# 항정선이 도곽 밖으로 뻗지 않도록 가둔다
	clip_contents = true
	resized.connect(queue_redraw)

var fog: Fog
var voyage: Voyage
var track: PackedVector2Array = PackedVector2Array()   ## 지나온 자리 (경위도)

func add_track(lon: float, lat: float) -> void:
	track.append(Vector2(lon, lat))
	if visible:
		queue_redraw()

func _draw() -> void:
	if fog == null or voyage == null:
		return

	# 해역 비율을 지키며 가운데에 앉힌다
	var aspect := float(Fog.W) / float(Fog.H)
	var w: float = minf(size.x, size.y * aspect)
	var h: float = w / aspect
	var origin := (size - Vector2(w, h)) * 0.5
	var scale := w / float(Fog.W)

	var to_local := func(lon: float, lat: float) -> Vector2:
		return origin + fog.to_px(lon, lat) * scale

	draw_rect(Rect2(origin, Vector2(w, h)), Pal.CHART_SEA)

	# 항정선망 — 나침도에서 32방위로 뻗는 그물
	for rose in [Vector2(-8.6, 37.6), Vector2(-10.2, 35.2)]:
		var rc: Vector2 = to_local.call(rose.x, rose.y)
		for i in 32:
			var a := float(i) * PI / 16.0
			draw_line(rc, rc + Vector2(cos(a), sin(a)) * w, Pal.HATCH, 1.0)

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

	# 아직 안 그린 곳
	fog.flush()
	draw_texture_rect_region(fog.texture, Rect2(origin, Vector2(w, h)),
		Rect2(Vector2.ZERO, Vector2(Fog.W, Fog.H)))

	# 한 번 적어 넣은 항구는 종이 위에 남는다 — 안개에 가리지 않는다
	var font := get_theme_default_font()
	for p in Geo.ports():
		if not voyage.found.has(p.name):
			continue
		var q: Vector2 = to_local.call(p.lon, p.lat)
		draw_arc(q, 4.5, 0.0, TAU, 16, Pal.BRASS, 1.6, true)
		draw_circle(q, 1.8, Pal.BRASS)
		if font:
			draw_string(font, q + Vector2(-40.0, 16.0), p.name,
				HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Pal.BRASS)

	# 내 배
	var c: Vector2 = to_local.call(voyage.lon, voyage.lat)
	var a2 := deg_to_rad(voyage.heading)
	var fwd := Vector2(sin(a2), -cos(a2))
	var side := Vector2(fwd.y, -fwd.x)
	draw_colored_polygon(PackedVector2Array([
		c + fwd * 8.0, c - fwd * 4.0 + side * 4.5, c - fwd * 4.0 - side * 4.5,
	]), Pal.VERMILION)

	draw_rect(Rect2(origin, Vector2(w, h)), Pal.BAND_RULE, false, 1.0)
