class_name NpcRoyaleCow
extends Combatant
## 大逃杀陪练牛（P2 战斗接线）：圈内锁敌打架，圈外逃命；圈阶段 >=3 全员狂暴。
## 内讧 40% 概率锁陪练牛——它们自己也会把彼此撞成马赛克。

const WALK_SPEED := 4.6      # 圈外逃命速度
const SEEK_SPEED := 4.2      # 圈内索敌接近速度
const CHARGE_SPEED := 16.0   # 直线冲撞速度
const CHARGE_TIME := 0.55    # 冲撞持续时间
const HIT_RANGE := 2.3       # 撞到判定距离
const RAGE_BOOST := 1.2      # 圈阶段 >=3 全体加速
const RAGE_CD_MUL := 0.5     # 圈阶段 >=3 冲撞 CD 减半

var arena: BattleRoyale
var model: CowModel
var cow_name := "陪练牛"

var out_time := 0.0
var charge_timer := 0.0
var charge_cd := 0.0
var charge_dir := Vector3.ZERO
var _target: Node3D
var _lock_cd := 0.0
var _wander_dir := Vector3.ZERO


func _ready() -> void:
	add_to_group("royale_npcs")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.6, 2.0)
	col.shape = shape
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	model = CowModel.new()
	model.body_color = Color.from_hsv(randf(), 0.55, 0.95)
	model.patch_color = Color.from_hsv(randf(), 0.6, 0.35)
	add_child(model)
	charge_cd = randf_range(2.0, 4.5)


func _physics_process(delta: float) -> void:
	if arena == null or arena.player == null:
		return

	if knock_left > 0.0:
		_knock_step(delta)  # 击退失魂：AI 让位
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var rage := arena.stage >= 3
	var speed_mul := RAGE_BOOST if rage else 1.0

	var dist := Vector2(global_position.x - arena.center.x, global_position.z - arena.center.y).length()
	if dist > arena.radius:
		# 圈外：逃命优先，架都不打了
		out_time += delta
		if out_time > arena.NPC_OUT_TIME:
			arena.on_npc_elim(self)
			return
		var to_center := Vector3(arena.center.x, 0.0, arena.center.y) - global_position
		to_center.y = 0.0
		if to_center.length() > 0.01:
			var dir := to_center.normalized()
			velocity.x = dir.x * WALK_SPEED * speed_mul
			velocity.z = dir.z * WALK_SPEED * speed_mul
			model.rotation.y = atan2(dir.x, dir.z)
			model.gait = 1.0
		move_and_slide()
		return

	charge_cd = maxf(charge_cd - delta, 0.0)
	if charge_timer > 0.0:
		_tick_charge(delta)
		move_and_slide()
		return

	# 圈内：索敌打架
	_lock_cd -= delta
	if _lock_cd <= 0.0:
		_lock_cd = 0.8
		_lock_target()
	if _target_alive():
		var to := _target.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < HIT_RANGE + 0.4 and charge_cd <= 0.0:
			_start_charge(to.normalized() if d > 0.01 else Vector3.BACK)
		elif d > 0.01:
			var dir := to.normalized()
			velocity.x = dir.x * SEEK_SPEED * speed_mul
			velocity.z = dir.z * SEEK_SPEED * speed_mul
			model.rotation.y = atan2(dir.x, dir.z)
			model.gait = 0.8
	else:
		_wander_dir = _wander_dir.rotated(Vector3.UP, randf_range(-0.5, 0.5))
		if _wander_dir.length() < 0.1:
			_wander_dir = Vector3.FORWARD
		velocity.x = _wander_dir.x * SEEK_SPEED * 0.5
		velocity.z = _wander_dir.z * SEEK_SPEED * 0.5
		model.gait = 0.4

	move_and_slide()


## 冲撞：直冲 + 沿途判定（玩家身先士卒，陪练牛随后——肉弹冲击）
func _tick_charge(delta: float) -> void:
	charge_timer -= delta
	velocity.x = charge_dir.x * CHARGE_SPEED
	velocity.z = charge_dir.z * CHARGE_SPEED
	_attempt_hits()
	if charge_timer <= 0.0:
		charge_cd = randf_range(2.5, 5.0) * (RAGE_CD_MUL if arena.stage >= 3 else 1.0)


func _attempt_hits() -> void:
	var player := arena.player
	if player != null and not player._dead and global_position.distance_to(player.global_position) < HIT_RANGE:
		arena.on_npc_hits_player(self)
		if charge_timer <= 0.0:
			return
	for n in get_tree().get_nodes_in_group("royale_npcs"):
		var other := n as NpcRoyaleCow
		if other == null or other == self or other.is_dead_combat():
			continue
		if global_position.distance_to(other.global_position) < HIT_RANGE:
			other.combat_take_hit(self, charge_dir, 1)  # 陪练牛没角：固定 1 血


## 锁定目标：60% 玩家 / 40% 最近陪练牛（它们内讧，玩家看戏）
func _lock_target() -> void:
	var player := arena.player
	if player != null and not player._dead and randf() < 0.6:
		_target = player
		return
	_target = _pick_npc_target()
	if _target == null and player != null and not player._dead:
		_target = player


func _pick_npc_target() -> NpcRoyaleCow:
	var best: NpcRoyaleCow = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("royale_npcs"):
		var other := n as NpcRoyaleCow
		if other == null or other == self or other.is_dead_combat():
			continue
		var d := global_position.distance_to(other.global_position)
		if d < 70.0 and d < bd:
			best = other
			bd = d
	return best


func _target_alive() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if _target == arena.player:
		return not arena.player._dead
	if _target.has_method("is_dead_combat"):
		return not _target.is_dead_combat()
	return true


func _start_charge(dir: Vector3) -> void:
	charge_timer = CHARGE_TIME
	charge_dir = dir
	model.gait = 1.0


## 被冲撞杀死（玩家或陪练牛所致）→ 按出局处理
func combat_die() -> void:
	if arena != null:
		arena.on_npc_elim(self)
	else:
		super.combat_die()
