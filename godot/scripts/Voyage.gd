class_name Voyage
extends RefCounted

## 항해 그 자체. 그리기와 무관한 상태와 규칙만 여기에 둔다.

signal noted(text: String, kind: String)      ## 세계가 알려주는 것
signal spoke(who: String, text: String)       ## 사람이 하는 말
signal revealed(lon: float, lat: float, radius_km: float)
signal sails_changed(stage: int, reason: String)

## 1배속에서 실시간 1초가 게임 몇 초인가.
##
## 원작대로 하루가 실시간 1분이다. 이것이 순항 속도이고, 창을 줄여놓고 딴짓하는
## 그 모드가 기본이 된다.
const CLOCK := 1440.0

## 돛. 이것이 유일한 속도 조절이다.
##
## 전에는 시계를 늦춰 속도를 조절했다. 그러면 "0.5배속 — 하루가 2분" 처럼
## 세계의 리듬 자체가 흔들린다. 원작은 시계를 고정한 채 돛으로 조절한다.
## 하루는 언제나 실시간 1분이고, 느리게 가고 싶으면 돛을 접는다.
##
## 노트는 실제 배의 값 그대로다. 압축은 시계(CLOCK)가 혼자 맡는다.
## 실시간 1초에 가는 거리 = 노트 × 0.74km.
enum { FURLED, SLOW, CRUISE, FULL }
const SAIL_KN := [0.0, 2.2, 6.0, 9.0]
const SAIL_NAME := ["정박", "미속", "순항", "전속"]

## 돛을 올리고 내리는 데 걸리는 시간(실시간 초). 즉시 바뀌면 배가 아니라
## 순간이동이 된다. 물살과 물보라도 이 값을 따라 잦아든다.
const SAIL_EASE := 2.2

## 뱃머리가 실시간 1초에 돌 수 있는 각도.
##
## 침로를 찍으면 그 자리에서 뱃머리가 홱 돌아가 있었다. 배는 그렇게 안 돈다.
## 지시는 즉시 들어가되 뱃머리는 이 속도로 따라 돈다. 시계 배속과는 무관하게
## 실시간 기준이어야 손맛이 일정하다.
const TURN_RATE := 22.0

## 정박 중엔 키가 안 듣는다. 물이 흘러야 방향이 잡힌다.
const TURN_STEERAGE := 0.35     ## 돛을 내렸을 때 남는 선회력

## 좌초. 육지에 붙으면 배가 긁힌다.
##
## 배가 지리에 비해 크다는 문제가 여기서 규칙으로 흡수된다 — 해안은 가까이
## 가면 안 되는 것이 되고, 접근 자체가 실수가 된다.
## 전속이면 실시간 1초에 6.7km 를 간다. 경고선이 8km 면 손쓸 틈이 1초뿐이라
## 20km 로 물렸다. 경고는 여기서 오고, 돛을 접을지는 뱃사람이 정한다.
## 안 접으면 2.5초 만에 긁히기 시작한다. 그게 좌초라는 것이다.
const GROUND_WARN_KM := 20.0    ## 여기부터 경고
const GROUND_HIT_KM := 3.0      ## 여기부터 긁힌다
const GROUND_STOP_KM := 1.2     ## 여기서는 아예 못 들어간다. 배가 뭍에 올라앉는다.
const HULL_MAX := 100.0
const HULL_RATE := 14.0         ## 가장 얕은 곳에서 게임 한 시간에 깎이는 내구도

var lon := -9.52
var lat := 38.66
var heading := 190.0            ## 도, 0 = 북. 실제로 뱃머리가 향한 쪽
var ordered_heading := 190.0    ## 지시한 침로. heading 은 이걸 향해 서서히 돈다
var sails := CRUISE              ## 정박 / 미속 / 순항 / 전속
var wind_brg := 210.0
var hours := 8.0
var surveying := false
var _kn := 0.0                   ## 실제로 나고 있는 속도. 돛을 따라 서서히 붙는다

var found := {}
var visited := {}
var hired := false
var near_port = null
var ask_index := 0

var features: Array = []
var seen_features := {}
var sails_seen := {}            ## 수평선에서 본 다른 배
var other_ships: Array = []

