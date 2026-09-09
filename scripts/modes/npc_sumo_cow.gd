class_name NpcSumoCow
extends Combatant
## 相扑陪练牛（P2 增强）：慢吞吞逼近玩家，偶尔发狂冲撞。
## 流派：莽撞（冲撞 CD 短 40%，冲过头容易自己冲出擂台）/ 守边（赖在台边钓鱼执法，玩家冲撞时侧身让位）。
## 对撞：双方同时冲撞 → 互弹（后出手者多退 30%——拼时机不拼数值）。

const WALK_SPEED := 3.2
const CHARGE_SPEED := 15.0
const OVERSHOOT_TIME := 0.35   # 莽撞型冲完再冲 0.35 秒——很容易冲出台

var arena: SumoArena
var model: CowModel

var style := "edge"          # "charge" 莽撞 / "edge" 守边
var fell_reason := "knock"   # knock 撞飞 / bounce 对撞 / overshoot 冲过头 / edge 骗下台
var respawn_timer := 0.0
var knocked_timer := 0.0
var charge_timer := 0.0
var charge_cd := 2.5
var charge_dir := Vector3.ZERO
var _charged_at := 0.0       # 本次冲撞已用时（对撞判定后手用）
var _overshoot_t := 0.0
var _edge_angle := 0.0


func _ready() -> void:
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
	style = "charge" if randf() < 0.5 else "edge"
	charge_cd = randf_range(1.5, 3.5) * (0.6 if style == "charge" else 1.0)
	_edge_angle = randf_range(0.0, TAU)
	combat_enabled = false  # 相扑只吃"被撞下台"，不吃血


func _physics_process(delta: float) -> void:
	if arena == null or arena.player == null:
		return

	# 重生等待：隐身冻结
	if respawn_timer > 0.0:
		respawn_timer -= delta
		velocity = Vector3.ZERO
		if respawn_timer <= 0.0:
			global_position = arena.respawn_point()
			visible = true
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	# 被撞飞中：不受控，疯狂自转
	if knocked_timer > 0.0:
		knocked_timer -= delta
		model.rotation.y += 12.0 * delta
		model.gait = 1.0
		move_and_slide()
		_check_fell()
		return

	# 莽撞型：冲完再冲一段（冲过头）
	if _overshoot_t > 0.0:
		_overshoot_t -= delta
		velocity.x = charge_dir.x * CHARGE_SPEED
		velocity.z = charge_dir.z * CHARGE_SPEED
		model.rotation.y = atan2(charge_dir.x, charge_dir.z)
		model.gait = 1.0
		move_and_slide()
		_check_fell()
		return

	var to_player := arena.player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# 玩家冲撞命中我 → 被撞飞（玩家有角会更疼一点……可惜相扑不吃血）
	if arena.player._charge_timer > 0.0 and dist < 2.3:
		fell_reason = "knock"
		var kdir := to_player.normalized() if dist > 0.01 else Vector3.BACK
		velocity = kdir * 17.0 + Vector3.UP * 8.0
		knocked_timer = 1.2
		arena.on_npc_knocked(self)
		move_and_slide()
		_check_fell()
		return

	if charge_timer > 0.0:
		charge_timer -= delta
		_charged_at += delta
		velocity.x = charge_dir.x * CHARGE_SPEED
		velocity.z = charge_dir.z * CHARGE_SPEED
		model.rotation.y = atan2(charge_dir.x, charge_dir.z)
		model.gait = 1.0
		# 撞到玩家（或对撞）
		if dist < 2.0:
			if arena.player_knock_ok():
				if arena.player._charge_timer > 0.0:
					arena.on_mutual_charge(self)   # 对撞互弹：拼时机
				else:
					arena.on_player_knocked(self)
			charge_timer = 0.0
			if style == "charge":
				_overshoot_t = OVERSHOOT_TIME  # 莽撞：停下来之前再冲一会儿
	elif style == "edge":
		_tick_edge_style(dist, to_player, delta)
	else:
		_tick_charge_style(dist, to_player, delta)


func _tick_charge_style(dist: float, to_player: Vector3, delta: float) -> void:
	charge_cd -= delta
	if dist > 2.2:
		var wdir := to_player.normalized()
		velocity.x = wdir.x * WALK_SPEED
		velocity.z = wdir.z * WALK_SPEED
		model.rotation.y = atan2(wdir.x, wdir.z)
		model.gait = 0.8
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0
	if charge_cd <= 0.0 and dist < 10.0:
		_start_charge(to_player.normalized() if dist > 0.01 else Vector3.BACK)


## 守边型：赖在台边旋转徘徊；玩家冲过来就侧身让位（骗你自己冲出台）
func _tick_edge_style(dist: float, to_player: Vector3, delta: float) -> void:
	charge_cd -= delta
	var player := arena.player
	var player_charging := player._charge_timer > 0.0
	var rim := SumoArena.PLATFORM_RADIUS - 2.5
	var from_center := Vector3(global_position.x - SumoArena.ARENA_CENTER.x, 0.0, global_position.z - SumoArena.ARENA_CENTER.z)
	var rc := from_center.length()
	var walk_dir := Vector3.ZERO
	if player_charging and dist < 6.0:
		# 侧身让位：垂直于玩家冲撞方向的切向移动
		walk_dir = Vector3(-to_player.z, 0.0, to_player.x).normalized()
		if walk_dir.dot(from_center.normalized() if rc > 0.1 else Vector3.RIGHT) > 0.0:
			walk_dir = -walk_dir
		model.gait = 1.0
	elif rc > rim + 0.6 or rc < rim - 0.6:
		_edge_angle = atan2(from_center.z, from_center.x)
		walk_dir = -from_center.normalized() if rc > rim else from_center.normalized()
	elif charge_cd <= 0.0 and dist < 8.0:
		_start_charge(to_player.normalized() if dist > 0.01 else Vector3.BACK)
		return
	velocity.x = walk_dir.x * WALK_SPEED * 1.3
	velocity.z = walk_dir.z * WALK_SPEED * 1.3
	if walk_dir.length() > 0.05:
		model.rotation.y = atan2(walk_dir.x, walk_dir.z)
	model.gait = 0.7


func _start_charge(dir: Vector3) -> void:
	charge_timer = 0.55
	_charged_at = 0.0
	charge_dir = dir
	charge_cd = randf_range(2.5, 4.5) * (0.6 if style == "charge" else 1.0)
	if arena.sfx != null:
		arena.sfx.play("charge")


func _check_fell() -> void:
	if global_position.y < SumoArena.ELIM_Y:
		arena.on_npc_fell(self)


## 对撞反弹落到地上时自动抹掉"bounce"标记（出局播报用一次就够）
func clear_fell_reason() -> void:
	fell_reason = "knock"
