class_name PlayerCow
extends CharacterBody3D
## 玩家小牛：移动 / 跳跃 / 冲撞 / 吃草 / 飞天BUG / 主动穿模 / 冲撞击飞。
## 刻意保留"廉价手感"：瞬间启停（无加减速）、瞬间转向（无插值）——僵硬即特色。

const SPEED := 6.0            # 常规移动速度（米/秒）
const JUMP_VELOCITY := 5.2    # 跳跃初速度
const CHARGE_SPEED := 16.0    # 冲撞速度
const CHARGE_TIME := 0.32     # 冲撞持续时间
const CHARGE_COOLDOWN := 1.0  # 冲撞冷却
const EAT_DURATION := 1.2     # 吃满一丛草所需时间（按住 E）
const EAT_RADIUS := 1.8       # 可吃到草的判定半径

# —— 飞天 BUG（连跳触发）——
const FLY_TRIGGER_JUMPS := 3      # 触发所需的连跳次数
const FLY_TRIGGER_WINDOW := 1.35  # 连跳判定时间窗（秒）
const FLY_VELOCITY := 16.0        # 飞天初速度（超级弹射）
const FLY_SPIN_SPEED := 9.0       # 空中疯狂自转速度
const FLY_AIR_CONTROL := 8.0      # 飞行中的空气控制速度
const FLY_BOUNCES := 3            # 落地后的弹跳次数

# —— 穿模 ——
const FRAGILE_WALL_LAYER := 4     # "脆弱墙"所在碰撞层（bit 3）

## 冲撞击飞了动态道具（ItemManager 统计获取进度用）
signal charged_prop(body: Node3D)
## 吃到一口草（gained = 士气增量；"拉"炸弹的判定钩子）
signal grass_eaten(gained: int)
signal player_died()

## 外部依赖（由 game.gd 注入）
var camera: CowCamera
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank

var fullness := 0        # 士气（吃饱度改的，决定穿模冷却——依然没什么大用）
var fly_count := 0       # 累计飞天触发次数（Bug 复刻挑战用）
var gravity_scale := 1.0 # 重力倍率（重力异常会调低 / 反向重力靴会调负）

var model: CowModel

var _charge_timer := 0.0
var _charge_cooldown := 0.0
var _charge_dir := Vector3.ZERO
var _eat_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _charge_hitbox: Area3D

# 飞天状态
var _jump_streak := 0
var _last_jump_at := -100.0
var _flying := false
var _fly_bounces := 0

# 幽灵状态（穿模药水）
var _ghost_left := 0.0
var _ghost_on := false
var _tree_pass_cd := 0.0  # P1-A：穿树反馈冷却

# —— P1-B 牛角战斗 ——
var hp := 3
var horn_level := 0          # 0 无角 / 1 初级角 / 2 狂暴角
var horn_shards := 0         # 已吃的发光石笋数
var rage_left := 0.0         # 狂暴角时限（狼骨粉 60 秒）
var golden_horn := false     # 黄金牛角（彩蛋）：局内永久狂暴角
var execution_cd := 0.0      # 处决 CD
var invincible_left := 0.0   # 死亡复活 / 被咬后的无敌窗口
var _dead := false           # 死亡态：不能动，等 game.gd 复活
var _hit_counters := {}      # 处决连击：body instance_id -> {c, t}
# 狼牙免死护符（P1-C）
var wolf_save := false
# 恋爱剧情：正在和心上牛对话（Romance 置位）——E 键留给对话，不吃草
var talk_target_active := false
# 首次下水提示只播一次
var _water_hinted := false


func _ready() -> void:
	# 碰撞体：一只方牛
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.6, 2.0)
	col.shape = shape
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	# 默认能撞上"脆弱墙"层；冲撞时摘掉该层 → 主动穿模
	collision_mask = 1 | FRAGILE_WALL_LAYER

	model = CowModel.new()
	model.name = "Model"
	add_child(model)

	# 冲撞击飞判定区（仅在冲撞期间启用）
	_charge_hitbox = Area3D.new()
	_charge_hitbox.monitoring = false
	var hit_col := CollisionShape3D.new()
	var hit_shape := BoxShape3D.new()
	hit_shape.size = Vector3(1.6, 1.6, 1.8)
	hit_col.shape = hit_shape
	hit_col.position = Vector3(0, 0.9, 1.3)
	_charge_hitbox.add_child(hit_col)
	_charge_hitbox.body_entered.connect(_on_charge_hit)
	add_child(_charge_hitbox)


