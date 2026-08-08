class_name CameraRig
extends Node3D

## 배를 중심으로 도는 자유 시점.
##
## 좌우 각(yaw)은 뱃머리를 기준으로 한 "상대" 각이다. 그래서 배가 돌면 시점도 같이 따라오고,
## 끌어서 돌린 만큼만 어긋난 채로 유지된다. 원작의 카메라가 이렇게 움직인다.

const YAW_LIMIT := 179.0
const PITCH_MIN := -4.0
const PITCH_MAX := 72.0
const DIST_MIN := 22.0
const DIST_MAX := 520.0

@export var yaw := 0.0        ## 뱃머리 기준 좌우 각(도)
@export var pitch := 13.0
@export var distance := 68.0

var camera: Camera3D

var _dragging := false
var _drag_travel := 0.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 1.5
	camera.far = 90000.0
	camera.fov = 62.0
	camera.current = true
	add_child(camera)

## 배의 위치와 침로를 받아 카메라를 놓는다. 배의 흔들림(피치·롤)은 따라가지 않는다 —
## 카메라가 같이 출렁이면 금세 멀미가 난다.
func place(target: Vector3, ship_heading_deg: float) -> void:
	global_position = target
	var a := deg_to_rad(ship_heading_deg + yaw)
	var p := deg_to_rad(pitch)

	# 뱃머리 반대쪽으로 물러나 앉는다
	var back := Vector3(-sin(a), 0.0, cos(a))
	var eye := target + back * (distance * cos(p)) + Vector3.UP * (distance * sin(p) + 6.0)
	camera.global_position = eye
	camera.look_at(target + Vector3.UP * 6.0, Vector3.UP)

func recenter() -> void:
	yaw = 0.0

func is_off_center() -> bool:
	return absf(yaw) > 4.0

## 화면의 한 점이 어느 쪽인지 — 뱃머리 기준 상대 방위(도)
func screen_bearing(screen_pos: Vector2, viewport_size: Vector2) -> float:
	var half_fov := deg_to_rad(camera.fov) * 0.5
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	var nx: float = (screen_pos.x / maxf(viewport_size.x, 1.0)) * 2.0 - 1.0
	var off := rad_to_deg(atan(nx * tan(half_fov) * aspect))
	return yaw + off

func handle_input(event: InputEvent, in_scene: bool) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and in_scene:
			distance = clampf(distance * 0.88, DIST_MIN, DIST_MAX)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and in_scene:
			distance = clampf(distance * 1.14, DIST_MIN, DIST_MAX)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and in_scene:
				_dragging = true
				_drag_travel = 0.0
			elif not mb.pressed:
				var was := _dragging and _drag_travel > 6.0
				_dragging = false
				return was      # 끌었으면 조타로 넘기지 않는다
		if mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			recenter()
			return true

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_travel += mm.relative.length()
		yaw = clampf(yaw - mm.relative.x * 0.26, -YAW_LIMIT, YAW_LIMIT)
		pitch = clampf(pitch + mm.relative.y * 0.16, PITCH_MIN, PITCH_MAX)
		return true

	return false

func drag_was_a_turn() -> bool:
	return _drag_travel > 6.0
