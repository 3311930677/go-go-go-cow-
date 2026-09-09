class_name Wolf
extends Combatant
## 抽象狼（P1-C）：走路瞬移、飞扑咬人、被撞晕。核心气质是"卡了"。
## 存活守则（荒诞）：狼 = 超低多边形灰盒子 + 歪嘴；行为 = 全是 Bug（瞬移、卡地、转圈）。

const SPEED := 7.0              # 追击速度
const POUNCE_SPEED := 18.0      # 飞扑速度
const POUNCE_TIME := 1.2        # 飞扑持续（秒）
const POUNCE_CD := 2.5          # 两次扑咬间隔
const TELEGRAPH_TIME := 0.8     # 前摇：原地抽搐
const TELEPORT_EVERY := 2.0     # 每 2 秒瞬移 0.5 米（"卡了"的表现）
const TELEPORT_STEP := 0.5
const KNOCK_TO_STUN := 5        # 被撞退 5 次 → 晕 10 秒
const STUN_TIME := 10.0
const STUCK_TIME := 3.0         # 卡进地里 3 秒后"咻"消失
const BITE_RANGE := 1.4         # 扑中判定距离
const LIFETIME := 90.0          # 实在杀不死的狼自己"咻"走
const TELEGRAPH_DIST := 5.0     # 进入前摇的距离

## 外部依赖（ChaosManager 注入）
var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank

## 死亡/失踪通知（ChaosManager 接：数掉落、清群、播报）
signal wolf_despawned(wolf: Node3D, at: Vector3, was_kill: bool)

var model: Node3D
var wolf_name := "狼"
var pacified_left := 0.0   # 狼皮：狼只绕圈不咬

var _state := "wander"     # wander / telegraph / pounce / stun / stuck / gone
var _state_t := 0.0
var _target: Node3D
var _pounce_dir := Vector3.ZERO
var _pounce_cd := 2.0
var _tele_t := 0.0
var _repick := 0.0
var _knocks := 0
var _bit := false
var _ghosted_pounce := false
var _life := 0.0
var _wander_dir := Vector3.FORWARD


func _ready() -> void:
	add_to_group("wolves")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.1, 1.7)
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)
	model = _build_model()
	add_child(model)
	_wander_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		_despawn(false)
		return
	if _state == "gone":
		return
	_pounce_cd = maxf(_pounce_cd - delta, 0.0)
	if pacified_left > 0.0:
		pacified_left -= delta
	# 击退失魂：AI 让位给物理（Combatant 约定）
	if knock_left > 0.0:
		_knock_step(delta)
		return
	if not is_on_floor() and _state != "stuck":
		velocity.y -= _gravity * delta
	match _state:
		"wander":
			_tick_wander(delta)
		"telegraph":
			_tick_telegraph(delta)
		"pounce":
			_tick_pounce(delta)
		"stun":
			_tick_stun(delta)
		"stuck":
			_tick_stuck(delta)
	move_and_slide()
	if global_position.y < -60.0:
		_despawn(false)


func _tick_wander(delta: float) -> void:
	_repick -= delta
	if _repick <= 0.0:
		_repick = 0.6
		_pick_target()
	# 狼皮生效：绕着玩家转圈，激烈但人畜无害
	if pacified_left > 0.0 and player != null:
		_circle_player()
		return
	if _target == null or not is_instance_valid(_target):
		_wander_dir = _wander_dir.rotated(Vector3.UP, randf_range(-0.6, 0.6))
		_walk(_wander_dir)
		return
	# 每 2 秒"瞬移" 0.5 米——位置突跳，没有过渡动画（就是要卡的感觉）
	_tele_t += delta
	if _tele_t >= TELEPORT_EVERY:
		_tele_t = 0.0
		var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * TELEPORT_STEP
		global_position += off
		if terrain != null:
			global_position.y = terrain.height_at(global_position.x, global_position.z) + 0.9
	var to := _target.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	_face(flat)
	if dist < TELEGRAPH_DIST and _pounce_cd <= 0.0:
		_state = "telegraph"
		_state_t = 0.0
		_pounce_dir = flat.normalized()
		return
	_walk(flat.normalized())


## 前摇：原地抽搐（身体快速小幅抖动），蓄力 0.8 秒
func _tick_telegraph(delta: float) -> void:
	if _state_t < delta and sfx != null:
		sfx.play("wolf")
	_state_t += delta
	velocity.x = 0.0
	velocity.z = 0.0
	model.rotation.z = sin(_state_t * 40.0) * 0.09
	model.position.y = absf(sin(_state_t * 28.0)) * 0.06
	if _state_t >= TELEGRAPH_TIME:
		model.rotation.z = 0.0
		model.position.y = 0.0
		_state = "pounce"
		_state_t = 0.0
		_bit = false
		var tgt: Node3D = _target if (_target != null and is_instance_valid(_target)) else player
		var to := tgt.global_position - global_position
		_pounce_dir = Vector3(to.x, 0.0, to.z).normalized()
		# 玩家幽灵/穿模中：扑空 → 判定卡地（P1-A 联动）
		_ghosted_pounce = player != null and player.is_ghosting()
		if _ghosted_pounce and player != null:
			add_collision_exception_with(player)
		velocity.x = _pounce_dir.x * POUNCE_SPEED
		velocity.z = _pounce_dir.z * POUNCE_SPEED
		velocity.y = 4.0