var hull := HULL_MAX            ## 선체 내구도
var sea_state := 0.3            ## 0 잔잔 ~ 1 폭풍
var water_days := 40.0
var food_days := 40.0

var _wind_phase := 0.0
var _last_ground := -99.0
var _last_reveal := Vector2(999, 999)
var _in_storm := false
var _supply_warned := false
var _land_in_sight := false
var _ground_warned := false
var _last_scrape := -99.0
var _stuck_told := false        ## 물가에 처박혔다고 이미 말했는가
var _wrecked := false

func _init() -> void:
	_seed_features()
	_seed_ships()

# ── 눈에 들어오는 거리 ───────────────────────────────────────────
## 검증용으로 항구를 가깝게 둘 때는 시야도 같이 줄여야 한다.
## 안 그러면 출항하자마자 온 항구가 다 보인다.
func sight_base() -> float:
	return 12.0 if Geo.USE_TEST_PORTS else 26.0

func survey_km() -> float:
	return sight_base() * 2.8

func arrive_km() -> float:
	return 3.0 if Geo.USE_TEST_PORTS else 16.0

func sight_km() -> float:
	return survey_km() if surveying else sight_base()

# ── 바람 ────────────────────────────────────────────────────────
func wind_rel() -> float:
	return cos(deg_to_rad(heading - wind_brg))

func wind_mult() -> float:
	return 0.45 + 0.75 * (0.5 + 0.5 * wind_rel())

func wind_label() -> String:
	var r := wind_rel()
	if r > 0.55:
		return "순풍"
	elif r > -0.2:
		return "옆바람"
	return "역풍"

## 돛이 지시하는 속도. 실제 속도(_kn)는 여기까지 서서히 붙는다.
func ordered_knots() -> float:
	var kn: float = SAIL_KN[clampi(sails, 0, SAIL_KN.size() - 1)]
	if surveying:
		kn *= 0.34              # 측량 중엔 배를 세워 두다시피 한다
	# 긁힌 배는 물을 먹어 느려진다
	var wear := lerpf(0.55, 1.0, clampf(hull / HULL_MAX, 0.0, 1.0))
	return kn * wind_mult() * wear

func speed_knots() -> float:
	return _kn

## 돛이 완전히 펴졌을 때에 견준 지금의 속도. 물살·물보라·흔들림이 이걸 본다.
func speed01() -> float:
	return clampf(_kn / (SAIL_KN[FULL] * 1.15), 0.0, 1.0)

# ── 돛 ──────────────────────────────────────────────────────────
func set_sails(stage: int, reason := "") -> void:
	var s := clampi(stage, 0, SAIL_KN.size() - 1)
	if s == sails:
		return
	sails = s
	sails_changed.emit(s, reason)

func trim_sails(dir: int) -> void:
	set_sails(sails + dir)

# ── 진행 ────────────────────────────────────────────────────────
## 침로를 지시한다. 뱃머리는 여기까지 스스로 돌아간다.
func set_course(bearing: float) -> void:
	ordered_heading = fposmod(bearing, 360.0)

## 지시한 침로 쪽으로 조금씩 키를 잡는다. 가까운 쪽으로 돈다.
func steer(dt: float) -> void:
	var diff := fposmod(ordered_heading - heading + 180.0, 360.0) - 180.0
	if absf(diff) < 0.01:
		heading = ordered_heading
		return
	var rate := TURN_RATE * lerpf(TURN_STEERAGE, 1.0, clampf(speed_knots() / 6.0, 0.0, 1.0))
	heading = fposmod(heading + clampf(diff, -rate * dt, rate * dt), 360.0)

## 밖에서 뱃머리를 그대로 놓을 때 쓴다. 지시도 같이 맞춰야 되돌아가지 않는다.
func face(bearing: float) -> void:
	heading = fposmod(bearing, 360.0)
	ordered_heading = heading

