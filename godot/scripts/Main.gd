extends Control

## 화면 하나가 곧 게임이다. 위 78%는 바다, 아래 22%는 슬롯 넷의 띠.
## 3D 는 SubViewport 안에서만 그려지므로 띠가 바다를 덮지 않는다.

const SCENE_RATIO := 78.0
const BAND_RATIO := 22.0

var voyage: Voyage
var fog: Fog
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
var _sky: ProceduralSkyMaterial
var _env: Environment

var _time := 0.0

func _ready() -> void:
	voyage = Voyage.new()
	fog = Fog.new()

	_build_layout()
	_build_world()
	_wire()

	voyage.noted.emit("리스보아를 나섰다.", "")
	_maybe_capture()

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
	voyage.heading = float(get_arg.call("--heading", str(voyage.heading)))
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
			voyage.heading = fposmod(voyage.heading + 22.0 * dt, 360.0)
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
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	_scene_wrap = Control.new()
	_scene_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_wrap.size_flags_stretch_ratio = SCENE_RATIO
	_scene_wrap.clip_contents = true
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
	add_child(_chart_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.043, 0.086, 0.133, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chart_layer.add_child(dim)

	chart = ChartView.new()
	chart.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chart.offset_left = 24
	chart.offset_top = 24
	chart.offset_right = -24
	chart.offset_bottom = -46
	chart.fog = fog
	chart.voyage = voyage
	_chart_layer.add_child(chart)

	var hint := Label.new()
	hint.text = "아무 곳이나 눌러 닫기"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(Pal.HUD_INK, 0.65))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_bottom = -16
	_chart_layer.add_child(hint)

	band.minimap.fog = fog
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
	_sky = ProceduralSkyMaterial.new()
	_sky.sun_angle_max = 12.0
	_sky.sun_curve = 0.18
	var sky := Sky.new()
	sky.sky_material = _sky
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.fog_enabled = true
	e.fog_density = 0.000035
	e.fog_aerial_perspective = 0.35
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

	_viewport.add_child(CoastMesh.build())

	ship = ShipModel.build()
	sails_node = ship.get_node_or_null("Sails")
	_spray = Spray.new()
	_spray.name = "Spray"
	ship.add_child(_spray)
	_viewport.add_child(ship)

	for s in voyage.other_ships:
		var mark := _distant_sail()
		mark.position = Geo.to_world(s.lon, s.lat)
		mark.rotation.y = -deg_to_rad(s.heading)
		_viewport.add_child(mark)

	rig = CameraRig.new()
	rig.name = "CameraRig"
	_viewport.add_child(rig)

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
	voyage.revealed.connect(func(lon: float, lat: float, r: float):
		fog.punch(lon, lat, r)
		chart.add_track(lon, lat))

	band.asked.connect(func(): voyage.ask_crew())
	band.port_entered.connect(func(): voyage.enter_port())
	voyage.time_scale_changed.connect(func(_s: float, reason: String):
		if reason != "":
			_flash_release(reason))
	band.chart_toggled.connect(_toggle_chart)
	band.survey_held.connect(func(down: bool): voyage.surveying = down)

	# 출항 자리도 해도에 남긴다
	fog.punch(voyage.lon, voyage.lat, voyage.sight_km())
	chart.add_track(voyage.lon, voyage.lat)

func _flash_release(reason: String) -> void:
	_speedplate.visible = true
	_speedplate.text = "배속 해제 — %s" % reason

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
		if turn != 0.0:
			voyage.heading = fposmod(voyage.heading + turn * 46.0 * delta, 360.0)
		voyage.step(delta)

	var fast := clampf((voyage.time_scale - 4.0) / 56.0, 0.0, 1.0)
	ocean.choppiness = lerpf(0.55, 1.75, voyage.sea_state) * lerpf(1.0, 0.28, fast)

	_place_ship()
	rig.place(ship.global_position, voyage.heading, delta)
	ocean.follow(ship.global_position)
	_update_wake()
	_update_sky()
	_update_hud()
	band.refresh(voyage)

