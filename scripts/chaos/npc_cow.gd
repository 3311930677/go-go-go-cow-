class_name NpcCow
extends Combatant
## 牛群迁徙 NPC：行为刻意充满 Bug——原地转圈 / 落地就弹的飞天牛 / 半埋地下。
## 配色随机鲜艳——"抽象"浓度拉满。

const SPEED := 8.0

var run_dir := Vector3.ZERO
## 0 正常狂奔 / 1 原地转圈 / 2 无限弹跳飞天 / 3 半埋地下
var bug_mode := 0

var model: CowModel
var _life := 0.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.6, 2.0)
	col.shape = shape
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	model = CowModel.new()
	# 荒诞配色：随机鲜艳色
	model.body_color = Color.from_hsv(randf(), 0.5, 0.95)
	model.patch_color = Color.from_hsv(randf(), 0.6, 0.35)
	add_child(model)  # 触发 _build，使用随机配色
	add_to_group("npcs")  # P1-C 狼群索敌目标池（路过牛群优先被咬）


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > 30.0:
		queue_free()  # 跑得够远了——功成身退
		return

	if knock_left > 0.0:
		_knock_step(delta)  # P1-B 击退失魂：AI 让位给物理
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	match bug_mode:
		1:  # 原地疯狂转圈（腿在跑，牛没动）
			velocity.x = 0.0
			velocity.z = 0.0
			model.rotation.y += 7.0 * delta
			model.gait = 1.0
		2:  # 落地就弹的飞天牛
			if is_on_floor():
				velocity.y = 13.0
			velocity.x = run_dir.x * SPEED
			velocity.z = run_dir.z * SPEED
			model.rotation.y = atan2(run_dir.x, run_dir.z)
			model.gait = 1.0
		3:  # 半埋地下，一动不动
			velocity = Vector3.ZERO
			model.gait = 0.0
		_:  # 正常狂奔
			velocity.x = run_dir.x * SPEED
			velocity.z = run_dir.z * SPEED
			model.rotation.y = atan2(run_dir.x, run_dir.z)
			model.gait = 1.0

	move_and_slide()
