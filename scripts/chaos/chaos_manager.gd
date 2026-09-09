class_name ChaosManager
extends Node
## 物理崩坏事件调度器：定期随机触发 牛群迁徙 / 重力异常 / 道具疯狂。
## P3 升级：事件频率随任务进度变快；后期解锁"重力反转"和"时间变慢"；
## 每 5 分钟草原中心刷一个"混沌黑洞"（吸物——冲撞 3 下撞碎掉号角）。
## 这是本作的核心卖点——把"物理 Bug"变成主动体验的内容。

const EVENT_INTERVAL_MIN := 20.0  # 事件最小间隔（秒）——随进度缩短的基线
const EVENT_INTERVAL_MAX := 35.0  # 事件最大间隔（秒）
const FIRST_EVENT_DELAY := 15.0   # 开场首个事件延迟
const GRAVITY_ANOMALY_DURATION := 4.0  # 重力异常持续时间
const STAMPEDE_COUNT := 6         # 牛群数量

## 重力反转（后期事件）：万物坠向天空 6 秒
const GRAVITY_FLIP_DURATION := 6.0
## 时间变慢（后期事件，仅离线）：全局慢动作 4 秒
const SLOWMO_DURATION := 4.0
const SLOWMO_SCALE := 0.5
## 解锁后期事件的进度门槛（main_state + side_state ≥ 此值）
const LATE_EVENT_PROGRESS := 3

## 混沌黑洞
const BLACKHOLE_INTERVAL := 300.0  # 每 5 分钟一个
const BLACKHOLE_FIRST := 120.0     # 开局 2 分钟后第一个
const BLACKHOLE_CENTER_R := 12.0  # 出生在草原中心附近

## 狼群危机（P1-C）：自由模式每 5-8 分钟概率判定一次
const WOLF_CHECK_MIN := 300.0
const WOLF_CHECK_MAX := 480.0
const WOLF_CHANCE := 0.15            # 基础概率
const WOLF_CHANCE_CROWD := 0.25      # 玩家 40m 内牛群 ≥ 5 只
const WOLF_CHANCE_LATE := 0.35       # 游戏时间 > 20 分钟
const WOLF_CROWD_RANGE := 40.0
const WOLF_CROWD_MIN := 5
const WOLF_LATE_TIME := 1200.0
const WOLF_COUNT_MAX := 3            # 一次最多 3 只
const WOLF_WARN_GRASS := 3           # 预警高草丛数量
const WOLF_WARN_RADIUS := 88.0       # 预警出现在地图边缘

## 黑洞被玩家撞碎（at = 撞碎位置；game.gd 接去记生涯）
signal blackhole_smashed

## 外部依赖（由 game.gd 注入）
var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank
var quests: QuestManager    # 任务进度（决定事件频率与后期事件解锁）
var items: ItemManager      # 黑洞奖励掉落
var net: NetManager

var _elapsed := 0.0
var _next_event_in := FIRST_EVENT_DELAY
var _anomaly_left := 0.0
var _flip_left := 0.0
var _slowmo_left := 0.0
var _bh_elapsed := 0.0
var _next_bh_in := BLACKHOLE_FIRST
var _blackhole: ChaosBlackhole = null
var _wolf_elapsed := 0.0      # 距上次狼群判定的计时
var _next_wolf_in := WOLF_CHECK_MIN
var _wolves_alive := 0        # 当前存活狼数（决定是否静默等下一波）
## 停用开关（进入闪回/现实后由 game.gd 关闭）
var enabled := true