## 飞扑：直冲 + 沿途咬人。扑完没咬到（且当时玩家在穿模）→ 卡进地里
func _tick_pounce(delta: float) -> void:
	_state_t += delta
	velocity.x = _pounce_dir.x * POUNCE_SPEED
	velocity.z = _pounce_dir.z * POUNCE_SPEED
	if not _bit and _state_t < POUNCE_TIME - 0.05:
		if player != null and _try_bite_player():
			_bit = true
		else:
			for cow in get_tree().get_nodes_in_group("npcs"):
				if cow is NpcCow and not cow.is_dead_combat() \
						and (cow as Node3D).global_position.distance_to(global_position) < BITE_RANGE:
					_bite_npc(cow as NpcCow)
					_bit = true
					break
	if _state_t >= POUNCE_TIME:
		_pounce_cd = POUNCE_CD
		if player != null:
			remove_collision_exception_with(player)
		if not _bit and _ghosted_pounce:
			_state = "stuck"
			_state_t = 0.0
			velocity = Vector3.ZERO
			if hud != null:
				hud.show_message("狼扑了个空，一头卡进了地里。\n（这是特性）", 3.0)
		else:
			_state = "wander"


## 晕眩：原地转圈 10 秒（被撞退累计 5 次 / 狼牙反震）
func _tick_stun(delta: float) -> void:
	_state_t += delta
	velocity.x *= 0.9
	velocity.z *= 0.9
	model.rotation.y += 9.0 * delta
	if _state_t >= STUN_TIME:
		_state = "wander"
		_knocks = 0
		if hud != null:
			hud.show_message("狼彻底转晕了。它好像老实了。大概吧。", 2.0)


## 卡地：挣扎两下，3 秒后"咻"消失
func _tick_stuck(delta: float) -> void:
	_state_t += delta
	velocity = Vector3.ZERO
	if _state_t < 0.5:
		model.position.z = sin(_state_t * 60.0) * 0.05
	elif _state_t >= STUCK_TIME:
		_despawn(false)


## 扑咬判定（玩家）：咬是处决级——无视血条直接走死亡流程（狼牙免死可救）
func _try_bite_player() -> bool:
	if player.global_position.distance_to(global_position) > BITE_RANGE:
		return false
	if player.is_ghosting():
		return false  # 穿模中：狼扑空，不会咬到
	if player.invincible_left > 0.0:
		if hud != null:
			hud.show_message("狼咬空了——它愣了一下。", 1.5)
		_pounce_cd = POUNCE_CD
		return true
	if sfx != null:
		sfx.play("bite")
	player.take_combat_hit(99, self)
	return true


## 咬路过的牛：秒杀 + 原地掉"牛排骨"（可拾取回士气）
func _bite_npc(cow: NpcCow) -> void:
	if sfx != null:
		sfx.play("bite")
	cow.combat_execute(self)
	_drop_rib(cow.global_position)
	if hud != null:
		hud.show_message("狼把一头路过的牛变成了排骨。梦里的牛肉不能细想。", 3.0)


