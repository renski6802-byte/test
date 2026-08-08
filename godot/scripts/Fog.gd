class_name Fog
extends RefCounted

## 아직 그리지 않은 해도. 검은 안개가 아니라 빗금 친 빈 종이다.
##
## 해역 전체를 덮는 이미지 한 장을 들고 있다가, 배가 지나간 자리를 투명하게
## 뚫는다. 해도와 미니맵이 이 한 장을 같이 쓴다.

const W := 512
const H := 680

var image: Image
var texture: ImageTexture

var _dirty := false

func _init() -> void:
	image = Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	image.fill(Pal.UNMAPPED)
	# 비어 있다는 것이 보이도록 빗금을 깔아둔다
	var hatch := Pal.UNMAPPED.lerp(Color("6b5f45"), 0.22)
	for y in H:
		for x in W:
			if (x + y) % 7 == 0:
				image.set_pixel(x, y, hatch)
	texture = ImageTexture.create_from_image(image)

## 경위도 → 이미지 픽셀 좌표
func to_px(lon: float, lat: float) -> Vector2:
	var u := (lon - Geo.LON_MIN) / (Geo.LON_MAX - Geo.LON_MIN)
	var v := (Geo.LAT_MAX - lat) / (Geo.LAT_MAX - Geo.LAT_MIN)
	return Vector2(u * W, v * H)

func px_per_km() -> float:
	return float(H) / ((Geo.LAT_MAX - Geo.LAT_MIN) * Geo.KM_LAT)

func punch(lon: float, lat: float, radius_km: float) -> void:
	var c := to_px(lon, lat)
	var r := radius_km * px_per_km()
	var x0 := int(max(0.0, floor(c.x - r)))
	var x1 := int(min(float(W - 1), ceil(c.x + r)))
	var y0 := int(max(0.0, floor(c.y - r)))
	var y1 := int(min(float(H - 1), ceil(c.y + r)))
	if x1 < x0 or y1 < y0:
		return

	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
			if d > r:
				continue
			# 가장자리는 부드럽게 — 지나간 자리가 원으로 딱 잘리지 않도록
			var a := clampf((d - r * 0.55) / (r * 0.45), 0.0, 1.0)
			var px := image.get_pixel(x, y)
			if a < px.a:
				px.a = a
				image.set_pixel(x, y, px)
	_dirty = true

## 그린 바다의 넓이(km²). 늘 올라가기만 하는 숫자라 진행감이 산다.
func mapped_km2() -> float:
	var open := 0
	var step := 4
	var total := 0
	for y in range(0, H, step):
		for x in range(0, W, step):
			total += 1
			if image.get_pixel(x, y).a < 0.5:
				open += 1
	if total == 0:
		return 0.0
	var region := (Geo.LON_MAX - Geo.LON_MIN) * Geo.km_per_deg_lon(Geo.ORIGIN_LAT) \
		* (Geo.LAT_MAX - Geo.LAT_MIN) * Geo.KM_LAT
	return float(open) / float(total) * region

func flush() -> void:
	if not _dirty:
		return
	texture.update(image)
	_dirty = false
