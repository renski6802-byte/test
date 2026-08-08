class_name MinimapView
extends Control

## 눈앞 해역만 보여주는 작은 지도. 해역 전체는 해도가 맡는다.

const SPAN_DEG := 1.8

var fog: Fog
var voyage: Voyage

func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	if fog == null or voyage == null:
		return
	var s: float = minf(size.x, size.y)
	if s < 8.0:
		return

	var px_per_deg_lat := float(Fog.H) / (Geo.LAT_MAX - Geo.LAT_MIN)
	var src_side := SPAN_DEG * px_per_deg_lat
	var center := fog.to_px(voyage.lon, voyage.lat)
	var src_origin := center - Vector2(src_side, src_side) * 0.5
	var scale := s / src_side

	var to_local := func(lon: float, lat: float) -> Vector2:
		return (fog.to_px(lon, lat) - src_origin) * scale

	draw_rect(Rect2(Vector2.ZERO, size), Pal.CHART_SEA.darkened(0.55))

	for poly in [Geo.poly_iberia(), Geo.poly_africa()]:
		var pts := PackedVector2Array()
		for g in poly:
			pts.append(to_local.call(g.x, g.y))
		Draw2D.fill_poly(get_canvas_item(), pts, Pal.CHART_LAND.darkened(0.45))

	# 아직 안 그린 곳을 덮는다
	fog.flush()
	draw_texture_rect_region(fog.texture, Rect2(Vector2.ZERO, Vector2(s, s)),
		Rect2(src_origin, Vector2(src_side, src_side)))

	for p in Geo.PORTS:
		if not voyage.found.has(p.name):
			continue
		draw_circle(to_local.call(p.lon, p.lat), 3.0, Pal.BRASS_LIT)

	# 내 배
	var c := Vector2(s, s) * 0.5
	var a := deg_to_rad(voyage.heading)
	var fwd := Vector2(sin(a), -cos(a))
	var side := Vector2(fwd.y, -fwd.x)
	draw_colored_polygon(PackedVector2Array([
		c + fwd * 7.0, c - fwd * 4.0 + side * 4.0, c - fwd * 4.0 - side * 4.0,
	]), Pal.VERMILION.lightened(0.25))

	draw_rect(Rect2(Vector2.ZERO, Vector2(s, s)), Pal.BAND_RULE, false, 1.0)
