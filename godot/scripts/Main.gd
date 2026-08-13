extends Control

## 화면 하나가 곧 게임이다. 위 78%는 바다, 아래 22%는 슬롯 넷의 띠.
## 3D 는 SubViewport 안에서만 그려지므로 띠가 바다를 덮지 않는다.

const SCENE_RATIO := 78.0
const BAND_RATIO := 22.0

var voyage: Voyage
var sky_dome: SkyDome
var stars: StarField
var coast: CoastMesh
var _sails_afloat: Array = []
var _sail_plate_until := 0.0
var ocean: Ocean
var rig: CameraRig
var ship: Node3D
var sails_node: Node3D
var band: BandView
var chart: ChartView

var _viewport: SubViewport
var _spray: Spray
var _scene_wrap: Control
var _chart_layer: Control
var _prompt: Label
var _camhint: Label
var _speedplate: Label
var _surveying: Label
var _sun: DirectionalLight3D
var _sky: ShaderMaterial
var _env: Environment

var _time := 0.0

func _ready() -> void:
	voyage = Voyage.new()
	sky_dome = SkyDome.new()

	_build_layout()
	_build_world()
	_wire()
	_setup_land_cut()

	voyage.noted.emit("리스보아를 나섰다.", "")
	_maybe_capture()

## 육지와 바다를 나누는 값들. 셋(육지·가까운 바다·먼 바다)이 같은 값을 봐야
## 물가가 한 줄로 떨어진다. 그래서 한자리에서만 넣는다.
func _land_cut_materials() -> Array:
	var mats: Array = [coast.sky_material()]
	mats.append_array(ocean.sky_materials())
	return mats

func _setup_land_cut() -> void:
	var ib := PackedVector2Array(Geo.poly_iberia())
	var af := PackedVector2Array(Geo.poly_africa())
	for m in _land_cut_materials():
		if m == null:
			continue
		m.set_shader_parameter("near_scale", Geo.LAND_NEAR_SCALE)
		m.set_shader_parameter("far_scale", Geo.LAND_SCALE)
		m.set_shader_parameter("blend_near_m", Geo.BLEND_NEAR_M)
		m.set_shader_parameter("blend_far_m", Geo.BLEND_FAR_M)
		m.set_shader_parameter("coast_ib", ib)
		m.set_shader_parameter("coast_af", af)
		m.set_shader_parameter("geo_origin", Vector2(Geo.ORIGIN_LON, Geo.ORIGIN_LAT))
		m.set_shader_parameter("km_lat", Geo.KM_LAT)

func _follow_land_cut() -> void:
	var here := Geo.to_metres(voyage.lon, voyage.lat)
	var geo := Vector2(here.x, here.z)
	var world := Vector2(ship.global_position.x, ship.global_position.z)
	for m in _land_cut_materials():
		if m == null:
			continue
		m.set_shader_parameter("ship_geo", geo)
		m.set_shader_parameter("ship_world", world)

## 개발용. 이렇게 부르면 잠시 항해한 뒤 화면을 파일로 남기고 끝낸다.
##   godot --path godot -- --shot out.png --wait 6 --heading 150 --yaw -40
## 에디터를 띄우지 않고 화면을 확인하려고 둔 통로다.
func _maybe_capture() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--shot"):
		return

	var get_arg := func(flag: String, fallback: String) -> String:
		var i := args.find(flag)
		return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback

	var path := get_arg.call("--shot", "shot.png") as String
	var wait := float(get_arg.call("--wait", "5"))
	# --at "-8.99,37.05" 처럼 주면 그 자리에서 시작한다. 해안을 보러 갈 때 쓴다.
	var at := get_arg.call("--at", "") as String
	if at != "":
		var parts := at.split(",")
		if parts.size() == 2:
			voyage.lon = float(parts[0])
			voyage.lat = float(parts[1])
	voyage.face(float(get_arg.call("--heading", str(voyage.heading))))
	voyage.sails = int(get_arg.call("--sails", "2"))
	rig.yaw = float(get_arg.call("--yaw", "0"))
	rig.pitch = float(get_arg.call("--pitch", str(rig.pitch)))
	rig.distance = float(get_arg.call("--dist", str(rig.distance)))
	rig.snap()
	voyage.hours = float(get_arg.call("--hour", str(voyage.hours)))

	if args.has("--frames"):
		await _capture_reel(path, int(get_arg.call("--frames", "60")),
			float(get_arg.call("--fps", "12")))
		return

	await get_tree().create_timer(wait).timeout
	if args.has("--chart"):
		_toggle_chart()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("찍음: ", path)
	get_tree().quit()

