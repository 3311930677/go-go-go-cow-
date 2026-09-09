class_name NetPlayer
extends Node3D
## 远程玩家：其他客户端的小牛在网络另一端的化身。
## 位置插值（低频网络包也能看出"僵硬顺滑"的魔性移动）+ 头顶名字牌。

var peer_id := 0
var player_name := ""

var _model: CowModel
var _label: Label3D
var _target_pos := Vector3.ZERO
var _target_ry := 0.0
var _act := "idle"
var _clock := 0.0


func _ready() -> void:
	_model = CowModel.new()
	# 联机牛：每头一个随机鲜艳配色（一眼分清谁是谁）
	_model.body_color = Color.from_hsv(randf(), 0.45, 0.95)
	_model.patch_color = Color.from_hsv(randf(), 0.5, 0.35)
	add_child(_model)

	_label = Label3D.new()
	_label.text = player_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.02
	_label.outline_size = 6
	_label.modulate = Color(1, 1, 1, 0.85)
	_label.position = Vector3(0, 2.3, 0)
	_label.font_size = 48
	add_child(_label)


## 由 NetManager 每次快照调用
func update_state(pos: Vector3, ry: float, act: String) -> void:
	_target_pos = pos
	_target_ry = ry
	_act = act


## 更新名字牌（快照中名字从占位符更新为真实名字时调用）
func update_name() -> void:
	_label.text = player_name


func _process(delta: float) -> void:
	_clock += delta
	# 插值：网络 15Hz → 显示 60Hz，指数平滑（故意偏"糊"，僵硬顺滑）
	global_position = global_position.lerp(_target_pos, 1.0 - exp(-12.0 * delta))
	_model.rotation.y = lerp_angle(_model.rotation.y, _target_ry, 1.0 - exp(-12.0 * delta))

	match _act:
		"fly":
			_model.rotation.y += 9.0 * delta  # 远程牛也在天上疯狂自转
			_model.gait = 1.0
			_model.set_pose(&"idle")
		"run":
			_model.gait = 1.0
			_model.set_pose(&"idle")
		"charge":
			_model.gait = 0.0
			_model.set_pose(&"charge")
		"eat":
			_model.gait = 0.0
			_model.set_pose(&"eat")
		_:
			_model.gait = 0.0
			_model.set_pose(&"idle")