func _physics_process(delta: float) -> void:
	execution_cd = maxf(0.0, execution_cd - delta)
	rage_left = maxf(0.0, rage_left - delta)
	invincible_left = maxf(0.0, invincible_left - delta)
	if _dead:
		# 死亡态：肉身躺平（还会往下掉），等 game.gd 复活
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return
	if _charge_cooldown > 0.0:
		_charge_cooldown -= delta

	# 幽灵化（穿模药水）：可穿墙 + 半透明（进入在 start_ghost 立即生效）
	if _ghost_left > 0.0:
		_ghost_left -= delta
		if _ghost_left <= 0.0 and _ghost_on:
			_ghost_on = false
			collision_mask = 1 | FRAGILE_WALL_LAYER
			model.set_ghost_alpha(false)
			if hud != null:
				hud.show_message("药劲过了。你又撞得动墙了。", 2.0)
				if _charge_timer <= 0.0:  # P1-A 穿模：药效结束撤豁免（除非正在冲撞）
					_set_fragile_exemptions(false)

	# —— 游泳：水里无重力，浮力把你顶在水面附近，跳跃 = 跃出水面 ——
	if _in_water():
		_update_swimming(delta)
	# 重力（重力异常事件会调低倍率 / 反向重力靴会翻负）
	elif not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	if _charge_timer > 0.0:
		# —— 冲撞中：方向锁定，横冲直撞（此刻可穿模）——
		_charge_timer -= delta
		velocity.x = _charge_dir.x * CHARGE_SPEED
		velocity.z = _charge_dir.z * CHARGE_SPEED
		if _charge_timer <= 0.0:
			_end_charge()
	elif _flying:
		_fly_update(delta)
	else:
		_regular_update()

	# 吃草判定（不与冲撞同时进行）
	_update_eating(delta)

	move_and_slide()

	# 飞天落地：巨大弹跳，弹完才算完
	if _flying and is_on_floor():
		if _fly_bounces > 0:
			velocity.y = 4.0 + 2.5 * _fly_bounces
			_fly_bounces -= 1
			if sfx != null:
				sfx.play("bounce")
			if hud != null:
				hud.show_message("弹跳！", 0.8)
		else:
			_flying = false
			if hud != null:
				hud.show_message("平稳着陆。（并没有）", 2.0)


## 常规移动：瞬间启停、瞬间转向（僵硬手感）
func _regular_update() -> void:
	if _dead or _input_blocked():
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := _camera_flat_dir(input_dir)
	# 水里游得慢（毕竟是牛，不是鱼）
	var spd := SPEED * (0.55 if _in_water() else 1.0)
	if wish.length() > 0.1:
		velocity.x = wish.x * spd
		velocity.z = wish.z * spd
		# 模型瞬间面向移动方向（+Z 为脸方向）
		model.rotation.y = atan2(wish.x, wish.z)
		model.gait = 1.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0

	# 跳跃 + 连跳计数（飞天 BUG 触发检测）
	if Input.is_action_just_pressed("jump") and is_on_floor():
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_jump_at < FLY_TRIGGER_WINDOW:
			_jump_streak += 1
		else:
			_jump_streak = 1
		_last_jump_at = now
		if _jump_streak >= FLY_TRIGGER_JUMPS:
			_start_fly()
		else:
			velocity.y = JUMP_VELOCITY
			if sfx != null:
				sfx.play("jump")

	# 冲撞触发
	if Input.is_action_just_pressed("charge") and _charge_cooldown <= 0.0 and is_on_floor():
		_start_charge()


## 飞行中：空中控制 + 疯狂自转
func _fly_update(delta: float) -> void:
	if _dead or _input_blocked():
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := _camera_flat_dir(input_dir)
	velocity.x = wish.x * FLY_AIR_CONTROL
	velocity.z = wish.z * FLY_AIR_CONTROL
	model.rotation.y += FLY_SPIN_SPEED * delta
	model.gait = 1.0


## 飞天 BUG：连跳三次触发超级弹射
func _start_fly() -> void:
	_flying = true
	fly_count += 1
	_fly_bounces = FLY_BOUNCES
	_jump_streak = 0
	velocity.y = FLY_VELOCITY
	if sfx != null:
		sfx.play("fly")
	if hud != null:
		hud.show_message("牛走飞天！这一定是特性！", 3.0)


