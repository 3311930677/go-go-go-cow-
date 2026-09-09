extends SceneTree
## 第 7 轮测试：新模式（相扑/天降正义/Bug复刻/飞天竞速）+ T 键聊天 + 自定义牛名 + 全局事件
## 运行：Godot --headless --path D:\牛来 --script res://tests/round7_test.gd

const GODOT := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const PROJECT_PATH := "D:\\牛来"
const TEST_PORT := 24681

var _pass := 0
var _fail := 0
var _srv_pid := -1


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
	print("==== 牛走 · 第 7 轮测试（四新模式 + 聊天改名） ====")

	# ============ A. 联机：T 键聊天 + 自定义牛名 + 全局事件回环 ============
	_srv_pid = OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH,
		"res://scenes/server.tscn", "--", "--port=%d" % TEST_PORT, "--event-interval=999"
	])
	_check(_srv_pid > 0, "测试服务器启动")
	await create_timer(3.0).timeout

	_reset("free")
	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = TEST_PORT
	NetConfig.player_name = "牛走测试员"
	var game_a: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_a)
	await create_timer(3.0).timeout
	_check(game_a.net != null and game_a.net.connected_ok, "客户端连接成功")
	_check(game_a.net.my_name == "牛走测试员", "自定义牛名生效", game_a.net.my_name)

	# T 键绑定（事件级判定）
	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = KEY_T
	key_ev.pressed = true
	_check(key_ev.is_action_pressed("chat"), "T 键绑定到 chat 动作")

	# T 键真实事件流（Input → Viewport → _unhandled_input）
	Input.parse_input_event(key_ev)
	await create_timer(0.4).timeout
	_check(game_a.chat.chat_open, "按 T 打开聊天框（真实按键事件流）")
	game_a.chat.close(false)
	await create_timer(0.2).timeout

	# 全局聊天（服务器广播，含自己）
	var chat_recv: Array = []
	game_a.net.chat_received.connect(func(pname, text): chat_recv.push_back([pname, text]))
	game_a.net.send_chat("全局消息测试")
	await create_timer(1.5).timeout
	var chat_ok := false
	for item in chat_recv:
		if item[1] == "全局消息测试" and item[0] == "牛走测试员":
			chat_ok = true
	_check(chat_ok, "全局聊天回环（带自定义牛名）", str(chat_recv))

	# 全局游戏事件（KO 播报等）
	var ev_recv: Array = []
	game_a.net.game_event_received.connect(func(data): ev_recv.push_back(data))
	game_a.net.send_game_event({"type": "ko", "attacker": "牛走测试员", "victim": "陪练牛"})
	await create_timer(1.5).timeout
	var ev_ok := false
	for d in ev_recv:
		if d.get("type") == "ko" and d.get("attacker") == "牛走测试员":
			ev_ok = true
	_check(ev_ok, "全局游戏事件回环（服务器广播）", str(ev_recv))

	game_a.queue_free()
	await create_timer(1.0).timeout
	OS.kill(_srv_pid)
	_srv_pid = -1

	# ============ B. 牛牛相扑 ============
	_reset("sumo")
	var game_s: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_s)
	await create_timer(1.5).timeout
	_check(game_s.sumo != null, "相扑：擂台已生成")
	_check(game_s.quests == null and game_s.chaos == null, "相扑：任务/崩坏事件已停用")
	_check(game_s.player.global_position.distance_to(Vector3(120, 47, 120)) < 8.0,
		"相扑：玩家出生在擂台上", str(game_s.player.global_position))
	var npcs := 0
	var an_npc = null
	for c in game_s.sumo.get_children():
		if c is NpcSumoCow:
			npcs += 1
			if an_npc == null:
				an_npc = c
	_check(npcs == 5, "相扑：5 头陪练牛", str(npcs))

	# 模拟陪练牛掉下台 → KO 计分
	# （掉台判定在"被撞飞/冲过头"分支里——先置 knocked 让它确定性走进该分支）
	an_npc.knocked_timer = 1.0
	an_npc.global_position = Vector3(120, 10, 120)
	an_npc._physics_process(0.016)
	_check(game_s.sumo.kos == 1, "相扑：陪练牛掉台计 KO", str(game_s.sumo.kos))
	_check(an_npc.respawn_timer > 0.0 and not an_npc.visible, "相扑：掉台陪练牛进入重生等待")

	# 模拟玩家掉下台 → 传送回台 + 计次
	game_s.player.global_position = Vector3(120, 5, 120)
	game_s.sumo._physics_process(0.016)
	_check(game_s.sumo.falls == 1, "相扑：玩家掉台计次", str(game_s.sumo.falls))
	_check(game_s.player.global_position.distance_to(Vector3(120, 48, 120)) < 3.0,
		"相扑：玩家掉台后传送回出生点", str(game_s.player.global_position))
	game_s.queue_free()
	await create_timer(1.0).timeout

	# ============ C. 天降正义 ============
	_reset("survival")
	var game_v: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_v)
	await create_timer(1.5).timeout
	_check(game_v.meteors != null, "生存：陨石管理器已生成")
	_check(game_v.quests == null and game_v.chaos == null, "生存：任务/崩坏事件已停用")
	game_v.meteors.invuln = 0.0
	game_v.meteors._spawn_meteor()
	await create_timer(0.2).timeout
	var meteor_list := root.get_tree().get_nodes_in_group("meteors")
	var meteor_count := 0
	for m in meteor_list:
		if is_instance_valid(m):
			meteor_count += 1
	_check(meteor_count >= 1, "生存：陨石已生成", str(meteor_count))

	# 模拟被砸中：陨石贴身 + 高速
	if meteor_count > 0:
		var rb: RigidBody3D = null
		for m in meteor_list:
			if is_instance_valid(m):
				rb = m
				break
		if rb != null:
			rb.global_position = game_v.player.global_position
			rb.linear_velocity = Vector3(0, -20, 0)
			game_v.meteors._check_hits()
	_check(game_v.meteors.deaths == 1, "生存：被砸中计死亡", str(game_v.meteors.deaths))
	_check(game_v.player.velocity.y > 5.0, "生存：被砸中后表演飞天", str(game_v.player.velocity))
	game_v.queue_free()
	await create_timer(1.0).timeout

	# ============ D. Bug 复刻 ============
	_reset("quest")
	var game_q: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_q)
	await create_timer(1.5).timeout
	_check(game_q.bugquest != null, "复刻：挑战管理器已生成")
	_check(game_q.quests == null and game_q.chaos != null, "复刻：任务停用、崩坏事件保留")

	var step := func():
		game_q.bugquest._physics_process(0.016)
		await create_timer(0.05).timeout

	_check(game_q.bugquest.idx == 0, "复刻：从挑战 1 开始")
	game_q.player.fly_count += 1
	await step.call()
	_check(game_q.bugquest.idx == 1, "复刻：挑战1（触发飞天）完成", str(game_q.bugquest.idx))
	game_q.player.global_position.y = 30.0
	await step.call()
	_check(game_q.bugquest.idx == 2, "复刻：挑战2（25米高空）完成", str(game_q.bugquest.idx))
	var prop := RigidBody3D.new()
	prop.add_to_group("dynamic_props")
	game_q.add_child(prop)
	prop.global_position = Vector3(5, 6, 5)
	await step.call()
	_check(game_q.bugquest.idx == 3, "复刻：挑战3（道具上天）完成", str(game_q.bugquest.idx))
	game_q.player.global_position = Vector3(-60, 1.0, -60)
	await step.call()
	_check(game_q.bugquest.idx == 4, "复刻：挑战4（进入隐藏区）完成", str(game_q.bugquest.idx))
	game_q.terrain.golden_eaten += 3
	await step.call()
	_check(game_q.bugquest.idx == 5, "复刻：挑战5（吃3丛金草）完成", str(game_q.bugquest.idx))
	game_q.player.fly_count += 2
	await step.call()
	_check(game_q.bugquest.done, "复刻：全部 6 挑战完成")
	prop.queue_free()
	game_q.queue_free()
	await create_timer(1.0).timeout

	# ============ E. 飞天竞速 ============
	_reset("race")
	var game_r: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_r)
	await create_timer(1.5).timeout
	_check(game_r.race != null, "竞速：赛道已生成")
	_check(game_r.quests == null and game_r.chaos == null, "竞速：任务/崩坏事件已停用")
	_check(game_r.race._rings.size() == 10, "竞速：10 个浮环", str(game_r.race._rings.size()))

	# 穿环流程
	game_r.player.global_position = game_r.race.ring_positions[0]
	game_r.race._physics_process(0.016)
	_check(game_r.race.state == 1 and game_r.race.idx == 1, "竞速：穿第 1 环开始计时", "state=%d idx=%d" % [game_r.race.state, game_r.race.idx])
	for i in range(1, 10):
		game_r.player.global_position = game_r.race.ring_positions[i]
		game_r.race._physics_process(0.016)
	_check(game_r.race.state == 2, "竞速：穿完全部环完赛", "state=%d idx=%d" % [game_r.race.state, game_r.race.idx])
	_check(FileAccess.file_exists(ProjectSettings.globalize_path("user://race_best.txt")), "竞速：最佳成绩已保存")

	# R 重开
	game_r.race.reset()
	_check(game_r.race.state == 0 and game_r.race.idx == 0, "竞速：R 重置赛道")
	game_r.queue_free()
	await create_timer(0.5).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://race_best.txt"))

	# ============ 收尾 ============
	_reset("free")
	_finish()


func _finish() -> void:
	if _srv_pid > 0:
		OS.kill(_srv_pid)
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
