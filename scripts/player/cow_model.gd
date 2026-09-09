class_name CowModel
extends Node3D
## 程序化低多边形小牛——刻意粗糙的"手搓"建模。
## 全部由基础 Mesh 拼装：棱角分明、无贴图、无平滑，脸朝 +Z 方向。
## 动画按固定低帧率"定格"跳变（不插值），复刻僵硬别扭的动作质感。

## 动画帧率：刻意压到 8 FPS，制造"定格动画"式的僵硬感
const ANIM_FPS := 8.0
## 步幅幅度（弧度）
const STEP_AMP := 0.55

## 外观配色（NPC 牛可覆盖为随机鲜艳色，金雕像用金色）
var body_color := Color(0.93, 0.92, 0.88)
var patch_color := Color(0.13, 0.12, 0.11)

var _body: Node3D
var _head: Node3D
var _tail: Node3D
var _legs: Array[Node3D] = []
var _horn_l: MeshInstance3D
var _horn_r: MeshInstance3D
var _horn_level := 0
var _anim_clock := 0.0
## 步态强度：0 静止，1 全速
var gait := 0.0
## 当前姿态：idle / charge / eat
var pose := &"idle"


func _ready() -> void:
	_build()


## 以指定姿势播放（由 PlayerCow 调用）
func set_pose(new_pose: StringName) -> void:
	pose = new_pose


func _build() -> void:
	# —— 材质：纯色、全粗糙、无金属——"廉价刺眼"的质感 ——
	var mat_body := _flat_mat(body_color)
	var mat_patch := _flat_mat(patch_color)
	var mat_horn := _flat_mat(Color(0.86, 0.79, 0.62))
	var mat_pink := _flat_mat(Color(0.95, 0.62, 0.66))
	var mat_eye := _flat_mat(Color(0.05, 0.05, 0.05))

	# —— 身体（白方盒） ——
	_body = Node3D.new()
	_body.name = "BodyRoot"
	add_child(_body)
	_add_box(_body, Vector3(1.1, 0.95, 1.9), mat_body, Vector3(0, 1.15, 0))

	# —— 黑斑：略微凸出表面，避免 Z-fighting（手搓式的"贴片"） ——
	_add_box(_body, Vector3(0.55, 0.5, 0.02), mat_patch, Vector3(0.30, 1.25, 0.55))
	_add_box(_body, Vector3(0.02, 0.45, 0.6), mat_patch, Vector3(-0.56, 1.30, -0.35))
	_add_box(_body, Vector3(0.5, 0.02, 0.45), mat_patch, Vector3(-0.15, 1.63, -0.55))

	# —— 头部组（可低头吃草） ——
	_head = Node3D.new()
	_head.name = "HeadRoot"
	_head.position = Vector3(0, 1.45, 0.95)
	add_child(_head)
	_add_box(_head, Vector3(0.62, 0.62, 0.55), mat_body, Vector3(0, 0.1, 0.15))
	# 鼻口（粉色方块，刻意呆）
	_add_box(_head, Vector3(0.4, 0.28, 0.12), mat_pink, Vector3(0, -0.05, 0.48))
	# 眼睛：纯黑小方块，无高光——毫无神采
	_add_box(_head, Vector3(0.09, 0.11, 0.09), mat_eye, Vector3(0.33, 0.22, 0.28))
	_add_box(_head, Vector3(0.09, 0.11, 0.09), mat_eye, Vector3(-0.33, 0.22, 0.28))
	# 耳朵：侧面薄盒
	_add_box(_head, Vector3(0.22, 0.1, 0.16), mat_body, Vector3(0.4, 0.32, 0.05))
	_add_box(_head, Vector3(0.22, 0.1, 0.16), mat_body, Vector3(-0.4, 0.32, 0.05))
	# 牛角：细棱锥（顶半径为 0 的圆柱）
	_horn_l = _add_cone(_head, mat_horn, Vector3(0.2, 0.55, -0.05), deg_to_rad(-16.0), deg_to_rad(18.0))
	_horn_r = _add_cone(_head, mat_horn, Vector3(-0.2, 0.55, -0.05), deg_to_rad(16.0), deg_to_rad(-18.0))
	_horn_l.visible = false
	_horn_r.visible = false

	# —— 四条腿：枢轴在腿根，便于摆动 ——
	var leg_pos := [
		Vector3(0.38, 0.72, 0.62),   # 前左
		Vector3(-0.38, 0.72, 0.62),  # 前右
		Vector3(0.38, 0.72, -0.62),  # 后左
		Vector3(-0.38, 0.72, -0.62), # 后右
	]
	for i in leg_pos.size():
		var leg := Node3D.new()
		leg.name = "Leg%d" % i
		leg.position = leg_pos[i]
		add_child(leg)
		_add_box(leg, Vector3(0.24, 0.74, 0.28), mat_body, Vector3(0, -0.37, 0))
		# 蹄子（黑）
		_add_box(leg, Vector3(0.26, 0.14, 0.3), mat_patch, Vector3(0, -0.78, 0.02))
		_legs.append(leg)

	# —— 尾巴：细长盒，末端一撮毛 ——
	_tail = Node3D.new()
	_tail.name = "TailRoot"
	_tail.position = Vector3(0, 1.55, -0.95)
	add_child(_tail)
	_add_box(_tail, Vector3(0.09, 0.7, 0.09), mat_body, Vector3(0, -0.35, 0))
	_add_box(_tail, Vector3(0.14, 0.22, 0.14), mat_patch, Vector3(0, -0.78, 0))