func _process(delta: float) -> void:
	if not enabled:
		return
	# 慢动作期间用真实时间推进计时器
	var rdt: float = delta / maxf(Engine.time_scale, 0.05)
	_elapsed += rdt
	_bh_elapsed += rdt

	# 重力异常进行中：持续给动态道具施加漂浮力
	if _anomaly_left > 0.0:
		_anomaly_left -= rdt
		for body in get_tree().get_nodes_in_group("dynamic_props"):
			if body is RigidBody3D:
				(body as RigidBody3D).apply_central_force(Vector3.UP * (body as RigidBody3D).mass * 12.0)
		if _anomaly_left <= 0.0:
			# 反向重力靴生效期间（负重力）不去动玩家的重力——那是牛自己的事
			if player.gravity_scale > 0.0:
				player.gravity_scale = 1.0
			hud.show_message("重力恢复了。大概吧。", 2.0)
		return

	# 重力反转进行中：万物坠向天空
	if _flip_left > 0.0:
		_flip_left -= rdt
		for body in get_tree().get_nodes_in_group("dynamic_props"):
			if body is RigidBody3D:
				(body as RigidBody3D).apply_central_force(Vector3.UP * (body as RigidBody3D).mass * 25.0)
		if _flip_left <= 0.0:
			if player.gravity_scale > 0.0:
				player.gravity_scale = 1.0
			hud.show_message("重力想起来自己该往哪边了。", 2.0)
		return

	# 时间变慢进行中
	if _slowmo_left > 0.0:
		_slowmo_left -= rdt
		if _slowmo_left <= 0.0:
			Engine.time_scale = 1.0
			hud.show_message("时间恢复了流速。大概吧。", 2.0)
		return

	if _elapsed >= _next_event_in:
		_elapsed = 0.0
		_next_event_in = randf_range(_interval_min(), _interval_max())
		_pick_event()

	# 混沌黑洞（自由模式限定——别打扰特性复刻的仪式感）
	if ModeConfig.mode == "free" and _blackhole == null and _bh_elapsed >= _next_bh_in:
		_bh_elapsed = 0.0
		_next_bh_in = BLACKHOLE_INTERVAL
		spawn_blackhole()

	# 狼群危机（P1-C，自由模式限定）：每 5-8 分钟概率判定，场上还有狼就静默
	if ModeConfig.mode == "free" and player != null:
		_wolf_elapsed += rdt
		if _wolves_alive <= 0 and _wolf_elapsed >= _next_wolf_in:
			_next_wolf_in = randf_range(WOLF_CHECK_MIN, WOLF_CHECK_MAX)
			var chance := WOLF_CHANCE
			if _npc_cows_near(WOLF_CROWD_RANGE) >= WOLF_CROWD_MIN:
				chance = WOLF_CHANCE_CROWD
			elif _elapsed >= WOLF_LATE_TIME:
				chance = WOLF_CHANCE_LATE
			if randf() < chance:
				trigger_wolves()


## 任务进度（0~4）：主线 2 步 + 支线 2 步
func _progress() -> int:
	if quests == null:
		return 0
	return int(quests.main_state == 2) + int(quests.side_state == 2) \
		+ int(quests.side_state >= 1) + int(quests.main_state >= 1)


## 进度越高，混沌越频繁（20~35s → 12~20s——草原逐渐失控）
func _interval_min() -> float:
	return maxf(12.0, EVENT_INTERVAL_MIN - _progress() * 2.0)


func _interval_max() -> float:
	return maxf(20.0, EVENT_INTERVAL_MAX - _progress() * 3.5)


func _pick_event() -> void:
	var late := _progress() >= LATE_EVENT_PROGRESS
	var r := randf()
	if late:
		# 后期池：5 种事件
		if r < 0.25:
			trigger_stampede()
		elif r < 0.45:
			trigger_gravity_anomaly()
		elif r < 0.6:
			trigger_props_wild()
		elif r < 0.8:
			trigger_gravity_flip()
		else:
			trigger_slowmo()
	else:
		if r < 0.4:
			trigger_stampede()
		elif r < 0.7:
			trigger_gravity_anomaly()
		else:
			trigger_props_wild()


# ————————————————— 原有三件套 —————————————————

## 牛群迁徙：6 只 Bug 各异的随机配色 NPC 牛横穿地图
func trigger_stampede() -> void:
	if sfx != null:
		sfx.play("event")
	hud.show_message("牛群迁徙开始了！跟上它们！（它们可能会卡墙。）", 3.5)
	var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var side := dir.cross(Vector3.UP)
	var bugs := [0, 1, 2, 3, 0, 0]
	bugs.shuffle()
	for i in STAMPEDE_COUNT:
		var cow := NpcCow.new()
		cow.bug_mode = bugs[i]
		cow.run_dir = (dir * -1.0 + side * randf_range(-0.15, 0.15)).normalized()
		get_parent().add_child(cow)
		# 出生在玩家 55 米外的一侧，横穿玩家附近
		var sxz := player.global_position + dir * 55.0 + side * randf_range(-12.0, 12.0)
		var y := terrain.height_at(sxz.x, sxz.z) + 1.2
		if bugs[i] == 3:
			y -= 0.9  # 半埋牛：出生就卡在地下
		cow.global_position = Vector3(sxz.x, y, sxz.z)


