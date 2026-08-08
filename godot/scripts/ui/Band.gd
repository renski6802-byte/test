class_name BandView
extends Control

## 화면 아래 띠. 슬롯 넷의 뼈대는 장면이 바뀌어도 그대로다 —
## 초상화 · 대사 · 문맥 · 지도. 지금은 항해 장면이라 문맥 자리에 바람과 침로가 있고,
## 도시를 만들면 같은 자리에 소지금과 날짜가 들어간다.

signal asked
signal chart_toggled
signal port_entered
signal survey_held(down: bool)

const MAX_NOTES := 4

var portrait: PortraitView
var compass: CompassView
var minimap: MinimapView

var _say_who: Label
var _say_text: Label
var _notes_box: VBoxContainer
var _wind: Label
var _speed: Label
var _btn_ask: Button
var _btn_chart: Button
var _btn_survey: Button
var _btn_enter: Button

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Pal.BAND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var rule := ColorRect.new()
	rule.color = Pal.BAND_RULE
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 2
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	row.add_child(_slot_portrait())
	row.add_child(_divider())
	row.add_child(_slot_talk())
	row.add_child(_divider())
	row.add_child(_slot_context())
	row.add_child(_divider())
	row.add_child(_slot_map())

func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Pal.BAND_RULE
	d.custom_minimum_size = Vector2(1, 0)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return d

func _slot_portrait() -> Control:
	portrait = PortraitView.new()
	portrait.custom_minimum_size = Vector2(104, 0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return portrait

func _slot_talk() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	_pad(box, 10, 8)

	var say_row := HBoxContainer.new()
	say_row.add_theme_constant_override("separation", 8)
	_say_who = _label("주앙", 12, Pal.BRASS)
	_say_text = _label("돛을 올렸습니다. 어디로 갈지 물어보십시오.", 15, Pal.BAND_INK)
	_say_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	say_row.add_child(_say_who)
	say_row.add_child(_say_text)
	box.add_child(say_row)

	_notes_box = VBoxContainer.new()
	_notes_box.add_theme_constant_override("separation", 1)
	_notes_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_notes_box)

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	_btn_ask = _button("묻기  Q")
	_btn_chart = _button("해도  M")
	_btn_survey = _button("측량  Space")
	_btn_enter = _button("입항  E")
	_btn_enter.disabled = true
	acts.add_child(_btn_ask)
	acts.add_child(_btn_chart)
	acts.add_child(_btn_survey)
	acts.add_child(_btn_enter)
	box.add_child(acts)

	_btn_ask.pressed.connect(func(): asked.emit())
	_btn_chart.pressed.connect(func(): chart_toggled.emit())
	_btn_enter.pressed.connect(func(): port_entered.emit())
	_btn_survey.button_down.connect(func(): survey_held.emit(true))
	_btn_survey.button_up.connect(func(): survey_held.emit(false))
	return box

func _slot_context() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(132, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	_pad(box, 8, 6)

	compass = CompassView.new()
	compass.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(compass)

	_wind = _label("바람 —", 12, Pal.BAND_SOFT)
	_wind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed = _label("— 노트 · —", 11, Pal.BAND_SOFT)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_wind)
	box.add_child(_speed)
	return box

func _slot_map() -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 7)
	wrap.add_theme_constant_override("margin_right", 7)
	wrap.add_theme_constant_override("margin_top", 7)
	wrap.add_theme_constant_override("margin_bottom", 7)
	minimap = MinimapView.new()
	minimap.custom_minimum_size = Vector2(126, 0)
	wrap.add_child(minimap)
	return wrap

# ── 바깥에서 부르는 것들 ─────────────────────────────────────────
func set_say(who: String, text: String) -> void:
	_say_who.text = who
	_say_text.text = text
	portrait.who = who

func add_note(text: String, kind: String) -> void:
	var col := Pal.BAND_SOFT
	if kind == "hi":
		col = Pal.BRASS
	elif kind == "warn":
		col = Pal.VERMILION
	var l := _label(text, 12, col)
	_notes_box.add_child(l)
	while _notes_box.get_child_count() > MAX_NOTES:
		var old := _notes_box.get_child(0)
		_notes_box.remove_child(old)
		old.queue_free()

func refresh(v: Voyage) -> void:
	compass.set_state(v.heading, v.wind_brg)
	_wind.text = "바람 %s" % v.wind_label()
	_speed.text = "%.1f노트 · %s" % [v.speed_knots(), v.clock()]
	minimap.queue_redraw()

	var near_ok := v.near_port != null
	_btn_enter.disabled = not near_ok
	_btn_survey.button_pressed = v.surveying

# ── 잔손질 ──────────────────────────────────────────────────────
func _label(text: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.clip_text = true
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	return b

func _pad(c: Control, h: int, v: int) -> void:
	c.add_theme_constant_override("margin_left", h)
	c.add_theme_constant_override("margin_right", h)
	c.add_theme_constant_override("margin_top", v)
	c.add_theme_constant_override("margin_bottom", v)