## 뱃머리가 가르는 물살과 물보라. 둘 다 속력을 그대로 따라간다.
func _update_wake() -> void:
	var a := deg_to_rad(voyage.heading)
	var fwd := Vector2(sin(a), -cos(a))
	var sp01 := clampf(voyage.speed_knots() / 10.0, 0.0, 1.0)
	ocean.set_ship(ship.global_position, fwd, sp01)

	# 배속을 올리면 배가 세계를 훌쩍훌쩍 건너뛴다. 물방울은 태어난 자리에 남으므로
	# 그때 물보라를 계속 뿜으면 배 뒤로 흰 줄이 길게 끌린다. 그래서 끊는다.
	_spray.set_speed01(sp01 if voyage.time_scale <= 4.0 else 0.0)

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
	roll += sin(deg_to_rad(voyage.wind_brg - voyage.heading)) * 0.085 * float(voyage.sails)

	var b := Basis(Vector3.UP, -a)
	b = b * Basis(Vector3.RIGHT, pitch)
	b = b * Basis(Vector3.BACK, roll)
	ship.global_transform = Transform3D(b, ship.global_position)


func _update_sky() -> void:
	var h := fmod(voyage.hours, 24.0)
	# 6시에 뜨고 18시에 진다
	var elev := sin((h - 6.0) / 12.0 * PI) * 62.0
	var azim := (h / 24.0) * 360.0 - 90.0

	var day := clampf((elev + 6.0) / 22.0, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elev) / 16.0, 0.0, 1.0)

	# 해가 지면 달빛으로 갈아탄다. 위에서 내려오는 약한 빛이라야 밤에도 배가 보인다.
	var lit_elev := elev if elev > 3.0 else 30.0
	_sun.rotation = Vector3(deg_to_rad(-lit_elev), deg_to_rad(azim), 0.0)

	var night_top := Color(0.027, 0.047, 0.094)
	var night_horizon := Color(0.062, 0.086, 0.145)
	var top := night_top.lerp(Color(0.208, 0.408, 0.678), day)
	var horizon := night_horizon.lerp(Color(0.639, 0.757, 0.855), day)
	horizon = horizon.lerp(Color(0.882, 0.545, 0.310), dusk * 0.75)

	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_bottom_color = top.darkened(0.4)
	_sky.ground_horizon_color = horizon.darkened(0.25)
	var moon := Color(0.62, 0.72, 1.0)
	_sun.light_color = moon.lerp(Color(1.0, 0.95, 0.88), day).lerp(Color(1.0, 0.72, 0.48), dusk * 0.8)
	_sun.light_energy = lerpf(0.30, 1.25, day)

	# 밤에는 하늘이 어두워 하늘빛만으로는 아무것도 안 보인다. 바닥을 깔아준다.
	_env.ambient_light_color = Color(0.17, 0.23, 0.36)
	_env.ambient_light_energy = lerpf(0.75, 1.0, day)
	_env.ambient_light_sky_contribution = lerpf(0.18, 0.5, day)

	# 바다의 먼 끝과 안개도 하늘을 따라간다
	ocean.set_sky(horizon, top)
	_env.fog_light_color = horizon

func _update_hud() -> void:
	_surveying.visible = voyage.surveying

	_speedplate.visible = voyage.time_scale > 1.0
	if _speedplate.visible:
		_speedplate.text = "%d배속 — 하루가 %d초" % [
			int(voyage.time_scale), int(round(86400.0 / (Voyage.CLOCK * voyage.time_scale)))]

	_camhint.visible = rig.is_off_center()
	if _camhint.visible:
		var side := "왼쪽" if rig.yaw < 0.0 else "오른쪽"
		_camhint.text = "%s %d° 보는 중 — 가운데 버튼으로 정면" % [side, int(absf(rig.yaw))]

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
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and in_scene:
			if not rig.drag_was_a_turn():
				_steer_towards(mb.position)

	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				voyage.sails = mini(2, voyage.sails + 1)
			KEY_DOWN, KEY_S:
				voyage.sails = maxi(0, voyage.sails - 1)
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
			KEY_BRACKETLEFT:
				voyage.cycle_time_scale(-1)
			KEY_BRACKETRIGHT:
				voyage.cycle_time_scale(1)
			KEY_1:
				voyage.set_time_scale(1.0)
			KEY_2:
				voyage.set_time_scale(4.0)
			KEY_3:
				voyage.set_time_scale(16.0)
			KEY_4:
				voyage.set_time_scale(60.0)

	elif event is InputEventKey and not (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_SPACE:
			voyage.surveying = false

## 화면에서 고른 자리 쪽으로 뱃머리를 돌린다. 고개를 돌려둔 만큼을 더해준다.
func _steer_towards(screen_pos: Vector2) -> void:
	var local := screen_pos - _scene_wrap.get_global_rect().position
	var rel := rig.screen_bearing(local, _scene_wrap.size)
	voyage.heading = fposmod(voyage.heading + rel, 360.0)