## 冲撞：朝当前面向方向猛冲，期间可穿过"脆弱墙"
func _start_charge() -> void:
	_charge_dir = model.global_transform.basis.z  # 模型 +Z 即脸方向
	_charge_timer = CHARGE_TIME
	# 士气越高冷却越短（上限也就 -40%，还是没什么大用）
	_charge_cooldown = CHARGE_TIME + CHARGE_COOLDOWN * (1.0 - fullness / 250.0)
	collision_mask = 1  # 冲撞期间无视"脆弱墙"层 → 主动穿模
	_set_fragile_exemptions(true)  # P1-A：树/石也穿得过
	_charge_hitbox.monitoring = true
	model.set_pose(&"charge")
	if sfx != null:
		sfx.play("charge")
	if hud != null:
		hud.show_message("哞——！！", 0.6)


## 冲撞/幽灵期间豁免"脆弱环境物"（树/石）的碰撞——穿过去但不撞坏世界
func _set_fragile_exemptions(on: bool) -> void:
	for node in get_tree().get_nodes_in_group("fragile_env"):
		if on:
			add_collision_exception_with(node)
		else:
			remove_collision_exception_with(node)


func _is_fragile_env(body: Node) -> bool:
	return body is StaticBody3D and body.is_in_group("fragile_env")


## 穿过一棵树的反馈：树冠抖动（无奈）+ 掉 3 片叶子
func _on_tree_passed(tree: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _tree_pass_cd < 0.6:
		return
	_tree_pass_cd = now
	if tree.is_queued_for_deletion():
		return
	var tw := tree.create_tween()
	tw.tween_property(tree, "rotation:z", 0.16, 0.06)
	tw.tween_property(tree, "rotation:z", -0.12, 0.1)
	tw.tween_property(tree, "rotation:z", 0.0, 0.08)
	_spawn_leaves(tree.global_position + Vector3(0.0, 1.5, 0.0))
	if hud != null:
		hud.show_message("你穿过了树。树的感受不得而知。", 1.2)


## 掉叶子：三片绿色小方块，物理坠落（连叶子都在抗议）
func _spawn_leaves(at: Vector3) -> void:
	for i in 3:
		var leaf := RigidBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.18, 0.05, 0.12)
		col.shape = shape
		leaf.add_child(col)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.7, 0.2)
		mat.roughness = 1.0
		mi.mesh = mesh
		mi.material_override = mat
		leaf.add_child(mi)
		get_parent().add_child(leaf)
		leaf.global_position = at + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.8), randf_range(-0.3, 0.3))
		leaf.apply_central_impulse(Vector3(randf_range(-2.0, 2.0), randf_range(4.0, 7.0), randf_range(-2.0, 2.0)))
		leaf.get_tree().create_timer(randf_range(1.5, 2.5)).timeout.connect(func(): leaf.queue_free())


func _end_charge() -> void:
	# 幽灵化期间不能把墙的碰撞加回来（药效优先）
	collision_mask = 1 if _ghost_on else (1 | FRAGILE_WALL_LAYER)
	if not _ghost_on:  # P1-A：幽灵中先别把豁免撤掉
		_set_fragile_exemptions(false)
	_charge_hitbox.monitoring = false
	_charge_dir = Vector3.ZERO


## 穿模药水：持续秒数内可穿墙、全身半透明（立即生效）
func start_ghost(duration: float) -> void:
	_ghost_left = duration
	if not _ghost_on:
		_ghost_on = true
		collision_mask = 1  # 无视"脆弱墙"层
		if _charge_timer <= 0.0:  # P1-A：冲撞中豁免已生效，不必重复
			_set_fragile_exemptions(true)
		if model != null:
			model.set_ghost_alpha(true)


## 是否在幽灵态（穿模药水）：狼扑空判定用（P1-C）
func is_ghosting() -> bool:
	return _ghost_on


## 冲撞击飞动态物体——物理崩坏的快乐源泉
func _on_charge_hit(body: Node3D) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		var impulse := _charge_dir * 26.0 + Vector3.UP * 9.0
		impulse += Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		rb.apply_central_impulse(impulse)
		rb.apply_torque_impulse(Vector3(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0), randf_range(-20.0, 20.0)))
		if sfx != null:
			sfx.play("moo")
		if hud != null:
			hud.show_message("物理引擎表示强烈抗议。", 1.5)
		charged_prop.emit(body)  # 道具获取统计
	elif body is BoulderBoss:
		# 巨石 BOSS：冲撞命中——它用自己的方式消化伤害（扣"耐心"）
		(body as BoulderBoss).on_player_charged(_charge_dir)
		if sfx != null:
			sfx.play("moo")
		if hud != null:
			hud.show_message("你撞了一块石头。它好像有点不高兴。", 1.5)
	elif body is StaticBody3D and body.get_parent() is ChaosBlackhole:
		# 混沌黑洞：冲撞命中——把它撞碎（黑洞：不讲武德）
		(body.get_parent() as ChaosBlackhole).on_player_charged()
		if sfx != null:
			sfx.play("moo")
		if hud != null:
			hud.show_message("你把头撞进了黑洞。居然没被吸进去。", 1.5)
	elif body.has_method("combat_take_hit"):
		# P1-B 战斗：角打伤害，连击处决（牛/狼/陪练牛走 Combatant 基类）
		_combat_charge_hit(body)
	elif _is_fragile_env(body):
		# P1-A：穿树反馈——树冠抖动 + 掉叶子（物理不拦你，树只会怀疑人生）
		_on_tree_passed(body)


