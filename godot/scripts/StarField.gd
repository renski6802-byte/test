class_name StarField
extends Node3D

## 실제 별하늘. 히파르코스 성표의 5.5등급까지 2,617개를 천구에 박는다.
##
## 별자리 목록도, 별자리 선도 없다. 밝은 별이 제자리에 있으면 북두칠성이든
## 오리온이든 저절로 보인다. 실제로 하늘을 볼 때 선이 그려져 있지 않은 것과 같다.
##
## 좌표 변환 하나만 맞으면 나머지는 전부 따라온다. 천구를 위도만큼 기울이고
## 시각만큼 돌리기만 하면, 별이 동에서 떠서 서로 지고 북극성 고도가 위도와
## 같아진다. 남쪽으로 내려가면 북극성이 수평선 아래로 가라앉는 것도 공짜다.

const DATA := "res://data/stars.bin"
const RADIUS := 40000.0          ## 천구의 반지름. 카메라 far(90km) 안쪽이면 된다.

## 등급을 점의 크기로. 화면 900픽셀·화각 52도 기준 반지름 픽셀 수.
const MAG_BRIGHT := -1.5
const MAG_FAINT := 5.5
const PX_BRIGHT := 3.4
const PX_FAINT := 0.85
const FOV_DEG := 52.0
const SCREEN_PX := 900.0

var _mat: ShaderMaterial

## 하루가 항성일(23시간 56분)만큼 돈다. 해보다 조금 빨라서 계절마다
## 밤하늘의 별자리가 바뀐다.
const SIDEREAL := 1.0027379

static func _bv_to_color(bv: float) -> Color:
	# 실제 별빛 색. 리겔은 푸르고 안타레스는 붉다.
	var stops := [
		[-0.35, Color(0.62, 0.74, 1.00)],
		[0.00, Color(0.86, 0.91, 1.00)],
		[0.35, Color(1.00, 0.98, 0.95)],
		[0.80, Color(1.00, 0.90, 0.74)],
		[1.50, Color(1.00, 0.78, 0.58)],
		[2.20, Color(1.00, 0.66, 0.46)],
	]
	if bv <= stops[0][0]:
		return stops[0][1]
	for i in range(stops.size() - 1):
		var a: float = stops[i][0]
		var b: float = stops[i + 1][0]
		if bv <= b:
			return (stops[i][1] as Color).lerp(stops[i + 1][1], (bv - a) / (b - a))
	return stops[-1][1]

func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Sphere"
	mi.mesh = _build()
	mi.custom_aabb = AABB(Vector3.ONE * -RADIUS * 1.2, Vector3.ONE * RADIUS * 2.4)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/stars.gdshader")
	mi.material_override = _mat
	add_child(mi)

func _build() -> ArrayMesh:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_warning("별 자료를 못 찾았다: %s" % DATA)
		return ArrayMesh.new()
	var raw := f.get_buffer(f.get_length())
	f.close()
	if raw.size() < 8 or raw.slice(0, 4).get_string_from_ascii() != "STR1":
		push_warning("별 자료 형식이 다르다")
		return ArrayMesh.new()

	var count := raw.decode_u32(4)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	# 시야각 하나가 화면에서 차지하는 크기 → 천구 위의 길이로
	var px := tan(deg_to_rad(FOV_DEG) * 0.5) * 2.0 / SCREEN_PX

	# 북극성을 천구 북극에 정확히 둔다. 실제로는 0.73도 떨어져 있지만,
	# 그러면 "북극성 고도 = 위도"가 어긋난다. 관측이 이 규칙 위에 서므로
	# 여기서는 규칙을 정확하게 만든다.
	var pole_i := -1
	var pole_dec := -91.0
	for i in count:
		var dec := float(raw.decode_s16(8 + i * 6 + 2)) / 32767.0 * 90.0
		if dec > pole_dec:
			pole_dec = dec
			pole_i = i

	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in count:
		var o := 8 + i * 6
		var ra := float(raw.decode_u16(o)) / 65536.0 * 360.0
		var dec := float(raw.decode_s16(o + 2)) / 32767.0 * 90.0
		var mag := float(raw.decode_u8(o + 4)) / 255.0 * 16.0 - 2.0
		var bv := float(raw.decode_u8(o + 5)) / 255.0 * 4.0 - 0.5
		if i == pole_i:
			dec = 90.0

		# 적도좌표 → 천구 위의 자리. Y 가 천구 북극이다.
		var a := deg_to_rad(ra)
		var d := deg_to_rad(dec)
		var dir := Vector3(cos(d) * cos(a), sin(d), -cos(d) * sin(a))

		var t := clampf((MAG_FAINT - mag) / (MAG_FAINT - MAG_BRIGHT), 0.0, 1.0)
		var size := lerpf(PX_FAINT, PX_BRIGHT, pow(t, 0.7)) * px * RADIUS
		var col := _bv_to_color(bv)
		col.a = lerpf(0.42, 1.0, pow(t, 0.5))

		var base := verts.size()
		for c in corners:
			verts.append(dir * RADIUS)
			uvs.append(c)
			uv2s.append(Vector2(size, float(i) * 0.618))
			cols.append(col)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## 관측자의 자리와 시각에 맞춰 천구를 돌린다.
##
## 두 번 돌리면 끝난다 — 시각만큼 천구를 돌리고(자전), 위도만큼 극을 기울인다.
## 북극성은 그래서 정북 고도 = 위도 자리에 선다.
func orient(hours: float, lat: float, eye: Vector3, night01: float) -> void:
	var lst := fposmod((hours - 12.0) * 15.0 * SIDEREAL, 360.0)
	# 부호 둘이 같이 맞아야 한다. 하나만 뒤집으면 별이 서에서 떠서 동으로 지거나,
	# 방향은 맞는데 남중 시각이 반나절 어긋난다.
	var b := Basis(Vector3.RIGHT, deg_to_rad(lat - 90.0)) \
		* Basis(Vector3.UP, deg_to_rad(-lst - 90.0))
	# 천구는 배를 따라다닌다. 몇십 km 움직여봐야 별은 꿈쩍도 않는다.
	global_transform = Transform3D(b, eye)
	if _mat:
		_mat.set_shader_parameter("night", night01)
