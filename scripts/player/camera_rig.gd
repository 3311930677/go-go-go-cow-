class_name CowCamera
extends Node3D
## 第三人称相机：鼠标旋转视角、滚轮缩放、迟钝的平滑跟随。
## 跟随刻意带一点"廉价滞后"，但不至于眩晕。

const MIN_DIST := 2.5
const MAX_DIST := 12.0
const PITCH_MIN := 0.08   # 近乎平视
const PITCH_MAX := 1.25   # 高俯视
const FOLLOW_LERP := 6.0  # 跟随平滑系数（偏"迟钝"）

var follow_target: Node3D
var yaw := 0.0
var pitch := 0.35
var dist := 6.0
var roll := 0.0  # 相机侧倾（反向重力靴用——更晕)

var _shake := 0.0
var _shake_strength := 0.3

var _cam: Camera3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0  # 略广——廉价感
	add_child(_cam)
	_snap_to_target()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0032
		pitch = clampf(pitch + event.relative.y * 0.0032, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist - 0.6, MIN_DIST, MAX_DIST)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist + 0.6, MIN_DIST, MAX_DIST)


func _process(delta: float) -> void:
	if follow_target == null:
		return
	var target := follow_target.global_position + Vector3(0, 1.3, 0)
	var want := target + _offset()
	# 指数平滑——带点迟钝的"廉价跟随"
	global_position = global_position.lerp(want, 1.0 - exp(-FOLLOW_LERP * delta))
	_cam.look_at(target)
	if _shake > 0.0:
		_shake -= delta
		var m := _shake_strength * maxf(_shake, 0.0)
		_cam.rotation.x += randf_range(-m, m) * 0.4
		_cam.rotation.y += randf_range(-m, m) * 0.4
	if roll != 0.0:
		_cam.rotate_z(roll)  # 视线之后再侧倾——晕的就是你


## 震一下相机（死亡 / 大事件用）：廉价手摇,震完自愈
func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake = duration


## 相机水平前向（单位向量，Y 分量为 0），供角色移动对齐视角
func get_flat_forward() -> Vector3:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return fwd.normalized()


func _offset() -> Vector3:
	# 球坐标：相机始终在目标上方偏后
	return Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * dist


func _snap_to_target() -> void:
	if follow_target == null:
		return
	global_position = follow_target.global_position + Vector3(0, 1.3, 0) + _offset()