func step(dt: float) -> void:
	# 시계는 고정이다. 하루는 언제나 실시간 1분.
	var dt_h := dt * CLOCK / 3600.0

	# 돛을 올리고 내리는 데 걸리는 만큼 속도가 따라온다
	_kn = move_toward(_kn, ordered_knots(),
		SAIL_KN[FULL] * dt / maxf(SAIL_EASE, 0.05))

	_wind_phase += dt_h * 0.06
	wind_brg = fposmod(210.0 + sin(_wind_phase) * 55.0 + sin(_wind_phase * 2.3) * 18.0, 360.0)
	_update_weather(dt_h)
	_burn_supplies(dt_h)
	_check_ground(dt_h)

	var km := speed_knots() * 1.852 * dt_h
	if km > 0.0:
		var nlon := lon + sin(deg_to_rad(heading)) * km / Geo.km_per_deg_lon(lat)
		var nlat := lat + cos(deg_to_rad(heading)) * km / Geo.KM_LAT
		# 해안에 닿아도 세우지 않는다. 갈 수 있는 쪽으로 미끄러지게 둔다.
		# 다만 물가 코앞은 막는다 — 안 막으면 배가 뭍 위로 올라앉는다.
		var was := Vector2(lon, lat)
		if not _blocked(nlon, nlat):
			lon = nlon
			lat = nlat
		elif not _blocked(nlon, lat):
			lon = nlon
		elif not _blocked(lon, nlat):
			lat = nlat
		lon = clamp(lon, Geo.LON_MIN, Geo.LON_MAX)
		lat = clamp(lat, Geo.LAT_MIN, Geo.LAT_MAX)

		# 뱃머리가 물가를 정면으로 밀고 있으면 옆으로 미끄러질 것도 없어서
		# 아무 말 없이 제자리에 선 채 선체만 깎인다. 그건 알려줘야 한다.
		# 같은 자리에 처박혀 있는 내내 되풀이하면 알림창에 그것만 남는다.
		# 한 번만 말하고, 물가에서 벗어나야 다시 말한다.
		var went := Geo.dist_km(was.x, was.y, lon, lat)
		if went < km * 0.15 and not _stuck_told:
			_stuck_told = true
			_last_ground = hours
			noted.emit("물이 얕다. 뱃머리를 돌려야 한다.", "warn")

	hours += dt_h
	_reveal()
	_check_ports()
	_check_features()
	_check_ships()
	_check_land()

func _reveal() -> void:
	var r := sight_km()
	if Geo.dist_km(_last_reveal.x, _last_reveal.y, lon, lat) < r * 0.32:
		return
	_last_reveal = Vector2(lon, lat)
	revealed.emit(lon, lat, r)

# ── 좌초 ────────────────────────────────────────────────────────
## 배가 들어갈 수 없는 자리인가. 뭍이거나 물가 코앞이면 못 간다.
## 항구는 원래 해안에 붙어 있으므로 입항 길은 열어둔다.
func _blocked(l: float, t: float) -> bool:
	if Geo.on_land(l, t):
		return true
	for p in Geo.ports():
		if Geo.dist_km(l, t, p.lon, p.lat) < arrive_km() * 1.6:
			return false
	return Geo.coast_dist_km(l, t) < GROUND_STOP_KM

## 해안에 붙으면 긁힌다. 배가 지리에 비해 크므로 실제로 얹히기 전에 경고가 온다.
func _check_ground(dt_h: float) -> void:
	# 항구는 원래 해안에 붙어 있다. 입항하러 들어가는 길을 좌초로 잡으면 안 된다.
	for p in Geo.ports():
		if Geo.dist_km(lon, lat, p.lon, p.lat) < arrive_km() * 1.6:
			_ground_warned = false
			return

	var d := Geo.coast_dist_km(lon, lat)

	if d > GROUND_HIT_KM:
		_stuck_told = false

	if d > GROUND_WARN_KM:
		_ground_warned = false
		return

	if not _ground_warned:
		_ground_warned = true
		noted.emit("여울이다. 뱃머리를 바다 쪽으로 돌려라.", "warn")

	if d >= GROUND_HIT_KM:
		return

	var bite := (GROUND_HIT_KM - d) / GROUND_HIT_KM
	hull = maxf(0.0, hull - HULL_RATE * bite * dt_h)
	if hull <= 0.0:
		if not _wrecked:
			_wrecked = true
			noted.emit("배가 갈라졌다. 더는 못 간다.", "warn")
			set_sails(FURLED, "파선")
	elif hours - _last_scrape > 3.0:
		_last_scrape = hours
		noted.emit("바닥이 긁힌다. 선체 %d%%." % int(hull), "warn")