## 重力异常：万物上浮 4 秒（玩家重力也变轻）
func trigger_gravity_anomaly() -> void:
	if sfx != null:
		sfx.play("event")
	hud.show_message("重力异常！所有东西都飘起来了。这是特性。", 3.0)
	if player.gravity_scale > 0.0:  # 反向重力靴期间不打架
		player.gravity_scale = 0.25
	_anomaly_left = GRAVITY_ANOMALY_DURATION
	for body in get_tree().get_nodes_in_group("dynamic_props"):
		if body is RigidBody3D:
			var rb := body as RigidBody3D
			rb.apply_central_impulse(Vector3.UP * 4.0 + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))


## 道具疯狂：所有动态道具随机乱飞乱转
func trigger_props_wild() -> void:
	if sfx != null:
		sfx.play("event")
	hud.show_message("物理引擎下班了。", 2.5)
	for body in get_tree().get_nodes_in_group("dynamic_props"):
		if body is RigidBody3D:
			var rb := body as RigidBody3D
			var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.0), randf_range(-1.0, 1.0)).normalized()
			rb.apply_central_impulse(dir * randf_range(10.0, 22.0))
			rb.apply_torque_impulse(Vector3(randf_range(-25.0, 25.0), randf_range(-25.0, 25.0), randf_range(-25.0, 25.0)))


# ————————————————— P3 新事件 —————————————————

## 重力反转（后期）：万物坠向天空 6 秒（反向重力靴：英雄所见略同）
func trigger_gravity_flip() -> void:
	if sfx != null:
		sfx.play("event")
	hud.show_message("重力反转！天在下面了。跑不掉的，认命吧。", 3.5)
	if player.gravity_scale > 0.0:  # 正在穿靴子的牛不受影响——它已经疯了
		player.gravity_scale = -0.6
	_flip_left = GRAVITY_FLIP_DURATION
	for body in get_tree().get_nodes_in_group("dynamic_props"):
		if body is RigidBody3D:
			(body as RigidBody3D).apply_central_impulse(Vector3.UP * 8.0)


## 时间变慢（后期，仅离线）：全局慢动作 4 秒——子弹时间的廉价版
func trigger_slowmo() -> void:
	if NetConfig.enabled:
		# 联机不做全局慢动作（各端时间轴会打架）——换成道具疯狂代替
		trigger_props_wild()
		return
	if sfx != null:
		sfx.play("event")
	hud.show_message("时间变慢了。你也没快多少，但看起来很酷。", 3.0)
	Engine.time_scale = SLOWMO_SCALE
	_slowmo_left = SLOWMO_DURATION


# ————————————————— 混沌黑洞 —————————————————

## 草原中心刷出混沌黑洞：吸入万物，冲撞 3 下撞碎
func spawn_blackhole() -> void:
	if _blackhole != null and is_instance_valid(_blackhole):
		return
	var ang := randf() * TAU
	var r := randf_range(0.0, BLACKHOLE_CENTER_R)
	var x := cos(ang) * r
	var z := sin(ang) * r
	var bh := ChaosBlackhole.new()
	bh.name = "ChaosBlackhole"
	bh.player = player
	bh.hud = hud
	bh.sfx = sfx
	bh.net = net
	get_parent().add_child(bh)
	bh.global_position = Vector3(x, terrain.height_at(x, z) + 2.0, z)
	_blackhole = bh
	bh.smashed.connect(_on_blackhole_smashed)
	bh.swallowed_npc.connect(_on_blackhole_swallowed)
	bh.ate_and_left.connect(_on_blackhole_left)
	hud.show_message("草原中心出现了一个混沌黑洞！它正在吸走一切——\n冲撞它 3 下把它撞碎！（60 秒内）", 5.0)
	_broadcast("草原刷出了混沌黑洞，冲撞 3 下撞碎它")


func _on_blackhole_smashed(at: Vector3) -> void:
	_blackhole = null
	blackhole_smashed.emit(at)
	# 掉落：弹射号角（黑洞里塞满了历代飞天失败的遗物）+ 一份随机小礼物
	if items != null and at != null:
		items.drop_reward_near(at, "horn")
		items.drop_reward_near(at + Vector3(2.0, 0, 0), "")


## 黑洞吃饱飘走了：清引用（下一个 5 分钟的坑位留给后来者）
func _on_blackhole_left() -> void:
	_blackhole = null


func _on_blackhole_swallowed(npc: Node3D) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	# 被吞的 NPC 吐到新的离谱地方——任务还能做，就是得多跑路
	var ang := randf() * TAU
	var r := randf_range(50.0, 85.0)
	var x := cos(ang) * r
	var z := sin(ang) * r
	npc.global_position = Vector3(x, terrain.height_at(x, z) + 4.0, z)
	hud.show_message("被黑洞吸走的「%s」被吐到了草原另一头。\n（它本人似乎毫无察觉）" % _npc_name(npc), 4.5)


