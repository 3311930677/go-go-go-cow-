extends SceneTree
## 第 14 轮测试（P3）：巢漂移 / 毛蛋飞天→巨石BOSS / 混沌黑洞 / 混沌频率与后期事件。
## 运行：D:\godot\Godot_v4.6.1-stable_win64.exe --headless --path D:\牛来 --script res://tests/round14_test.gd

var _pass := 0
var _fail := 0
# 信号回调写成员变量——GDScript 的 lambda 按值捕获局部变量，写副本外层看不见
var _boss: Node = null
var _boss_got := false
var _smashed_at := Vector3(999, 999, 999)


func _on_boss_started(b: Node) -> void:
	_boss = b
	_boss_got = true


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("[PASS] %s" % name)
	else:
		_fail += 1
		print("[FAIL] %s  %s" % [name, detail])


func _reset(mode: String) -> void:
	ModeConfig.mode = mode
	NetConfig.enabled = false
	NetConfig.player_name = ""


func _run() -> void:
	print("==== 牛走 · 第 14 轮测试（P3：任务升级 + 混沌黑洞 + BOSS 战） ====")

	_reset("free")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.5).timeout
	var quests: Node = game.get("quests")
	var player: Node = game.get("player")
	var terrain: Node = game.get("terrain")
	var chaos: Node = game.get("chaos")
	var items: Node = game.get("items")
	var hud: Node = game.get("hud")
	var world_map: Node = game.get("world_map")

	# ============ A. 巢漂移 ============
	var nest_r := Vector2(quests.nest_pos.x, quests.nest_pos.z).length()
	_check(nest_r >= 45.0 and nest_r <= 80.0, "巢：漂移在 45~80 米环带内", "r=%.1f" % nest_r)
	var nest_h := absf(terrain.height_at(quests.nest_pos.x, quests.nest_pos.z) - quests.nest_pos.y)
	_check(nest_h < 1.0, "巢：贴合地形高度", "diff=%.2f" % nest_h)

	# ============ B. 毛蛋飞天 → 巨石 BOSS ============
	# 跳过投喂流程，直接排程飞天
	quests.set("_alpaca_fly_in", 0.05)
	quests.boss_started.connect(_on_boss_started)
	# 飞天流程：毛蛋起飞（倒计时≈0s + 3s 计时）→ BOSS 隆起 1.5s
	var waited := 0.0
	while not _boss_got and waited < 8.0:
		await create_timer(0.2).timeout
		waited += 0.2
	_check(_boss_got and _boss != null, "BOSS：毛蛋飞天引出巨石 BOSS", "waited=%.1fs" % waited)
	_check(_boss != null and _boss.get("rising") == true, "BOSS：从地下隆起中")
	await create_timer(2.5).timeout
	_check(_boss != null and _boss.get("active") == true, "BOSS：隆起完成开始活动")
	_check(quests.alpaca.visible == false, "BOSS：毛蛋已飞走隐藏")
	_check(get_nodes_in_group("boulder_bosses").size() >= 1, "地图：BOSS 进组（可画「石」标记）")

	# BOSS 战：4 次冲撞 → 胜利掉落
	if _boss != null:
		var before_patience: int = _boss.get("patience")
		_check(before_patience == 4, "BOSS：耐心 4/4")
		_boss.call("on_player_charged", Vector3.FORWARD)
		_check(_boss.get("patience") == 3, "BOSS：冲撞掉 1 耐心")
		_boss.call("on_player_charged", Vector3.FORWARD)
		_boss.call("on_player_charged", Vector3.FORWARD)
		_boss.call("on_player_charged", Vector3.FORWARD)
		_check(_boss.get("patience") <= 0, "BOSS：耐心归零")
		_check(_boss.get("_dead") == true, "BOSS：胜利（失去耐心飞走）")
		await create_timer(0.5).timeout
		var drop_count := 0
		for c in items.get_children():
			if c.name.begins_with("RewardItem"):
				drop_count += 1
		_check(drop_count >= 2, "BOSS：掉落 2 件战利品（号角+随机）", "drops=%d" % drop_count)
		# 清理：tween 飞走后自动 queue_free
		if is_instance_valid(_boss):
			_boss.queue_free()

	# ============ C. 混沌黑洞 ============
	chaos.call("spawn_blackhole")
	var bh: Node = chaos.get("_blackhole")
	# 黑洞在场时整图重绘一次（标记数据源注入 + 绘制不炸——炸了后面的检查就跑不到了）
	_check(world_map.get("chaos") == chaos, "地图：混沌调度器已注入（黑洞标记）")
	world_map.call("_draw_map")
	_check(bh != null, "黑洞：草原中心刷出")
	_check(Vector2(bh.global_position.x, bh.global_position.z).length() <= 15.0, "黑洞：出生在草原中心附近")
	# 吸力存在：给一个动态道具，看它被拉向黑洞
	_check(bh.get("hits_left") == 3, "黑洞：需要撞 3 下")
	bh.call("on_player_charged")
	bh.call("on_player_charged")
	_check(bh.get("hits_left") == 1, "黑洞：撞 2 下后剩 1")
	var smashed_pos: Vector3 = bh.global_position
	bh.smashed.connect(func(at): _smashed_at = at)
	bh.call("on_player_charged")
	await create_timer(0.3).timeout
	_check(chaos.get("_blackhole") == null, "黑洞：撞碎后调度器清除引用")
	_check(_smashed_at.distance_to(smashed_pos) < 5.0, "黑洞：撞碎信号带位置", "at=%s" % str(_smashed_at))
	var bh_rewards := 0
	for c in items.get_children():
		if c.name.begins_with("RewardItem"):
			bh_rewards += 1
	_check(bh_rewards >= 1, "黑洞：撞碎掉落号角", "rewards=%d" % bh_rewards)

	# —— 黑洞吃饱：吞 NPC 吐到别处 ——
	chaos.call("spawn_blackhole")
	var bh2: Node = chaos.get("_blackhole")
	var npc := NpcCow.new()
	game.add_child(npc)
	npc.global_position = bh2.global_position + Vector3(5, 1.5, 0)
	bh2.set("_life", 0.05)
	await create_timer(1.5).timeout
	var npc_r := Vector2(npc.global_position.x, npc.global_position.z).length()
	_check(npc_r >= 45.0, "黑洞：吃饱后把 NPC 吐到草原另一头", "r=%.1f" % npc_r)
	_check(chaos.get("_blackhole") == null, "黑洞：吃饱后飘走清除")

	# ============ D. 混沌频率与后期事件 ============
	# 进度 0 → 基线间隔
	_check(absf(chaos.call("_interval_min") - 20.0) < 0.01, "频率：进度 0 时基线 20s")
	# 模拟进度 4（主线+支线全完成）
	quests.set("main_state", 2)
	quests.set("side_state", 2)
	_check(chaos.call("_progress") == 4, "频率：进度统计 = 4")
	_check(absf(chaos.call("_interval_min") - 12.0) < 0.01, "频率：进度 4 时缩到 12s", str(chaos.call("_interval_min")))

	# 重力反转：玩家重力翻负
	player.set("gravity_scale", 1.0)
	chaos.call("trigger_gravity_flip")
	_check(player.get("gravity_scale") == -0.6, "后期事件：重力反转（负重力）", str(player.get("gravity_scale")))
	await create_timer(0.3).timeout
	# 反转期间靴子保护逻辑（gravity_scale<0 时不再改）
	player.set("gravity_scale", -1.0)
	chaos.call("trigger_gravity_flip")
	_check(player.get("gravity_scale") == -1.0, "后期事件：穿靴期间不被覆盖")
	player.set("gravity_scale", 1.0)
	chaos.set("_flip_left", 0.0)  # 提前结束，防污染后续

	# 时间变慢（离线）：全局慢动作
	chaos.call("trigger_slowmo")
	_check(absf(Engine.time_scale - 0.5) < 0.01, "后期事件：时间变慢（离线）", str(Engine.time_scale))
	chaos.set("_slowmo_left", 0.01)
	await create_timer(0.5).timeout
	_check(absf(Engine.time_scale - 1.0) < 0.01, "后期事件：慢动作恢复")

	game.queue_free()
	await create_timer(0.5).timeout

	_reset("free")
	_finish()


func _finish() -> void:
	var summary := "==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail]
	print(summary)
	var f := FileAccess.open("user://round14_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(summary)
		f.close()
	quit(1 if _fail > 0 else 0)
