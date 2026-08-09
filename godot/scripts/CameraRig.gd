class_name CameraRig
extends Node3D

## 배를 중심으로 도는 자유 시점.
##
## 좌우 각(yaw)은 뱃머리를 기준으로 한 "상대" 각이다. 그래서 배가 돌면 시점도 같이 따라오고,
## 끌어서 돌린 만큼만 어긋난 채로 유지된다. 원작의 카메라가 이렇게 움직인다.
##
## 위아래(pitch)는 음수까지 간다. 올려다보면 수평선이 화면 아래로 내려가고 하늘이
## 화면을 채운다. 예전에는 아래 한계가 -4도라 수평선이 늘 화면 한가운데 걸려 있었다.

const YAW_LIMIT := 179.0
const PITCH_MIN := -28.0        ## 음수 = 올려다봄
const PITCH_MAX := 70.0        ## 더 올리면 지도처럼 내려다보게 된다
const DIST_MIN := 14.0
const DIST_MAX := 110.0

## 시선이 머무는 높이. 내려다볼 땐 갑판, 올려다볼 땐 돛대 쪽으로 올라간다.
##
## 이게 없으면 올려다보려고 카메라를 내리다가 물속으로 들어간다. 기준점을 위로
## 올리면 카메라는 물 위에 남은 채로 시선만 위를 향한다.
const PIVOT_LOW := 6.0
const PIVOT_HIGH := 20.0
const EYE_CLEARANCE := 2.5      ## 눈이 물에 잠기지 않도록 남기는 높이

## 마우스 한 픽셀당 몇 도를 도는가. 이게 크면 조금만 움직여도 화면이 홱 돈다.
const YAW_PER_PX := 0.15
const PITCH_PER_PX := 0.09

## 시점이 손을 따라오는 빠르기. 낮으면 미끄러지듯 밀리고, 높으면 손에 붙는다.
const FOLLOW := 12.0

## 밖에서 만지는 값은 "가고 싶은 곳"이다. 실제 시점은 이걸 뒤쫓는다.
@export var yaw := 0.0          ## 뱃머리 기준 좌우 각(도)
@export var pitch := 13.0
@export var distance := 68.0

var camera: Camera3D

var _yaw := 0.0
var _pitch := 13.0
var _dist := 68.0

var _dragging := false

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 1.5
	camera.far = 90000.0
	# 62도는 너무 넓어 배가 작아지고 바다가 옆으로 늘어져 보였다
	camera.fov = 52.0
	camera.current = true
	add_child(camera)
	snap()

## 부드럽게 따라가지 않고 지금 당장 맞춘다. 첫 프레임과 화면 촬영에 쓴다.
func snap() -> void:
	_yaw = yaw
	_pitch = pitch
	_dist = distance

## 배의 위치와 침로를 받아 카메라를 놓는다. 배의 흔들림(피치·롤)은 따라가지 않는다 —
## 카메라가 같이 출렁이면 금세 멀미가 난다.
func place(target: Vector3, ship_heading_deg: float, delta := 0.0) -> void:
	# 끄는 대로 딱딱 붙으면 손맛이 없다. 지수적으로 뒤쫓게 한다.
	var k: float = 1.0 - exp(-FOLLOW * delta) if delta > 0.0 else 1.0
	_yaw = lerpf(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, distance, k)

	global_position = target

	# 올려다볼수록 시선 기준점이 돛대 쪽으로 오른다
	var up_look := clampf(-_pitch / absf(PITCH_MIN), 0.0, 1.0)
	var pivot := target + Vector3.UP * lerpf(PIVOT_LOW, PIVOT_HIGH, up_look)

	var a := deg_to_rad(ship_heading_deg + _yaw)
	var p := deg_to_rad(_pitch)

	# 뱃머리 반대쪽으로 물러나 앉는다
	var back := Vector3(-sin(a), 0.0, cos(a))
	var eye := pivot + back * (_dist * cos(p)) + Vector3.UP * (_dist * sin(p))
	# 멀리서 많이 올려다보면 눈이 수면 아래로 내려간다. 거기서 멈춘다.
	# 시선은 위쪽 기준점을 그대로 보므로 구도는 유지된다.
	eye.y = maxf(eye.y, target.y + EYE_CLEARANCE)

	camera.global_position = eye
	camera.look_at(pivot, Vector3.UP)

func recenter() -> void:
	yaw = 0.0
	pitch = 13.0

## 지금 화면에 그려진 좌우 각. 나침반과 조타가 이 값을 기준으로 삼는다.
func view_yaw() -> float:
	return _yaw

func is_off_center() -> bool:
	return absf(_yaw) > 4.0

## 화면의 한 점이 어느 쪽인지 — 뱃머리 기준 상대 방위(도).
## 지금 화면에 그려진 각(_yaw)을 써야 눈에 보이는 대로 조타된다.
func screen_bearing(screen_pos: Vector2, viewport_size: Vector2) -> float:
	var half_fov := deg_to_rad(camera.fov) * 0.5
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	var nx: float = (screen_pos.x / maxf(viewport_size.x, 1.0)) * 2.0 - 1.0
	var off := rad_to_deg(atan(nx * tan(half_fov) * aspect))
	return _yaw + off

func handle_input(event: InputEvent, in_scene: bool) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and in_scene:
			distance = clampf(distance * 0.88, DIST_MIN, DIST_MAX)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and in_scene:
			distance = clampf(distance * 1.14, DIST_MIN, DIST_MAX)
			return true
		# 시점은 오른쪽 버튼이 맡는다. 왼쪽 버튼 하나가 시점과 조타를 겸하면
		# 돌리려던 것이 조타가 되고 조타하려던 것이 시점이 되어 헷갈린다.
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and in_scene:
				_dragging = true
				return true
			elif not mb.pressed:
				_dragging = false
				return true
		if mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			recenter()
			return true

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		# 배를 손으로 돌린다고 생각하면 된다. 왼쪽으로 끌면 배의 오른쪽 면이 돌아온다.
		yaw = clampf(yaw + mm.relative.x * YAW_PER_PX, -YAW_LIMIT, YAW_LIMIT)
		pitch = clampf(pitch + mm.relative.y * PITCH_PER_PX, PITCH_MIN, PITCH_MAX)
		return true

	return false