func _npc_name(npc: Node3D) -> String:
	if npc is Lark:
		return "云雀"
	if npc is Alpaca:
		return "毛蛋"
	return "路过的牛"


func _broadcast(text: String) -> void:
	if net != null and net.connected_ok:
		net.send_game_event({"type": "chaos", "name": net.my_name, "text": text})


# ————————————————— 狼群危机（P1-C） —————————————————

## 玩家 x 米内路过的牛群数量（决定狼群触发概率）
func _npc_cows_near(radius: float) -> int:
	var n := 0
	for cow in get_tree().get_nodes_in_group("npcs"):
		if cow is NpcCow and (cow as Node3D).global_position.distance_to(player.global_position) <= radius:
			n += 1
	return n


## 狼群事件：地图边缘高草丛预警 3 秒 → 蹦出 1-3 只抽象狼
func trigger_wolves() -> void:
	_wolf_elapsed = 0.0
	if not get_tree().get_nodes_in_group("wolves").is_empty():
		return
	if sfx != null:
		sfx.play("event")
	var ang := randf() * TAU
	var cx := cos(ang) * WOLF_WARN_RADIUS
	var cz := sin(ang) * WOLF_WARN_RADIUS
	if hud != null:
		hud.show_message("草丛里有东西……", 3.0)
	for i in WOLF_WARN_GRASS:
		var g := _warn_grass(Vector3(cx, 0.0, cz) + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0)))
		get_parent().add_child(g)
	_broadcast("草原边缘的草丛在剧烈晃动——有什么东西关了抖动？")
	await get_tree().create_timer(3.0).timeout
	if not enabled:
		return
	_spawn_wolves(Vector3(cx, 0.0, cz))


## 预警高草丛：放大 2 倍的草锥体，剧烈晃动 3 秒后缩没
func _warn_grass(at: Vector3) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(at.x, terrain.height_at(at.x, at.z), at.z)
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = 0.55
	cone.height = 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.18)
	mat.roughness = 1.0
	mi.mesh = cone
	mi.material_override = mat
	mi.scale = Vector3.ONE * 2.0
	mi.position.y = 1.6
	g.add_child(mi)
	var tw := g.create_tween()
	for i in 6:
		var amp := 0.18 * (1.0 - float(i) / 6.0)
		tw.tween_property(g, "rotation:z", amp if i % 2 == 0 else -amp, 0.28)
	tw.tween_property(g, "scale", Vector3(1.2, 0.1, 1.2), 0.3)
	tw.tween_callback(g.queue_free)
	return g


## 在预警点附近蹦出 1-3 只狼
func _spawn_wolves(at: Vector3) -> void:
	var count := 1 + randi() % WOLF_COUNT_MAX
	for i in count:
		var w := Wolf.new()
		w.name = "Wolf%d" % i
		w.player = player
		w.terrain = terrain
		w.hud = hud
		w.sfx = sfx
		get_parent().add_child(w)
		var px := at.x + randf_range(-6.0, 6.0)
		var pz := at.z + randf_range(-6.0, 6.0)
		w.global_position = Vector3(px, terrain.height_at(px, pz) + 0.9, pz)
		w.wolf_despawned.connect(_on_wolf_despawned)
		_wolves_alive += 1
	if hud != null:
		hud.show_message("从草丛里蹦出 %d 只抽象的狼！\n它们走路会瞬移、扑过来会咬。跑或战都行。" % count, 5.0)
	_broadcast("草丛里蹦出了 %d 只抽象的狼——注意安全" % count)
	if sfx != null:
		sfx.play("wolf")


## 狼消失（被杀/卡地/超时）：掉落 + 播报 + 清计数器
func _on_wolf_despawned(_w: Node3D, at: Vector3, was_kill: bool) -> void:
	_wolves_alive = maxi(_wolves_alive - 1, 0)
	if was_kill:
		if items != null:
			items.drop_reward_near(at, "wolf_tooth")
			if randf() < 0.35:
				items.drop_reward_near(at + Vector3(1.5, 0.0, 0.0), "wolf_skin")
			if randf() < 0.2:
				items.drop_reward_near(at + Vector3(-1.5, 0.0, 0.0), "wolf_bone")
		if hud != null:
			hud.show_message("狼变成了一堆道具。它生前一定很抽象。", 3.0)
		_broadcast("草原上少了一匹狼。剩下的在生气。")
	if _wolves_alive <= 0 and was_kill and hud != null:
		hud.show_message("狼群偃旗息鼓了。草丛恢复安静。（直到下次）", 3.0)