## 조타와 시점 조작을 스스로 하며 연속으로 찍는다. 움직이는 화면을 보여주려는 것.
func _capture_reel(path_base: String, frames: int, fps: float) -> void:
	var dt := 1.0 / fps
	for i in frames:
		var t := float(i) / float(frames)
		# 앞부분은 뱃머리를 돌리고, 뒷부분은 고개를 왼쪽으로 돌려 해안을 본다
		if t < 0.45:
			voyage.face(voyage.heading + 22.0 * dt)
		else:
			rig.yaw = clampf(rig.yaw - 26.0 * dt, -60.0, 60.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path_base % i)
	print("연속 촬영 끝: ", frames)
	get_tree().quit()

# ── 화면 ────────────────────────────────────────────────────────
func _build_layout() -> void:
	# Control 은 기본이 MOUSE_FILTER_STOP 이라 그냥 두면 화면을 덮은 컨트롤이
	# 마우스를 전부 먹는다. 시점 조작은 _unhandled_input 에서 받으므로,
	# 바다 위를 덮는 것들은 모두 마우스를 흘려보내야 한다.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	_scene_wrap = Control.new()
	_scene_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_wrap.size_flags_stretch_ratio = SCENE_RATIO
	_scene_wrap.clip_contents = true
	_scene_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_scene_wrap)

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_wrap.add_child(vpc)

	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	vpc.add_child(_viewport)

	_surveying = _plate("측량 중 — 배가 느려집니다", Pal.HUD_GOLD)
	_surveying.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_surveying.offset_top = 12
	_surveying.visible = false
	_scene_wrap.add_child(_surveying)

	_speedplate = _plate("", Pal.HUD_GOLD)
	_speedplate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_speedplate.offset_top = 44
	_speedplate.visible = false
	_scene_wrap.add_child(_speedplate)

	_camhint = _plate("", Pal.HUD_GOLD)
	_camhint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_camhint.offset_top = 12
	_camhint.offset_right = -12
	_camhint.visible = false
	_scene_wrap.add_child(_camhint)

	_prompt = _plate("", Pal.HUD_INK)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_bottom = -14
	_prompt.visible = false
	_scene_wrap.add_child(_prompt)

	band = BandView.new()
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.size_flags_stretch_ratio = BAND_RATIO
	col.add_child(band)

	# 전체 해도 — 평소엔 숨어 있다가 M 으로 펼친다
	_chart_layer = Control.new()
	_chart_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chart_layer.visible = false
	# 아무 곳이나 눌러 닫는 것도 _unhandled_input 이 받는다
	_chart_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chart_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.043, 0.086, 0.133, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart_layer.add_child(dim)

	chart = ChartView.new()
	chart.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chart.offset_left = 24
	chart.offset_top = 24
	chart.offset_right = -24
	chart.offset_bottom = -46
	chart.voyage = voyage
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart_layer.add_child(chart)

	var hint := Label.new()
	hint.text = "아무 곳이나 눌러 닫기"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(Pal.HUD_INK, 0.65))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_bottom = -16
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart_layer.add_child(hint)

	band.minimap.voyage = voyage

