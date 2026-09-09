class_name Combatant
extends CharacterBody3D
## 可战斗生物基类：3 格血 + 冲撞击退 + 死亡演出。
## 牛 / 狼 / 陪练牛统一走这里——PlayerCow 的冲撞战斗分支用 has_method("combat_take_hit") 识别。
## 子类约定：
##   - _physics_process 开头接 `if is_knocked(): _knock_step(delta); return` 让击退期间 AI 让位
##   - 需要模式化死亡语义时覆写 combat_die()（记得 super.combat_die() 或自行处理释放）
##   - 相扑陪练牛 setup 里设 combat_enabled = false——它只吃"被撞下台"，不吃血

const KNOCK_TIME := 0.9       # 失魂时间（被撞飞后 AI 靠边站，纯物理）

signal hp_changed(hp: int)
signal combat_defeated(by: Node3D, dir: Vector3)

var hp := 3
var combat_enabled := true    # 关闭 = 不吃"撞伤"（相扑陪练牛专用）
var knock_damper := 1.0

var knock_left := 0.0
var _dead := false
var _hp_pips: Array[MeshInstance3D] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func is_knocked() -> bool:
	return knock_left > 0.0

func is_dead_combat() -> bool:
	return _dead


## 击退帧：基类专用（子类 _physics_process 开头调用后 return）
## 失魂期间只处理重力 + 落地摩擦，让物理自由发挥
func _knock_step(delta: float) -> void:
	knock_left -= delta
	velocity.y -= _gravity * delta
	if is_on_floor() and knock_left <= KNOCK_TIME * 0.4:
		velocity.x *= 0.85
		velocity.z *= 0.85
	move_and_slide()


## 被冲撞命中（PlayerCow 战斗分支调用）。power = 本次有效角伤害（0 纯击退 / 1 / 2）。
## 返回实际造成的伤害——攻击方拿它判连击。侧面/背面伤害减半向下取整。
func combat_take_hit(by: Node3D, dir: Vector3, power: int) -> int:
	if not combat_enabled or _dead:
		return 0
	apply_knockback(dir, power)
	on_knocked()
	if power <= 0:
		return 0
	var dmg := power
	if not _is_face_hit(dir):
		dmg = int(power / 2)
	if dmg <= 0:
		return 0
	hp = maxi(hp - dmg, 0)
	_refresh_pips()
	hp_changed.emit(hp)
	if hp <= 0:
		_die(by)
	return dmg


## 正面判定：攻击方向大致顶到我的脸（牛/狼的模型 +Z 是脸，旋转都在 model 上）
func _is_face_hit(attack_dir: Vector3) -> bool:
	var atk := Vector3(attack_dir.x, 0.0, attack_dir.z)
	if atk.length() <= 0.01:
		return true
	return atk.normalized().dot(-combat_face_dir()) > 0.5


## 我的脸朝向（子类把视觉旋转放在 model 身上，只能问 model）
func combat_face_dir() -> Vector3:
	var m = get("model")
	if m is Node3D:
		return (m as Node3D).global_transform.basis.z.normalized()
	return global_transform.basis.z.normalized()


## 击退：水平冲量 + 按伤害等级上抛，失魂 0.9 秒
func apply_knockback(dir: Vector3, power: int) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() <= 0.01:
		flat = Vector3.BACK
	else:
		flat = flat.normalized()
	velocity.x = flat.x * 13.0 * knock_damper
	velocity.z = flat.z * 13.0 * knock_damper
	velocity.y = 7.0 if power >= 2 else (4.0 if power >= 1 else 0.0)
	knock_left = KNOCK_TIME


## 子类钩子：被撞时的表现
func on_knocked() -> void:
	pass


## 处决（PlayerCow 连击达标后调用）：无视血量秒杀 + 走死亡流程
func combat_execute(by: Node3D) -> void:
	if _dead:
		return
	hp = 0
	_refresh_pips()
	_die(by)


func _die(by: Node3D) -> void:
	if _dead:
		return
	_dead = true
	combat_defeated.emit(by, Vector3.FORWARD)
	combat_die()


## 死亡演出（默认：原地旋转升天，越转越小，"咻"）
## 子类覆写时记得 super.combat_die() 或自行处理释放
func combat_die() -> void:
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", global_position.y + 3.5, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector3.ZERO, 1.1)
	tw.tween_property(self, "rotation:y", rotation.y + TAU * 5.0, 1.1)
	tw.chain().tween_callback(queue_free)


## 头顶 3 颗"爱心"：红色发光小方块，廉价血条（默认字体不保底 Unicode，方块最稳）
func _refresh_pips() -> void:
	if _hp_pips.is_empty():
		_build_pips()
	for i in _hp_pips.size():
		_hp_pips[i].visible = i < hp


func _build_pips() -> void:
	for i in 3:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.16, 0.16, 0.16)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.92, 0.2, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.15, 0.1)
		mat.emission_energy_multiplier = 0.8
		mi.material_override = mat
		mi.position = Vector3((i - 1) * 0.42, 2.65, 0)
		add_child(mi)
		_hp_pips.append(mi)