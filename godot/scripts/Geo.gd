class_name Geo
extends RefCounted

## 실제 지구 좌표를 게임 세계 좌표(미터)로 옮기는 일과, 해안선·항구 자료를 담는다.
##
## 세계 좌표계: x = 동쪽(m), z = 남쪽(m). 그래서 -z 가 북쪽이고 Godot 의 "앞"과 맞는다.
## 원점은 해역 한가운데로 잡는다. 이 해역은 600km 남짓이라 float 정밀도로 충분하다.

## 지리 1미터를 세계 몇 미터로 그릴 것인가.
##
## 시계가 빨리 돌면 배는 지리적으로 초당 수 km 를 간다. 그걸 그대로 3D 에 옮기면
## 물이 흐르는 게 아니라 끓는다. 그렇다고 시계 압축만큼(1440배) 세계를 줄이면
## 포르투갈이 배 스무 척 길이가 된다.
## 그래서 압축을 시간과 공간에 나눠 건다. 이 값이 공간 쪽 몫이다.
const WORLD_SCALE := 1.0 / 13.0

const KM_LAT := 111.19

const LON_MIN := -11.0
const LON_MAX := -5.2
const LAT_MIN := 33.4
const LAT_MAX := 39.6

const ORIGIN_LON := (LON_MIN + LON_MAX) * 0.5
const ORIGIN_LAT := (LAT_MIN + LAT_MAX) * 0.5

## 포르투갈 서안 → 남안 → 지브롤터
const COAST_IB := [
	Vector2(-8.90, 39.60), Vector2(-9.10, 39.55), Vector2(-9.42, 39.36),
	Vector2(-9.33, 39.20), Vector2(-9.20, 39.10), Vector2(-9.35, 38.90),
	Vector2(-9.42, 38.78), Vector2(-9.38, 38.70), Vector2(-9.30, 38.66),
	Vector2(-9.25, 38.55), Vector2(-9.00, 38.48), Vector2(-8.82, 38.40),
	Vector2(-8.79, 38.00), Vector2(-8.85, 37.85), Vector2(-8.80, 37.60),
	Vector2(-8.87, 37.40), Vector2(-8.95, 37.20), Vector2(-8.99, 37.02),
	Vector2(-8.80, 37.02), Vector2(-8.66, 37.09), Vector2(-8.40, 37.09),
	Vector2(-8.10, 37.06), Vector2(-7.90, 37.01), Vector2(-7.52, 37.16),
	Vector2(-7.20, 37.19), Vector2(-7.00, 37.20), Vector2(-6.80, 37.10),
	Vector2(-6.45, 36.94), Vector2(-6.35, 36.80), Vector2(-6.29, 36.53),
	Vector2(-6.20, 36.42), Vector2(-6.05, 36.20), Vector2(-5.80, 36.08),
	Vector2(-5.61, 36.01), Vector2(-5.44, 36.15), Vector2(-5.20, 36.22),
]

## 탕헤르 → 모로코 대서양 연안
const COAST_AF := [
	Vector2(-5.20, 35.95), Vector2(-5.45, 35.88), Vector2(-5.75, 35.84),
	Vector2(-5.94, 35.79), Vector2(-6.03, 35.55), Vector2(-6.15, 35.20),
	Vector2(-6.35, 34.80), Vector2(-6.55, 34.50), Vector2(-6.75, 34.20),
	Vector2(-6.84, 34.03), Vector2(-7.10, 33.80), Vector2(-7.45, 33.65),
	Vector2(-7.62, 33.55), Vector2(-8.00, 33.40),
]

## 충돌 판정에 쓰는 닫힌 다각형 (해안선 + 지도 바깥쪽 변)
static func poly_iberia() -> Array:
	var p := COAST_IB.duplicate()
	p.append(Vector2(-5.20, 39.60))
	return p

static func poly_africa() -> Array:
	var p := COAST_AF.duplicate()
	p.append(Vector2(-8.00, 33.40))
	p.append(Vector2(-5.20, 33.40))
	return p

## 항구. region 이 다르면 그 지역을 아는 선원을 태워야 방향을 물을 수 있다.
const PORTS := [
	{ "name": "리스보아", "lon": -9.30, "lat": 38.70, "region": "이베리아", "home": true },
	{ "name": "사그레스", "lon": -8.97, "lat": 37.00, "region": "이베리아", "home": false },
	{ "name": "파루", "lon": -7.93, "lat": 37.01, "region": "이베리아", "home": false },
	{ "name": "카디스", "lon": -6.29, "lat": 36.53, "region": "이베리아", "home": false, "hires": true },
	{ "name": "탕헤르", "lon": -5.85, "lat": 35.80, "region": "마그레브", "home": false },
	{ "name": "살레", "lon": -6.84, "lat": 34.03, "region": "마그레브", "home": false },
]

