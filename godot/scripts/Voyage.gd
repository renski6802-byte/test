class_name Voyage
extends RefCounted

## 항해 그 자체. 그리기와 무관한 상태와 규칙만 여기에 둔다.

signal noted(text: String, kind: String)      ## 세계가 알려주는 것
signal spoke(who: String, text: String)       ## 사람이 하는 말
signal revealed(lon: float, lat: float, radius_km: float)

const SIGHT_KM := 26.0
const SURVEY_KM := 72.0
const ARRIVE_KM := 16.0
const HOURS_PER_SEC := 0.34     ## 실시간 1초 ≈ 게임 20분
const BASE_KN := 4.2            ## 돛 한 단당. 전개하면 두 배

var lon := -9.50
var lat := 38.62
var heading := 175.0            ## 도, 0 = 북
var sails := 1                  ## 0 정박 / 1 반 / 2 전개
var wind_brg := 210.0
var hours := 8.0
var surveying := false

var found := {}                 ## 해도에 적어 넣은 항구
var visited := {}
var hired := false              ## 마그레브를 아는 항해사를 태웠는가
var near_port = null
var ask_index := 0

var features: Array = []        ## 바다에 흩어진 것들
var seen_features := {}

var _wind_phase := 0.0
var _last_ground := -99.0
var _last_reveal := Vector2(999, 999)

func _init() -> void:
	_seed_features()

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

func speed_knots() -> float:
	var s := float(min(sails, 2)) * 0.34 if surveying else float(sails)
	return BASE_KN * s * wind_mult()

func sight_km() -> float:
	return SURVEY_KM if surveying else SIGHT_KM

# ── 진행 ────────────────────────────────────────────────────────
func step(dt: float) -> void:
	_wind_phase += dt * 0.05
	wind_brg = fposmod(210.0 + sin(_wind_phase) * 55.0 + sin(_wind_phase * 2.3) * 18.0, 360.0)

	var dt_h := dt * HOURS_PER_SEC
	var km := speed_knots() * 1.852 * dt_h

	if km > 0.0:
		var nlon := lon + sin(deg_to_rad(heading)) * km / Geo.km_per_deg_lon(lat)
		var nlat := lat + cos(deg_to_rad(heading)) * km / Geo.KM_LAT
		# 해안에 닿아도 세우지 않는다. 갈 수 있는 쪽으로 미끄러지게 둔다.
		if not Geo.on_land(nlon, nlat):
			lon = nlon
			lat = nlat
		elif not Geo.on_land(nlon, lat):
			lon = nlon
		elif not Geo.on_land(lon, nlat):
			lat = nlat
		elif hours - _last_ground > 2.0:
			_last_ground = hours
			noted.emit("물이 얕다. 뱃머리를 돌려야 한다.", "warn")
		lon = clamp(lon, Geo.LON_MIN, Geo.LON_MAX)
		lat = clamp(lat, Geo.LAT_MIN, Geo.LAT_MAX)

	hours += dt_h
	_reveal()
	_check_ports()
	_check_features()

func _reveal() -> void:
	var r := sight_km()
	if Geo.dist_km(_last_reveal.x, _last_reveal.y, lon, lat) < r * 0.32:
		return
	_last_reveal = Vector2(lon, lat)
	revealed.emit(lon, lat, r)

func _check_ports() -> void:
	var best = null
	var best_d := 1.0e9
	for p in Geo.PORTS:
		var d := Geo.dist_km(lon, lat, p.lon, p.lat)
		if d < sight_km() + 8.0 and not found.has(p.name):
			found[p.name] = true
			noted.emit("수평선에 %s 보인다. 해도에 적어 넣는다." % Geo.josa(p.name, "이", "가"), "hi")
		if d < ARRIVE_KM and d < best_d:
			best_d = d
			best = p
	near_port = best

func enter_port() -> void:
	if near_port == null:
		return
	var p = near_port
	sails = 0
	if not visited.has(p.name):
		visited[p.name] = true
		noted.emit("%s 입항. 닻을 내린다." % p.name, "hi")
		if p.get("hires", false) and not hired:
			hired = true
			spoke.emit("유수프", "마그레브 사람입니다. 남쪽 물길이라면 제가 압니다. 태워 주시겠습니까.")
			noted.emit("유수프를 배에 태웠다. 남쪽 연안이 열렸다.", "hi")
		else:
			spoke.emit("주앙", "%s입니다. 닻을 내렸습니다." % p.name)
	else:
		spoke.emit("주앙", "%s에 다시 들렀습니다." % p.name)

## 선원에게 묻는다 — 목록이 아니라 대답으로 돌아온다
func ask_crew() -> void:
	var left: Array = []
	for p in Geo.PORTS:
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
	var far := "먼 길입니다"
	if d < 25.0:
		far = "바로 눈앞입니다"
	elif d < 90.0:
		far = "반나절이면 닿습니다"
	elif d < 200.0:
		far = "하루는 잡으셔야 합니다"
	elif d < 400.0:
		far = "이삼일은 걸립니다"
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

func _check_features() -> void:
	var r := sight_km() * 0.8
	for f in features:
		if seen_features.has(f.id):
			continue
		if Geo.dist_km(lon, lat, f.lon, f.lat) < r:
			seen_features[f.id] = true
			noted.emit(f.msg, "")
