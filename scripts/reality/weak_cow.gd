class_name WeakCow
extends CharacterBody3D
## 现实模式的孱弱小牛：移动极慢、永远站不稳（摇晃+踉跄）、
## 跳跃/冲撞被腿拒绝——与梦境里飞天穿墙的小牛形成反差彩蛋。
## 走到奶盆旁按 E 触发结局。

const SPEED := 1.2               # 慢到令人发指
const DRINK_RADIUS := 2.6        # 奶盆交互半径
const STUMBLE_MIN := 3.0         # 踉跄最小间隔
const STUMBLE_MAX := 7.0

var hud: GameHUD
var sfx: SfxBank
var milk_pos: Vector3            # 奶盆位置（由 Barn 注入）
var ending := false              # 是否已触发结局

var model: CowModel
var _clock := 0.0
var _stumble_timer := 4.0
var _stumble_tilt := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.2, 1.5)
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)

	model = CowModel.new()
	model.name = "Model"
	model.scale = Vector3(0.72, 0.72, 0.72)  # 比梦里的自己小一圈
	add_child(model)


func _physics_process(delta: float) -> void:
	_clock += delta

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if ending:
		# 结局后：躺平不动
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0
		move_and_slide()
		return

	# —— 移动：极慢 ——
	var input_dir := Vector2.ZERO
	if get_viewport().gui_get_focus_owner() == null:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Vector3(input_dir.x, 0, input_dir.y)  # 现实不看相机（牛棚小，固定方位足够"复古"）
	if wish.length() > 0.1:
		velocity.x = wish.x * SPEED
		velocity.z = wish.z * SPEED
		model.rotation.y = atan2(wish.x, wish.z)
		model.gait = 1.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0

	# —— 拒绝跳跃 ——
	if Input.is_action_just_pressed("jump"):
		if sfx != null:
			sfx.play("stumble")
		if hud != null:
			hud.show_message("你试图跳跃。孱弱的腿拒绝了。（梦里你能飞天。）", 3.0)

	# —— 拒绝冲撞 ——
	if Input.is_action_just_pressed("charge"):
		if sfx != null:
			sfx.play("stumble")
		if hud != null:
			hud.show_message("冲撞？你现在连站都站不稳。", 3.0)

	# —— 吃奶结局 ——
	if Input.is_action_just_pressed("eat"):
		if Vector2(global_position.x - milk_pos.x, global_position.z - milk_pos.z).length() < DRINK_RADIUS:
			_trigger_ending()

	# —— 站不稳：正弦摇摆 + 随机踉跄（定格跳变） ——
	_stumble_timer -= delta
	if _stumble_timer <= 0.0:
		_stumble_timer = randf_range(STUMBLE_MIN, STUMBLE_MAX)
		_stumble_tilt = randf_range(-0.28, 0.28)  # 突然歪一下
	_stumble_tilt = move_toward(_stumble_tilt, 0.0, delta * 0.35)
	var t := floorf(_clock * 8.0) / 8.0  # 8FPS 定格
	model.rotation.z = sin(t * TAU * 0.9) * 0.07 + _stumble_tilt

	move_and_slide()


func _trigger_ending() -> void:
	ending = true
	model.rotation.x = 0.55  # 满足地躺倒
	if sfx != null:
		sfx.play("moo")
	if hud != null:
		hud.show_message("（你喝到了奶。梦醒了。）", 6.0)
		hud.set_task("【现实·结局】原来这一切，只是小牛吃奶时做的一个梦。\n按 R 重回梦境（你确定？）。")