func _plate(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Pal.HUD_PLATE
	sb.border_color = Color(col, 0.45)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(7)
	l.add_theme_stylebox_override("normal", sb)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ── 세계 ────────────────────────────────────────────────────────
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	_sky = ShaderMaterial.new()
	_sky.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	# 번짐이 세면 가까운 물의 반짝임이 화면 전체로 퍼져 수평선까지 들어올린다.
	# 문턱을 올려 정말 밝은 것만 번지게 한다.
	e.glow_intensity = 0.16
	e.glow_hdr_threshold = 1.35
	e.fog_enabled = true
	# 안개가 짙으면 먼바다가 통째로 하늘색이 된다. 16km 앞이 43% 하늘색이었다.
	e.fog_density = 0.000012
	# 안개가 픽셀 방향의 하늘색을 따라간다. 수평선 아래를 보는 물에게 그 하늘은
	# 수평선 아래쪽 색이라 어둡다. 그래서 먼바다가 하늘로 녹지 않고 물빛으로 물러난다.
	e.fog_aerial_perspective = 0.55
	e.fog_sky_affect = 0.0
	env.environment = e
	_env = e
	_viewport.add_child(env)

	_sun = DirectionalLight3D.new()
	_sun.light_energy = 1.15
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 900.0
	_viewport.add_child(_sun)

	ocean = Ocean.new()
	ocean.name = "Ocean"
	_viewport.add_child(ocean)

	stars = StarField.new()
	stars.name = "Stars"
	_viewport.add_child(stars)

	coast = CoastMesh.new()
	coast.name = "Coast"
	_viewport.add_child(coast)

	ship = ShipModel.build()
	sails_node = ship.get_node_or_null("Sails")
	_spray = Spray.new()
	_spray.name = "Spray"
	ship.add_child(_spray)
	_viewport.add_child(ship)

	# 남의 배도 육지와 같은 축척으로 놓는다. 바다 축척으로 두면 50km 밖의 배가
	# 135m 앞에 서고 5km 밖의 배는 우리 선체 안에 들어온다.
	for s in voyage.other_ships:
		var mark := _distant_sail()
		mark.rotation.y = -deg_to_rad(s.heading)
		_viewport.add_child(mark)
		_sails_afloat.append({"node": mark, "lon": s.lon, "lat": s.lat})

	rig = CameraRig.new()
	rig.name = "CameraRig"
	_viewport.add_child(rig)

## 남의 배를 육지와 같은 축척으로 배 주위에 놓는다.
func _place_far_sails() -> void:
	var here := Geo.to_metres(voyage.lon, voyage.lat)
	for e in _sails_afloat:
		var off := (Geo.to_metres(e.lon, e.lat) - here) * Geo.LAND_SCALE
		var n: Node3D = e.node
		n.global_position = Vector3(
			ship.global_position.x + off.x, 0.0, ship.global_position.z + off.z)

## 수평선에 보이는 남의 돛. 가까이 갈 일이 아직 없으니 단순하게 둔다.
func _distant_sail() -> Node3D:
	var n := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("e8dfc6")
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for spec in [[Vector2(12.0, 9.0), 13.0], [Vector2(9.0, 5.5), 6.5]]:
		var q := QuadMesh.new()
		q.size = spec[0]
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.position = Vector3(0, spec[1], 0)
		mi.material_override = m
		n.add_child(mi)
	var hull := BoxMesh.new()
	hull.size = Vector3(6.0, 3.0, 18.0)
	var hi := MeshInstance3D.new()
	hi.mesh = hull
	hi.position = Vector3(0, 1.0, 0)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color("46351f")
	hm.roughness = 0.9
	hi.material_override = hm
	n.add_child(hi)
	return n

func _wire() -> void:
	voyage.noted.connect(func(t: String, k: String): band.add_note(t, k))
	voyage.spoke.connect(func(w: String, t: String): band.set_say(w, t))
	voyage.revealed.connect(func(lon: float, lat: float, _r: float):
		chart.add_track(lon, lat))

	band.asked.connect(func(): voyage.ask_crew())
	band.port_entered.connect(func(): voyage.enter_port())
	voyage.sails_changed.connect(func(stage: int, reason: String):
		_flash_sails(stage, reason))
	band.chart_toggled.connect(_toggle_chart)
	band.survey_held.connect(func(down: bool): voyage.surveying = down)

	# 출항 자리도 해도에 남긴다
	chart.add_track(voyage.lon, voyage.lat)

## 돛이 바뀔 때마다 잠깐 띄운다. 저절로 줄어든 것이면 까닭도 같이 적는다.
func _flash_sails(stage: int, reason: String) -> void:
	_speedplate.visible = true
	_sail_plate_until = _time + (3.4 if reason != "" else 1.8)
	var name: String = Voyage.SAIL_NAME[clampi(stage, 0, Voyage.SAIL_NAME.size() - 1)]
	_speedplate.text = "돛 %s — %s" % [name, reason] if reason != "" else "돛 %s" % name

func _toggle_chart() -> void:
	_chart_layer.visible = not _chart_layer.visible
	if _chart_layer.visible:
		chart.queue_redraw()

# ── 매 프레임 ───────────────────────────────────────────────────
func _process(delta: float) -> void:
	_time += delta

	if not _chart_layer.visible:
		var turn := 0.0
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
			turn -= 1.0
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
			turn += 1.0
		# 키도 지시를 옮길 뿐이다. 뱃머리는 제 속도로 따라 돈다.
		if turn != 0.0:
			voyage.set_course(voyage.ordered_heading + turn * Voyage.TURN_RATE * delta)
		voyage.steer(delta)
		voyage.step(delta)

	ocean.choppiness = lerpf(0.55, 1.75, voyage.sea_state)

	_place_ship()
	rig.place(ship.global_position, voyage.heading, delta)
	ocean.follow(ship.global_position)
	# 육지는 바다와 다른 축척이라 배를 기준으로 따로 눌러 놓는다
	coast.follow(ship.global_position, voyage.lon, voyage.lat, _time)
	_follow_land_cut()
	_place_far_sails()
	_update_wake()
	_update_sky()
	_update_hud()
	band.refresh(voyage, voyage.heading + rig.view_yaw())

## 뱃머리가 가르는 물살과 물보라. 둘 다 속력을 그대로 따라간다.
func _update_wake() -> void:
	var a := deg_to_rad(voyage.heading)
	var fwd := Vector2(sin(a), -cos(a))
	var sp01 := voyage.speed01()
	ocean.set_ship(ship.global_position, fwd, sp01)
	_spray.set_speed01(sp01)

## 배를 파도 위에 올린다. 앞뒤·좌우 네 점의 물 높이로 기울기를 구한다.
func _place_ship() -> void:
	var wp := Geo.to_world(voyage.lon, voyage.lat)
	var here := ocean.displace_at(wp.x, wp.z, _time)
	ship.global_position = Vector3(wp.x, here.y, wp.z)

	var a := deg_to_rad(voyage.heading)
	var fwd := Vector3(sin(a), 0.0, -cos(a))
	var right := Vector3(cos(a), 0.0, sin(a))

	var hf := ocean.height_at(wp.x + fwd.x * 11.0, wp.z + fwd.z * 11.0, _time)
	var hb := ocean.height_at(wp.x - fwd.x * 11.0, wp.z - fwd.z * 11.0, _time)
	var hr := ocean.height_at(wp.x + right.x * 4.0, wp.z + right.z * 4.0, _time)
	var hl := ocean.height_at(wp.x - right.x * 4.0, wp.z - right.z * 4.0, _time)

	var pitch := atan2(hb - hf, 22.0)
	var roll := atan2(hr - hl, 8.0)
	# 바람을 옆으로 받으면 배가 기운다. 돛만 돌리면 돛대 높이만큼 옆으로 밀려난다.
	roll += sin(deg_to_rad(voyage.wind_brg - voyage.heading)) * 0.17 * voyage.speed01()

	var b := Basis(Vector3.UP, -a)
	b = b * Basis(Vector3.RIGHT, pitch)
	b = b * Basis(Vector3.BACK, roll)
	ship.global_transform = Transform3D(b, ship.global_position)


func _update_sky() -> void:
	# 해와 달을 위도와 시각으로 제자리에 놓는다. 동에서 떠서 남중하고 서로 진다.
	sky_dome.update(voyage.hours, voyage.lat)
	var day := sky_dome.day01()
	var dusk := sky_dome.dusk01()

	# 하늘과 바다가 같은 값을 봐야 물에 비친 하늘이 실제 하늘과 어긋나지 않는다
	var mats: Array = [_sky, coast.sky_material()]
	mats.append_array(ocean.sky_materials())
	sky_dome.push(mats)

	# 밤에는 달빛으로 갈아탄다. 달도 제 궤도를 도므로 그림자가 달 쪽으로 눕는다.
	var lit_dir: Vector3 = sky_dome.sun_dir if day > 0.02 else sky_dome.moon_dir
	# 빛이 지평 아래에서 오면 그림자가 뒤집힌다. 그때는 위에서 내려오게 세운다.
	if lit_dir.y < 0.12:
		lit_dir = (lit_dir + Vector3.UP * 0.9).normalized()
	_sun.look_at_from_position(Vector3.ZERO, -lit_dir, Vector3.UP)

	var moon_col := Color(0.62, 0.72, 1.0)
	_sun.light_color = moon_col.lerp(Color(1.0, 0.95, 0.88), day) \
		.lerp(Color(1.0, 0.72, 0.48), dusk * 0.8)
	_sun.light_energy = lerpf(0.30, 1.25, day)

	# 해가 낮으면 반짝임 길이 수평선까지 길게 누워 화면을 태운다. 새벽에 가까운
	# 바다가 하늘만큼 밝아졌던 원인이다. 고도가 낮을수록 반사광만 눌러준다.
	var lit_alt := rad_to_deg(asin(clampf(lit_dir.y, -1.0, 1.0)))
	_sun.light_specular = lerpf(0.10, 1.0, clampf(lit_alt / 55.0, 0.0, 1.0))

	# 밤에는 하늘이 어두워 하늘빛만으로는 아무것도 안 보인다. 바닥을 깔아준다.
	_env.ambient_light_color = Color(0.17, 0.23, 0.36)
	_env.ambient_light_energy = lerpf(0.75, 1.0, day)
	_env.ambient_light_sky_contribution = lerpf(0.18, 0.5, day)

	# 안개는 지평 언저리 하늘을 따라간다. 다만 하늘색 그대로 쓰면 먼바다가
	# 수평선에서 하늘에 녹아 사라진다. 실제로는 멀어져도 물빛이 남는다.
	var horizon := Color(0.118, 0.156, 0.246).lerp(Color(0.639, 0.757, 0.855), day)
	horizon = horizon.lerp(Color(0.882, 0.545, 0.310), dusk * 0.55)
	_env.fog_light_color = horizon.lerp(Color(0.10, 0.20, 0.30), 0.52)

	# 별은 천구에 박혀 있고 배를 따라다닌다. 낮에는 하늘에 묻혀 안 보인다.
	stars.orient(voyage.hours, voyage.lat, rig.camera.global_position,
		clampf(1.0 - day * 1.35, 0.0, 1.0))


func _update_hud() -> void:
	_surveying.visible = voyage.surveying

	if _speedplate.visible and _time > _sail_plate_until:
		_speedplate.visible = false

	_camhint.visible = rig.is_off_center()
	if _camhint.visible:
		var off := wrapf(rig.view_yaw(), -180.0, 180.0)
		var side := "왼쪽" if off < 0.0 else "오른쪽"
		_camhint.text = "%s %d° 보는 중 — C 또는 가운데 버튼으로 정면" % [side, int(absf(off))]

	var p = voyage.near_port
	_prompt.visible = p != null and not _chart_layer.visible
	if _prompt.visible:
		if voyage.visited.has(p.name):
			_prompt.text = "%s — 입항할 수 있습니다" % p.name
		else:
			_prompt.text = "%s 눈앞이다" % Geo.josa(p.name, "이", "가")

# ── 조작 ────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if _chart_layer.visible:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_toggle_chart()
		elif event is InputEventKey and (event as InputEventKey).pressed:
			var kc := (event as InputEventKey).keycode
			if kc == KEY_M or kc == KEY_ESCAPE:
				_toggle_chart()
		return

	var in_scene := _scene_wrap.get_global_rect().has_point(get_global_mouse_position())
	if rig.handle_input(event, in_scene):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 시점은 오른쪽 버튼이 맡으므로 왼쪽은 조타만 한다
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and in_scene:
			_steer_towards(mb.position)

	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				voyage.trim_sails(1)
			KEY_DOWN, KEY_S:
				voyage.trim_sails(-1)
			KEY_SPACE:
				voyage.surveying = true
			KEY_M:
				_toggle_chart()
			KEY_E:
				voyage.enter_port()
			KEY_Q:
				voyage.ask_crew()
			KEY_C:
				rig.recenter()
			KEY_1:
				voyage.set_sails(Voyage.FURLED)
			KEY_2:
				voyage.set_sails(Voyage.SLOW)
			KEY_3:
				voyage.set_sails(Voyage.CRUISE)
			KEY_4:
				voyage.set_sails(Voyage.FULL)

	elif event is InputEventKey and not (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_SPACE:
			voyage.surveying = false

## 화면에서 고른 자리 쪽으로 침로를 지시한다. 고개를 돌려둔 만큼을 더해준다.
## 뱃머리가 그 자리에서 홱 돌지는 않는다 — 지시만 바뀌고 배는 제 속도로 돈다.
func _steer_towards(screen_pos: Vector2) -> void:
	var local := screen_pos - _scene_wrap.get_global_rect().position
	var rel := rig.screen_bearing(local, _scene_wrap.size)
	voyage.set_course(voyage.heading + rel)