## 角等级：0 无角 / 1 初级角 / 2 狂暴角（黑角变大）。升级瞬间 Tween 弹出来——廉价但上头
func set_horn_level(lvl: int) -> void:
	if _horn_l == null or _horn_r == null:
		return
	_horn_level = lvl
	if lvl >= 2:
		var dark := _flat_mat(Color(0.16, 0.13, 0.11))
		_horn_l.material_override = dark
		_horn_r.material_override = dark
		_horn_l.scale = Vector3.ONE
		_horn_r.scale = Vector3.ONE
		_horn_l.visible = true
		_horn_r.visible = true
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_horn_l, "scale", Vector3.ONE * 1.65, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_horn_r, "scale", Vector3.ONE * 1.65, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif lvl >= 1:
		_horn_l.material_override = _flat_mat(Color(0.86, 0.79, 0.62))
		_horn_r.material_override = _flat_mat(Color(0.86, 0.79, 0.62))
		_horn_l.scale = Vector3.ZERO
		_horn_r.scale = Vector3.ZERO
		_horn_l.visible = true
		_horn_r.visible = true
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_horn_l, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_horn_r, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		_horn_l.visible = false
		_horn_r.visible = false
func _process(delta: float) -> void:
	_anim_clock += delta
	# 时间量化到低帧率——所有关节只在这些"定格帧"上跳变，中间不做任何插值
	var t := floorf(_anim_clock * ANIM_FPS) / ANIM_FPS
	var phase := t * ANIM_FPS
	var step := sin(phase * TAU / 8.0) * STEP_AMP * gait

	# 对角步态：0/3 一组，1/2 一组（真实牛的对角步，但以定格方式呈现）
	_legs[0].rotation.x = step
	_legs[3].rotation.x = step
	_legs[1].rotation.x = -step
	_legs[2].rotation.x = -step

	# 身体颠簸：奔跑时上下硬跳
	_body.position.y = 1.15 + absf(sin(phase * TAU / 8.0)) * 0.06 * gait
	# 尾巴：低帧率下的生硬甩动
	_tail.rotation.z = sin(phase * 1.7) * 0.25

	# 姿态覆盖层（无过渡，瞬间切换——僵硬的精髓）
	match pose:
		&"eat":
			_head.rotation.x = 0.85
			_head.position.y = 1.45
		&"charge":
			_head.rotation.x = -0.25
			_head.position.y = 1.3
		_:
			_head.rotation.x = 0.0
			_head.position.y = 1.45 + sin(phase * TAU / 16.0) * 0.02


## 幽灵模式（穿模药水）：全身材质变半透明，像一只不靠谱的幽灵牛
func set_ghost_alpha(on: bool) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		var mat = (mi as MeshInstance3D).material_override
		if mat is StandardMaterial3D:
			var m := mat as StandardMaterial3D
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = 0.4 if on else 1.0


## 快速创建纯色平直材质
func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## 在 parent 下添加一个方盒网格
func _add_box(parent: Node3D, size: Vector3, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## 在 parent 下添加一个棱锥（顶半径 0 的低分段圆柱）
func _add_cone(parent: Node3D, mat: StandardMaterial3D, pos: Vector3, tilt_x: float, tilt_z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.09
	cone.height = 0.38
	cone.radial_segments = 5  # 低分段——棱角分明
	mi.mesh = cone
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(tilt_x, 0, tilt_z)
	parent.add_child(mi)
	return mi