## 牛排骨：棕色扁盒 + 骨拐头，浮空旋转，踩上去啃一口 +30 士气
func _drop_rib(at: Vector3) -> void:
	var rib := Node3D.new()
	rib.name = "CowRib"
	rib.position = at + Vector3(0.0, 0.6, 0.0)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.55, 0.12, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.18)
	mat.roughness = 1.0
	mi.mesh = mesh
	mi.material_override = mat
	rib.add_child(mi)
	var bone := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.1, 0.16)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.9, 0.88, 0.8)
	bone.mesh = bm
	bone.material_override = bmat
	bone.position = Vector3(0.2, -0.02, 0.08)
	rib.add_child(bone)
	var area := Area3D.new()
	var ac := CollisionShape3D.new()
	var ash := SphereShape3D.new()
	ash.radius = 1.2
	ac.shape = ash
	area.add_child(ac)
	area.body_entered.connect(_on_rib_touched.bind(rib))
	rib.add_child(area)
	get_parent().add_child(rib)
	var tw := rib.create_tween()
	tw.set_loops()
	tw.tween_property(rib, "position:y", rib.position.y + 0.25, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(rib, "position:y", rib.position.y, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tw2 := rib.create_tween()
	tw2.set_loops()
	tw2.tween_property(rib, "rotation:y", TAU, 2.4)


func _on_rib_touched(body: Node3D, rib: Node3D) -> void:
	if body is PlayerCow and not (body as PlayerCow)._dead:
		(body as PlayerCow).fullness = mini((body as PlayerCow).fullness + 30, 100)
		if hud != null:
			hud.show_message("啃了口牛排骨——这是别的牛的排骨。梦里不讲究。", 2.5)
			hud.set_fullness((body as PlayerCow).fullness)
		rib.queue_free()


## 选目标：无角牛（路过牛群）优先 → 够不着就拿玩家开刀
func _pick_target() -> void:
	var best: Node3D = null
	var best_d := 1e9
	for cow in get_tree().get_nodes_in_group("npcs"):
		if cow is NpcCow and not cow.is_dead_combat():
			var d := (cow as Node3D).global_position.distance_to(global_position)
			if d < 70.0 and d < best_d:
				best = cow
				best_d = d
	if best == null and player != null and not player._dead:
		var pd := player.global_position.distance_to(global_position)
		if pd < 80.0:
			best = player
	_target = best


func _walk(dir: Vector3) -> void:
	if dir.length_squared() > 0.01:
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
	model.rotation.z = sin(_life * 28.0) * 0.05  # 颠吧颠吧的跑步感


func _face(dir: Vector3) -> void:
	if dir.length_squared() > 0.01:
		model.rotation.y = atan2(dir.x, dir.z)


## 狼皮状态：绕圈徘徊，不打只盯着
func _circle_player() -> void:
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := maxf(flat.length(), 0.01)
	var tang := Vector3(-flat.z, 0.0, flat.x).normalized()
	if dist > 5.5:
		_walk(flat.normalized())
	elif dist < 3.2:
		_walk(-flat.normalized())
	else:
		_walk(tang * (1.0 if fmod(_life, 4.0) < 2.0 else -1.0))
	_face(flat)


# ————————————————— 受击 —————————————————

## 被撞退累加：5 次 → 转晕（此时可被处决）
func on_knocked() -> void:
	_knocks += 1
	_pounce_cd = 1.2
	if _knocks >= KNOCK_TO_STUN:
		knock_left = 0.0
		_state = "stun"
		_state_t = 0.0
		velocity = Vector3.ZERO
		if hud != null:
			hud.show_message("狼被撞蒙了——原地转圈 10 秒！撞它！", 3.0)


## 被狼牙免死反震（PlayerCow 调）：狠狠弹飞 + 直接转晕
func on_save_rebound() -> void:
	knock_left = 0.0
	_state = "stun"
	_state_t = 0.0
	_knocks = 0
	var away := Vector3.BACK
	if player != null:
		away = global_position - player.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.BACK
		away = away.normalized()
	velocity.x = away.x * 22.0
	velocity.z = away.z * 22.0
	velocity.y = 6.0


func combat_die() -> void:
	_despawn(true)


## 消失（被杀死 / 卡死 / 超时）：汇报 + 演出"咻"
func _despawn(was_kill: bool) -> void:
	if _state == "gone":
		return
	_state = "gone"
	wolf_despawned.emit(self, global_position, was_kill)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation:y", rotation.y + TAU, 0.6)
	tw.chain().tween_callback(queue_free)


# ————————————————— 建模（廉价抽象风） —————————————————

func _build_model() -> Node3D:
	var root := Node3D.new()
	var dark := _flat(Color(0.2, 0.19, 0.21))
	var gray := _flat(Color(0.3, 0.29, 0.31))
	var white := _flat(Color(0.92, 0.9, 0.85))
	var eye := _flat(Color(0.95, 0.85, 0.2), true)
	root.add_child(_box(Vector3(0.75, 0.55, 1.5), gray, Vector3(0, 0.24, 0)))       # 身体
	for lx in [-0.26, 0.26]:
		for lz in [0.42, -0.5]:
			root.add_child(_box(Vector3(0.13, 0.6, 0.13), dark, Vector3(lx, -0.18, lz)))  # 四根细腿
	root.add_child(_box(Vector3(0.42, 0.4, 0.52), gray, Vector3(0, 0.52, 0.92)))   # 头
	root.add_child(_box(Vector3(0.26, 0.14, 0.26), dark, Vector3(0, 0.38, 1.18)))  # 鼻口
	var mouth := _box(Vector3(0.3, 0.07, 0.24), white, Vector3(0.06, 0.3, 1.16))   # 歪嘴
	mouth.rotation.z = 0.7
	root.add_child(mouth)
	for ex in [-0.13, 0.13]:
		root.add_child(_box(Vector3(0.08, 0.08, 0.05), eye, Vector3(ex, 0.6, 1.12)))  # 眼睛
	for ex in [-0.2, 0.2]:
		var ear := _box(Vector3(0.1, 0.02, 0.2), dark, Vector3(ex, 0.78, 0.92))
		ear.rotation.x = 0.4
		root.add_child(ear)  # 耳朵
	root.add_child(_box(Vector3(0.05, 0.05, 0.45), dark, Vector3(0, 0.5, -0.85)))  # 尾巴
	return root


func _flat(c: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 1.0
	if emissive:
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 1.2
	return mat


func _box(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi