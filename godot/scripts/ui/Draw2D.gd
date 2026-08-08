class_name Draw2D
extends RefCounted

## _draw() 안에서 오목한 다각형을 채우는 일.
##
## draw_polygon() 은 "다각형 하나"를 받아 스스로 쪼갠다. 그래서 이미 삼각형으로
## 쪼갠 정점들을 넘기면 자기교차로 보고 통째로 실패한다.
## 삼각형 배열은 이 전용 통로로 넘겨야 한다.

static func fill_poly(ci: RID, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols)