# ── 세계가 알려주는 것들 ─────────────────────────────────────────
## 전에는 이것들이 배속을 저절로 풀었다. 지금은 알리기만 한다.
## 돛은 오직 뱃사람이 잡는다 — 볼 것이 있으면 스스로 접으면 된다.
## ① 육지 시인
func _check_land() -> void:
	var near := Geo.coast_dist_km(lon, lat) < sight_km() * 1.4
	if near and not _land_in_sight:
		_land_in_sight = true
		noted.emit("수평선에 육지가 걸린다.", "hi")
	elif not near:
		_land_in_sight = false

## ② 항구 접근  ③ 항구 발견
func _check_ports() -> void:
	var best = null
	var best_d := 1.0e9
	for p in Geo.ports():
		var d := Geo.dist_km(lon, lat, p.lon, p.lat)
		if d < sight_km() + arrive_km() * 0.5 and not found.has(p.name):
			found[p.name] = true
			noted.emit("수평선에 %s 보인다. 해도에 적어 넣는다." % Geo.josa(p.name, "이", "가"), "hi")
		if d < arrive_km() and d < best_d:
			best_d = d
			best = p
	near_port = best

## ④ 악천후
func _update_weather(dt_h: float) -> void:
	var t := hours * 0.03
	sea_state = clampf(0.42 + sin(t) * 0.33 + sin(t * 2.7 + 1.3) * 0.2, 0.0, 1.0)
	var storm := sea_state > 0.72
	if storm and not _in_storm:
		_in_storm = true
		noted.emit("바다가 거칠어진다. 물마루가 부서진다.", "warn")
	elif not storm and _in_storm and sea_state < 0.62:
		_in_storm = false
		noted.emit("파도가 잦아들었다.", "")

## ⑤ 보급 경고
func _burn_supplies(dt_h: float) -> void:
	var days := dt_h / 24.0
	water_days = maxf(0.0, water_days - days)
	food_days = maxf(0.0, food_days - days)
	if not _supply_warned and minf(water_days, food_days) < 10.0:
		_supply_warned = true
		var what := "물" if water_days <= food_days else "식량"
		noted.emit("%s이 열흘치도 남지 않았다." % what, "warn")

## 다른 배 — 수평선의 돛
func _check_ships() -> void:
	for s in other_ships:
		if sails_seen.has(s.id):
			continue
		if Geo.dist_km(lon, lat, s.lon, s.lat) < sight_km():
			sails_seen[s.id] = true
			noted.emit("수평선에 돛이 하나 보인다.", "hi")

# ── 항구 ────────────────────────────────────────────────────────
func enter_port() -> void:
	if near_port == null:
		return
	var p = near_port
	set_sails(FURLED, "입항")
	water_days = 40.0
	food_days = 40.0
	_supply_warned = false
	# 항구에서는 긁힌 데도 손본다
	var patched := hull < HULL_MAX - 1.0
	hull = HULL_MAX
	_wrecked = false
	if not visited.has(p.name):
		visited[p.name] = true
		noted.emit("%s 입항. 닻을 내리고 물과 식량을 채웠다." % p.name, "hi")
		if p.get("hires", false) and not hired:
			hired = true
			spoke.emit("유수프", "마그레브 사람입니다. 남쪽 물길이라면 제가 압니다. 태워 주시겠습니까.")
			noted.emit("유수프를 배에 태웠다. 남쪽 연안이 열렸다.", "hi")
		else:
			spoke.emit("주앙", "%s입니다. 닻을 내렸습니다." % p.name)
	else:
		spoke.emit("주앙", "%s에 다시 들렀습니다. 물과 식량을 채웠습니다." % p.name)
	if patched:
		noted.emit("선체를 손봤다.", "hi")