# ————————————————— P1-B 牛角战斗 —————————————————

## 当前有效角等级（狂暴角 / 黄金牛角覆盖初级角）
func effective_horn() -> int:
	if golden_horn or rage_left > 0.0:
		return 2
	return horn_level


func _refresh_horn_visuals() -> void:
	if model != null and model.has_method("set_horn_level"):
		model.set_horn_level(effective_horn())


## 吃发光石笋：长角进度（5 个 → 初级角，角芽弹出）
func gain_horn_shard() -> bool:
	if horn_level >= 1:
		return false
	horn_shards += 1
	if sfx != null:
		sfx.play("horn")
	if horn_shards >= 5:
		horn_level = 1
		_refresh_horn_visuals()
		if hud != null:
			hud.show_message("角芽破土而出！你长角了——现在冲撞能打伤害了。", 3.0)
	return true


## 狂暴角（狼骨粉）：60 秒角等级直接升到 2，到期掉回
func activate_rage(duration: float) -> void:
	rage_left = maxf(rage_left, duration)
	_refresh_horn_visuals()
	if hud != null:
		hud.show_message("角变得又黑又大——狂暴时间到！", 2.5)


## 冲撞命中战斗单位（Combatant 系）：按角等级打伤害（目标自己判正侧面）。
## 连击计数先行：同一目标 5 秒内第 3 次命中 = 处决（代替本次伤害），处决 CD 30 秒。
## 无角（power 0）不算连击——没角还想处决？想得美。
func _combat_charge_hit(target: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var id := target.get_instance_id()
	var rec: Dictionary = _hit_counters.get(id, {})
	if not rec.is_empty() and now - float(rec.get("t", -99.0)) <= 5.0:
		rec["c"] = int(rec.get("c", 0)) + 1
	else:
		rec["c"] = 1
	rec["t"] = now
	_hit_counters[id] = rec
	if effective_horn() > 0 and int(rec["c"]) >= 3 and execution_cd <= 0.0 \
			and target.has_method("combat_execute") and not target.is_dead_combat():
		_execute_combat(target)
		return
	var dealt: int = target.combat_take_hit(self, _charge_dir, effective_horn())
	if dealt <= 0:
		if sfx != null:
			sfx.play("hit")


## 处决：无视血量秒杀 + 马赛克爆炸 + 屏幕大字
func _execute_combat(target: Node3D) -> void:
	execution_cd = 30.0
	target.combat_execute(self)
	if sfx != null:
		sfx.play("exec")
	if hud != null:
		hud.show_message("哞——杀！", 1.2)
	_spawn_exec_particles(target.global_position)


func _spawn_exec_particles(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.15, 0.15)
	mat.roughness = 1.0
	p.mesh = BoxMesh.new()
	p.material_override = mat
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.7
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -13, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	get_parent().add_child(p)
	p.global_position = at
	var tw := get_tree().create_timer(1.5)
	tw.timeout.connect(func(): p.queue_free())


## 被伤害入口（狼咬 / 联机撞击 / 竞技模式）：掉血，掉完就死
func take_combat_hit(dmg: int, by: Node3D) -> void:
	if _dead or invincible_left > 0.0:
		return
	hp = maxi(hp - dmg, 0)
	if hud != null:
		hud.set_hp(hp)
	if sfx != null:
		sfx.play("hit")
	if hp <= 0:
		_die_player(by)


func _die_player(by: Node3D) -> void:
	if _dead:
		return
	if wolf_save:
		# 狼牙免死：免疫 + 回 1 血 + 反震（P1-C）
		wolf_save = false
		hp = 1
		invincible_left = 3.0
		if hud != null:
			hud.set_hp(hp)
			hud.show_message("狼牙发动！替你挡了一死——狼被震晕了！", 3.0)
		if sfx != null:
			sfx.play("horn")
		if by is Wolf:
			(by as Wolf).on_save_rebound()
		return
	_dead = true
	if _charge_timer > 0.0:
		_end_charge()
	if sfx != null:
		sfx.play("death")
	if hud != null:
		hud.set_hp(0)
	player_died.emit()


## 复活（game.gd 调度，梦境模式专用）：满血 + 3 秒无敌
func reset_for_respawn(pos: Vector3) -> void:
	hp = 3
	_dead = false
	invincible_left = 3.0
	velocity = Vector3.ZERO
	global_position = pos
	if camera != null:
		camera.call_deferred("_snap_to_target")
	if hud != null:
		hud.set_hp(hp)
		hud.show_message("你重生了。梦还在继续。（3 秒无敌）", 2.5)
## 输入门控：聊天打字 / 设置菜单打开时（任何控件持有键盘焦点），小牛不动
func _input_blocked() -> bool:
	var vp := get_viewport()
	return vp != null and vp.gui_get_focus_owner() != null


## 是否泡在水里（池塘碗形水坑内且低于水位）
func _in_water() -> bool:
	return terrain != null and terrain.is_in_water(global_position)


## 游泳：浮力把牛顶在水面附近轻轻起伏；跳跃 = 跃出水面
func _update_swimming(delta: float) -> void:
	var depth := terrain.water_depth_at(global_position)
	# 首次下水提示（一场游戏一次）
	if depth > 0.3 and not _water_hinted:
		_water_hinted = true
		if hud != null:
			hud.show_message("你在水里。这水居然是会动的正经水——能游（游得慢），按空格跃出水面。", 4.0)
	# 弹簧浮力：目标浮在水面下 0.35 米处，越深顶得越狠
	var target_y := terrain.water_level - 0.35
	velocity.y += (target_y - global_position.y) * 40.0 * delta
	# 垂直阻尼：水面轻轻起伏，不上蹿下跳
	velocity.y = lerpf(velocity.y, 0.0, clampf(3.0 * delta, 0.0, 0.5))
	# 跳跃 = 跃出水面（够深才触发，避免岸边误跳）
	if depth > 0.5 and Input.is_action_just_pressed("jump"):
		velocity.y = 7.5
		if sfx != null:
			sfx.play("jump")


## 吃草：站定并按住 E，附近有草才能吃（金草 +50）
func _update_eating(delta: float) -> void:
	var stationary := absf(velocity.x) < 0.05 and absf(velocity.z) < 0.05
	if _charge_timer <= 0.0 and not talk_target_active and not _input_blocked() and Input.is_action_pressed("eat") and is_on_floor() and stationary:
		if terrain != null and terrain.has_grass_near(global_position, EAT_RADIUS):
			_eat_timer += delta
			model.set_pose(&"eat")
			if hud != null:
				hud.set_eat_progress(_eat_timer / EAT_DURATION)
			if _eat_timer >= EAT_DURATION:
				var gained := terrain.consume_grass_near(global_position, EAT_RADIUS)
				if gained > 0:
					fullness = mini(fullness + gained, 100)
					if sfx != null:
						sfx.play("eat")
					if hud != null:
						hud.set_eat_progress(-1.0)
						hud.set_fullness(fullness)
						if gained >= 50:
							hud.show_message("金色的草！士气 +50（依然没什么用）", 2.5)
						else:
							hud.show_message("吃了一口草。士气 +10（并没有什么用）", 2.0)
					grass_eaten.emit(gained)  # 1% 概率"拉"出笨笨炸弹的判定钩子
				_eat_timer = 0.0
		else:
			# 荒诞反馈：附近没草
			if _eat_timer == 0.0 and Input.is_action_just_pressed("eat"):
				if hud != null:
					hud.show_message("这里没有草。哞。", 1.5)
			_eat_timer = 0.0
			if hud != null:
				hud.set_eat_progress(-1.0)
			model.set_pose(&"idle")
	else:
		_eat_timer = 0.0
		if hud != null:
			hud.set_eat_progress(-1.0)
		if _charge_timer <= 0.0:
			model.set_pose(&"idle")


## 把输入向量转换为相对相机水平朝向的世界方向
func _camera_flat_dir(input_dir: Vector2) -> Vector3:
	if camera == null:
		return Vector3(input_dir.x, 0, input_dir.y)
	var fwd := camera.get_flat_forward()
	var right := fwd.cross(Vector3.UP).normalized()
	return (fwd * -input_dir.y + right * input_dir.x)