## M0 검증용. 실제 해안선은 손대지 않고 항구만 리스보아 앞에 가깝게 둔다.
## 1배속에서도 2~5분이면 닿아서 조작감을 확인하기 좋다. 본편에서는 끄면 된다.
const USE_TEST_PORTS := true

## 실제 해안에서 8km 남짓 떨어진 정박지로 잡았다. 뭍 위에 떠 있지 않도록.
## 1배속 기준 리스보아에서 각각 1.5분 / 4분 / 6분 / 7분 / 8분.
const TEST_PORTS := [
	{ "name": "리스보아", "lon": -9.45, "lat": 38.72, "region": "이베리아", "home": true },
	{ "name": "카스카이스", "lon": -9.36, "lat": 38.58, "region": "이베리아", "home": false },
	{ "name": "세투발", "lon": -9.00, "lat": 38.44, "region": "이베리아", "home": false },
	{ "name": "시느스", "lon": -8.88, "lat": 38.20, "region": "이베리아", "home": false, "hires": true },
	{ "name": "밀폰테스", "lon": -8.88, "lat": 38.00, "region": "마그레브", "home": false },
	{ "name": "오데세이시", "lon": -8.94, "lat": 37.85, "region": "마그레브", "home": false },
]

static func ports() -> Array:
	return TEST_PORTS if USE_TEST_PORTS else PORTS

static func km_per_deg_lon(lat: float) -> float:
	return 111.32 * cos(deg_to_rad(lat))

## 경위도 → 세계 좌표(미터)
static func to_world(lon: float, lat: float) -> Vector3:
	var east := (lon - ORIGIN_LON) * km_per_deg_lon(lat) * 1000.0 * WORLD_SCALE
	var north := (lat - ORIGIN_LAT) * KM_LAT * 1000.0 * WORLD_SCALE
	return Vector3(east, 0.0, -north)

## 세계 좌표(미터) → 경위도
static func to_geo(p: Vector3) -> Vector2:
	var lat := ORIGIN_LAT + (-p.z) / (KM_LAT * 1000.0 * WORLD_SCALE)
	var lon := ORIGIN_LON + p.x / (km_per_deg_lon(lat) * 1000.0 * WORLD_SCALE)
	return Vector2(lon, lat)

static func dist_km(a_lon: float, a_lat: float, b_lon: float, b_lat: float) -> float:
	var dn := (a_lat - b_lat) * KM_LAT
	var de := (a_lon - b_lon) * km_per_deg_lon((a_lat + b_lat) * 0.5)
	return sqrt(dn * dn + de * de)

static func in_poly(lon: float, lat: float, poly: Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var pi: Vector2 = poly[i]
		var pj: Vector2 = poly[j]
		if (pi.y > lat) != (pj.y > lat):
			if lon < (pj.x - pi.x) * (lat - pi.y) / (pj.y - pi.y) + pi.x:
				inside = not inside
		j = i
	return inside

static func on_land(lon: float, lat: float) -> bool:
	return in_poly(lon, lat, poly_iberia()) or in_poly(lon, lat, poly_africa())

## 해안선까지의 대략적인 거리 (바다에 흩뿌릴 것들을 배치할 때 쓴다)
static func coast_dist_km(lon: float, lat: float) -> float:
	var best := 1.0e9
	for coast in [COAST_IB, COAST_AF]:
		for p in coast:
			best = min(best, dist_km(lon, lat, p.x, p.y))
	return best

## 그 자리 해안의 높이(m). 같은 자리는 늘 같은 값이 나오도록 해싱한다.
static func coast_height(lon: float, lat: float) -> float:
	var s: float = sin(lon * 12.9898 + lat * 78.233) * 43758.5453
	# 높이는 축척을 안 받는다. 가로가 줄어든 만큼 비탈이 가팔라지므로 조금 낮춰 잡는다.
	return 60.0 + (s - floor(s)) * 170.0

const COMPASS8 := ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]
const COMPASS16 := [
	"북", "북북동", "북동", "동북동", "동", "동남동", "남동", "남남동",
	"남", "남남서", "남서", "서남서", "서", "서북서", "북서", "북북서",
]

## 받침 유무에 따라 조사를 고른다
static func josa(word: String, with_jong: String, without_jong: String) -> String:
	if word.is_empty():
		return word
	var c := word.unicode_at(word.length() - 1)
	var jong := c >= 0xAC00 and c <= 0xD7A3 and (c - 0xAC00) % 28 != 0
	return word + (with_jong if jong else without_jong)