func ask_crew() -> void:
	var left: Array = []
	for p in Geo.ports():
		if p.home:
			continue
		if p.region == "마그레브" and not hired:
			continue
		if not visited.has(p.name):
			left.append(p)
	if left.is_empty():
		spoke.emit("주앙", "이 근방은 다 돌았습니다. 더 먼 데를 아는 사람이 필요합니다.")
		return

	var p = left[ask_index % left.size()]
	ask_index += 1
	var dir: String = Geo.COMPASS8[int(round(bearing_to(p.lon, p.lat) / 45.0)) % 8]
	var d := Geo.dist_km(lon, lat, p.lon, p.lat)
	# 며칠 걸리는지로 말한다. 이 게임에서 거리의 단위는 날짜다.
	var days := d / maxf(speed_knots() * 1.852 * 24.0, 1.0)
	var far := "먼 길입니다"
	if days < 0.25:
		far = "바로 눈앞입니다"
	elif days < 0.7:
		far = "반나절이면 닿습니다"
	elif days < 1.6:
		far = "하루는 잡으셔야 합니다"
	elif days < 4.0:
		far = "사나흘 걸립니다"
	var who := "유수프" if p.region == "마그레브" else "주앙"
	spoke.emit(who, "%s요? %s쪽입니다. %s." % [p.name, dir, far])

func bearing_to(to_lon: float, to_lat: float) -> float:
	var de := (to_lon - lon) * Geo.km_per_deg_lon(lat)
	var dn := (to_lat - lat) * Geo.KM_LAT
	return fposmod(rad_to_deg(atan2(de, dn)), 360.0)

func clock() -> String:
	var d := int(hours / 24.0)
	var h := int(fmod(hours, 24.0))
	var m := int(fmod(hours, 1.0) * 60.0)
	return "%d일 %02d:%02d" % [d, h, m]

func is_night() -> bool:
	var t := fmod(hours, 24.0)
	return t < 5.5 or t > 19.5

# ── 바다에 흩어진 것들 ───────────────────────────────────────────
const FEATURE_KINDS := [
	{ "kind": "새떼", "near": [0.0, 90.0], "msg": "육지 새가 무리지어 난다." },
	{ "kind": "표류물", "near": [0.0, 200.0], "msg": "부러진 나뭇가지가 떠다닌다." },
	{ "kind": "암초", "near": [0.0, 60.0], "msg": "물이 하얗게 부서진다. 암초다." },
	{ "kind": "어장", "near": [20.0, 140.0], "msg": "물고기 떼가 수면을 뒤집는다." },
]

func _seed_features() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77239
	var guard := 0
	while features.size() < 54 and guard < 5000:
		guard += 1
		var flon := rng.randf_range(Geo.LON_MIN, Geo.LON_MAX)
		var flat := rng.randf_range(Geo.LAT_MIN, Geo.LAT_MAX)
		if Geo.on_land(flon, flat):
			continue
		var cd := Geo.coast_dist_km(flon, flat)
		var pool: Array = []
		for k in FEATURE_KINDS:
			if cd >= k.near[0] and cd <= k.near[1]:
				pool.append(k)
		if pool.is_empty():
			continue
		var k = pool[rng.randi() % pool.size()]
		features.append({
			"lon": flon, "lat": flat, "kind": k.kind,
			"msg": k.msg, "id": features.size(),
		})

func _seed_ships() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var guard := 0
	while other_ships.size() < 10 and guard < 2000:
		guard += 1
		var slon := rng.randf_range(Geo.LON_MIN, Geo.LON_MAX)
		var slat := rng.randf_range(Geo.LAT_MIN, Geo.LAT_MAX)
		if Geo.on_land(slon, slat):
			continue
		other_ships.append({
			"lon": slon, "lat": slat, "id": other_ships.size(),
			"heading": rng.randf_range(0.0, 360.0),
		})

func _check_features() -> void:
	var r := sight_km() * 0.8
	for f in features:
		if seen_features.has(f.id):
			continue
		if Geo.dist_km(lon, lat, f.lon, f.lat) < r:
			seen_features[f.id] = true
			noted.emit(f.msg, "")
