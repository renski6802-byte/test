class_name SkyDome
extends RefCounted

## 해와 달을 하늘의 제자리에 놓고, 그 결과를 하늘·바다 셰이더에 함께 넘긴다.
##
## 예전에는 시각을 방위각에 바로 꽂고 있었다. 그러면 해가 남쪽에서 떠서
## 북쪽으로 지고, 도는 방향까지 반대가 된다. 달은 아예 뜨지도 지지도 않았다.
##
## 여기서는 관측자의 위도와 시각(시각)으로 지평좌표를 제대로 구한다.
## 그래야 동에서 떠서 남중하고 서로 지며, 위도를 바꾸면 궤도도 같이 바뀐다.
## 나중에 별을 얹을 때도 같은 좌표계를 쓴다.

const AXIAL_TILT := 23.44        ## 지축 기울기. 계절이 여기서 나온다.
const YEAR_DAYS := 365.24

## 지평좌표의 단위 벡터를 세계 좌표로. x=동, y=위, -z=북 이므로 북은 -z 다.
static func _enu_to_world(east: float, north: float, up: float) -> Vector3:
	return Vector3(east, up, -north)

## 적위 dec 인 천체가 시각각 ha 일 때 어디에 보이는가.
## ha 는 남중이 0 이고 서쪽으로 갈수록 커진다.
static func _horizon_dir(dec_deg: float, ha_deg: float, lat_deg: float) -> Vector3:
	var d := deg_to_rad(dec_deg)
	var h := deg_to_rad(ha_deg)
	var p := deg_to_rad(lat_deg)
	var east := -cos(d) * sin(h)
	var north := sin(d) * cos(p) - cos(d) * sin(p) * cos(h)
	var up := sin(p) * sin(d) + cos(p) * cos(d) * cos(h)
	return _enu_to_world(east, north, up).normalized()

## 그 날의 태양 적위(도). 하지에 +23.44, 동지에 -23.44.
##
## 출항일(0일)을 춘분으로 잡는다. 그러면 첫 항해는 여섯 시에 해가 떠서
## 열여덟 시에 지고, 항해가 길어질수록 계절이 저절로 흘러 낮이 길어진다.
static func sun_declination(day: float) -> float:
	return AXIAL_TILT * sin(TAU * day / YEAR_DAYS)

var sun_dir := Vector3(0, 1, 0)      ## 해가 있는 쪽
var moon_dir := Vector3(0, -1, 0)
var sun_alt := 0.0                   ## 해의 고도 sin값. 밤이면 음수.
var moon_alt := 0.0

## hours 는 출항부터 흐른 시각(시), lat 은 지금 위도(도).
func update(hours: float, lat: float) -> void:
	var day := floorf(hours / 24.0)
	var h := fposmod(hours, 24.0)

	# 시각각 — 정오에 0, 한 시간에 15도씩 서쪽으로
	var ha := (h - 12.0) * 15.0
	var dec := sun_declination(day)
	sun_dir = _horizon_dir(dec, ha, lat)
	sun_alt = sun_dir.y

	# 달은 보름달 하나로 둔다. 해의 정반대에 있으므로 해가 질 때 동쪽에서 뜨고
	# 자정에 남중해 해가 뜰 때 서쪽으로 진다. 위상은 다루지 않는다 —
	# 달이 밝아도 별은 그대로 보이는 것으로 정했다.
	moon_dir = _horizon_dir(-dec, ha + 180.0, lat)
	moon_alt = moon_dir.y

## 낮의 정도 0~1. 해가 지평 아래로 조금 내려가도 한동안 밝다.
func day01() -> float:
	return clampf((sun_alt + 0.09) / 0.30, 0.0, 1.0)

## 여명·황혼의 정도 0~1
func dusk01() -> float:
	return clampf(1.0 - absf(sun_alt) / 0.22, 0.0, 1.0)

## 달이 떠 있는 정도 0~1
func moon_up01() -> float:
	return clampf((moon_alt + 0.05) / 0.20, 0.0, 1.0)

## 하늘 셰이더와 바다 셰이더가 같은 값을 봐야 한다.
func push(materials: Array) -> void:
	for m in materials:
		if m == null:
			continue
		m.set_shader_parameter("sun_dir", sun_dir)
		m.set_shader_parameter("moon_dir", moon_dir)
		m.set_shader_parameter("sun_alt", sun_alt)
		m.set_shader_parameter("moon_up", moon_up01())
