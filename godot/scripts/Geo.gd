class_name Geo
extends RefCounted

## 실제 지구 좌표를 게임 세계 좌표(미터)로 옮기는 일과, 해안선·항구 자료를 담는다.
##
## 세계 좌표계: x = 동쪽(m), z = 남쪽(m). 그래서 -z 가 북쪽이고 Godot 의 "앞"과 맞는다.
## 원점은 해역 한가운데로 잡는다. 이 해역은 600km 남짓이라 float 정밀도로 충분하다.

## 지리 1미터를 세계 몇 미터로 그릴 것인가.
##
## 하루가 실시간 1분이면 배는 지리적으로 초당 7.4km 를 간다. 그걸 그대로 3D 에
## 옮기면 물이 흐르는 게 아니라 끓는다. 그래서 세계를 같은 비율로 줄인다.
##
## 축척을 안 받는 것은 배 하나뿐이다. 배는 파도와 같은 물에 떠야 하므로 26m 를
## 지켜야 하고, 그래서 지리에 비해 거대해진다. 그것도 원작의 모습 그대로다.
##
## 1/370 이었다. 그때는 배가 물 위에서 초속 20m 로 보이게 맞춘 값이었는데,
## 그 대가로 육지 축척(1/25)과 열다섯 배가 벌어져 해안이 배보다 열다섯 배
## 빨리 다가왔다. 물가가 미끄러지던 것이 전부 여기서 나왔다.
##
## 돛으로 속도를 조절하게 되면서 배가 빨라 보이는 것을 받아들이기로 했다.
## 전속에서 초속 56m 다. 대신 어긋남이 열다섯 배에서 다섯 배로 줄었다.
## 그리고 항해의 대부분은 순항 이하라 실제로 보이는 속도는 초속 37m 다.
const WORLD_SCALE := 1.0 / 120.0

## 육지만 쓰는 축척.
##
## 바다 축척(1/370)으로 육지를 세우면 26km 시야가 70m — 배 세 척 길이라
## 무엇을 그려도 뭉개진다. 육지는 훨씬 완만하게 눌러 26km 가 1km 가 되게 한다.
## 그러면 곶과 만이 각각 수백 미터를 차지해 지형이 성립하고, 해안이 수평선의
## 띠에서 시작해 몇십 초에 걸쳐 다가온다.
##
## 대가는 육지가 다가오는 속도가 배의 속도와 안 맞는다는 것 하나뿐인데,
## 육지가 보이면 배속이 저절로 내려가므로 눈에 띄지 않는다.
## 열린 바다에는 견줄 눈금이 없어 아무도 못 알아챈다.
const LAND_SCALE := 1.0 / 25.0

## 물가 쪽에서 쓰는 육지 축척. 바다(1/370)와 먼 육지(1/25) 사이다.
##
## 먼 육지를 1/25 로 두면 해안이 배보다 열다섯 배 빨리 다가와 물가가 미끄러진다.
## 가까운 곳만 바다 쪽으로 당겨 그 어긋남을 세 배로 줄인다.
const LAND_NEAR_SCALE := 1.0 / 40.0

## 가까운 배율에서 먼 배율로 넘어가는 구간(지리 미터).
## 육지 셰이더와 바다 셰이더가 같은 값을 봐야 물가가 어긋나지 않는다.
const BLEND_NEAR_M := 2000.0
const BLEND_FAR_M := 18000.0

## 육지 높이에 따로 먹이는 축척.
##
## 1 이다. 곧 메시는 실제 높이를 그대로 담는다.
##
## 누르는 일은 셰이더가 한다(land.gdshader 의 slope_ease). 여기서 미리 1/4 로
## 줄여놨더니 셰이더가 한 번 더 눌러, 3km 앞 해안이 1.6m 짜리 둔덕이 되어
## 파도에 잠겼다. 축척은 한 군데서만 먹인다.
const LAND_HEIGHT_SCALE := 1.0

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

## 해안의 생김새. 구간마다 다르게 준다 — 실제 지형을 따르면 항해에 의미가 생긴다.
## 절벽은 멀리서도 보여 좋은 표지가 되고, 낮은 모래해안은 늦게 보여 좌초가 무섭다.
enum { SAND, LOW, CLIFF, MOUNTAIN }

## 종류별 [높이 최소, 최대, 능선까지, 고원까지, 색]. 거리는 지리 미터다.
const TERRAIN := {
	SAND: [6.0, 22.0, 2600.0, 22000.0, Color("b8ac86")],
	LOW: [35.0, 85.0, 4000.0, 26000.0, Color("55603d")],
	CLIFF: [90.0, 180.0, 1400.0, 22000.0, Color("6f6656")],
	MOUNTAIN: [240.0, 430.0, 6000.0, 34000.0, Color("3e4736")],
}

## COAST_IB 의 점마다 어떤 땅인가
const TYPE_IB := [
	CLIFF, CLIFF, CLIFF, CLIFF, CLIFF, CLIFF,        # 페니셰 ~ 호카 곶
	CLIFF, LOW, LOW, LOW, LOW, LOW,                  # 리스보아 · 세투발
	CLIFF, CLIFF, CLIFF, CLIFF, CLIFF, CLIFF,        # 알렌테주 · 상비센트 곶
	CLIFF, CLIFF, SAND, SAND, SAND, SAND,            # 사그레스 ~ 알가르베
	SAND, SAND, SAND, SAND, LOW, LOW,                # 우엘바 · 카디스
	LOW, LOW, MOUNTAIN, MOUNTAIN, MOUNTAIN, MOUNTAIN, # 타리파 · 지브롤터
]

## COAST_AF 의 점마다
const TYPE_AF := [
	MOUNTAIN, MOUNTAIN, MOUNTAIN, MOUNTAIN,          # 탕헤르 · 리프
	LOW, LOW, LOW, LOW, SAND, SAND,                  # 라라슈 · 라바트
	SAND, SAND, SAND, SAND,                          # 카사블랑카
]

static func coast_types(coast: Array) -> Array:
	return TYPE_IB if coast == COAST_IB else TYPE_AF

## 충돌 판정에 쓰는 닫힌 다각형 (해안선 + 지도 바깥쪽 변)
##
## 한 번 만들어 두고 쓴다. 부를 때마다 새로 뜨면 육지 메시를 세울 때
## 수십만 번 배열을 복사하게 되어 그것만으로 몇 초가 날아간다.
static var _poly_ib: Array = []
static var _poly_af: Array = []

static func poly_iberia() -> Array:
	if _poly_ib.is_empty():
		_poly_ib = COAST_IB.duplicate()
		_poly_ib.append(Vector2(-5.20, 39.60))
	return _poly_ib

static func poly_africa() -> Array:
	if _poly_af.is_empty():
		_poly_af = COAST_AF.duplicate()
		_poly_af.append(Vector2(-8.00, 33.40))
		_poly_af.append(Vector2(-5.20, 33.40))
	return _poly_af

## 축척 없는 지리 미터 → 경위도. to_metres 의 역.
static func geo_of_metres(x: float, z: float) -> Vector2:
	var lat := ORIGIN_LAT + (-z) / (KM_LAT * 1000.0)
	return Vector2(ORIGIN_LON + x / (km_per_deg_lon(lat) * 1000.0), lat)

## 항구. region 이 다르면 그 지역을 아는 선원을 태워야 방향을 물을 수 있다.
const PORTS := [
	{ "name": "리스보아", "lon": -9.30, "lat": 38.70, "region": "이베리아", "home": true },
	{ "name": "사그레스", "lon": -8.97, "lat": 37.00, "region": "이베리아", "home": false },
	{ "name": "파루", "lon": -7.93, "lat": 37.01, "region": "이베리아", "home": false },
	{ "name": "카디스", "lon": -6.29, "lat": 36.53, "region": "이베리아", "home": false, "hires": true },
	{ "name": "탕헤르", "lon": -5.85, "lat": 35.80, "region": "마그레브", "home": false },
	{ "name": "살레", "lon": -6.84, "lat": 34.03, "region": "마그레브", "home": false },
]

## 검증용으로 항구를 리스보아 앞에 몰아둘 것인가.
##
## 하루가 28분이던 시절엔 실제 항구까지 몇십 분이 걸려 검증이 안 됐다.
## 하루가 1분이 된 지금은 리스보아→사그레스가 1.5분이라 그럴 이유가 없어졌다.
const USE_TEST_PORTS := false

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

## 경위도 → 축척을 안 먹인 지리 미터. 육지 메시가 이 좌표로 만들어진다.
static func to_metres(lon: float, lat: float) -> Vector3:
	var east := (lon - ORIGIN_LON) * km_per_deg_lon(lat) * 1000.0
	var north := (lat - ORIGIN_LAT) * KM_LAT * 1000.0
	return Vector3(east, 0.0, -north)

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

## 해안선까지의 거리(km).
##
## 꼭짓점까지의 거리만 재면 안 된다 — 해안선 점 사이가 10~20km 라, 두 점 한가운데
## 있으면 실제로는 코앞인데 멀다고 나온다. 좌초 판정이 이 값에 걸리므로
## 선분까지의 거리를 제대로 잰다.
static func coast_dist_km(lon: float, lat: float) -> float:
	var best := 1.0e9
	var kx := km_per_deg_lon(lat)
	for coast in [COAST_IB, COAST_AF]:
		for i in range(coast.size() - 1):
			var a: Vector2 = coast[i]
			var b: Vector2 = coast[i + 1]
			# 경도 1도의 거리가 위도 1도와 다르므로 km 로 펴놓고 잰다
			var pa := Vector2((a.x - lon) * kx, (a.y - lat) * KM_LAT)
			var pb := Vector2((b.x - lon) * kx, (b.y - lat) * KM_LAT)
			var ab := pb - pa
			var len2 := ab.length_squared()
			var t := 0.0 if len2 < 1e-9 else clampf(-pa.dot(ab) / len2, 0.0, 1.0)
			best = minf(best, (pa + ab * t).length())
	return best

## 그 자리 해안의 높이(m). 실제 높이 그대로다 — 육지 축척은 가로에만 먹인다.
## 같은 자리는 늘 같은 값이 나오도록 해싱해서 종류가 정한 범위 안에서 흔든다.
static func coast_height(lon: float, lat: float, kind: int) -> float:
	var t: Array = TERRAIN[kind]
	var s: float = sin(lon * 12.9898 + lat * 78.233) * 43758.5453
	return lerpf(t[0], t[1], s - floor(s)) * LAND_HEIGHT_SCALE

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
