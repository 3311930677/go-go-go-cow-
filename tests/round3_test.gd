extends SceneTree
## 第 3 轮测试：任务系统（云雀主线 / 毛蛋支线 / 完成度）。
## 运行方式：
##   Godot_v4.6.1-stable_win64.exe --headless --path . --script res://tests/round3_test.gd

var _failures: Array[String] = []
var _pass_count := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_pass_count += 1
		print("[PASS] %s" % name)
	else:
		_failures.append(name)
		print("[FAIL] %s  %s" % [name, detail])


func _run_tests() -> void:
	print("==== 牛走 · 第 3 轮测试（任务系统） ====")

	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "主场景加载")
	if scene == null:
		_finish()
		return
	var main := scene.instantiate()
	root.add_child(main)

	var player := main.get_node_or_null("PlayerCow") as PlayerCow
	var terrain := main.get_node_or_null("Grassland") as Grassland
	var quests := main.get_node_or_null("QuestManager") as QuestManager
	var hud := main.get_node_or_null("GameHUD") as GameHUD
	if player == null or terrain == null or quests == null or hud == null:
		_check(false, "关键节点存在")
		_finish()
		return

	# —— 1. 任务 NPC 与物件存在 ——
	_check(quests.lark != null, "云雀已生成")
	_check(quests.alpaca != null, "毛蛋已生成")
	_check(quests.feed_pile != null, "草料堆已生成")
	_check(terrain.tree_positions.size() >= 30, "静态树位置已记录", "数量 %d" % terrain.tree_positions.size())
	var lark := quests.lark
	_check(lark.state == Lark.State.STUCK, "云雀初始为卡住状态")
	_check(quests.main_state == 0 and quests.side_state == 0, "任务初始状态正确")

	# —— 2. 主线：冲撞撞出云雀 ——
	for i in 150:
		await physics_frame
	_check(player.is_on_floor(), "初始落地")
	var lx := lark.global_position.x
	var lz := lark.global_position.z
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(lx, terrain.height_at(lx, lz + 2.5) + 1.5, lz + 2.5)
	await _settle(player)
	player.model.rotation.y = PI  # 面向 -Z（朝云雀）
	Input.action_press("charge")
	await physics_frame
	Input.action_release("charge")
	for i in 30:
		await physics_frame
	_check(lark.state == Lark.State.FOLLOW, "冲撞撞出云雀（进入跟随）", "state=%d" % lark.state)
	_check(quests.main_state == 1, "主线进入护送阶段")

	# —— 3. 主线：护送回巢 ——
	var nx := quests.nest_pos.x
	var nz := quests.nest_pos.z
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(nx, terrain.height_at(nx, nz + 3.0) + 1.5, nz + 3.0)
	await _settle(player)
	for i in 10:
		await physics_frame
	_check(quests.main_state == 2, "护送到巢（主线完成）", "main_state=%d" % quests.main_state)
	_check(lark.state == Lark.State.NESTED, "云雀入巢")

	# —— 4. 支线：领取草料 ——
	var px := quests.feed_pile.global_position.x
	var pz := quests.feed_pile.global_position.z
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(px, terrain.height_at(px, pz + 1.5) + 1.5, pz + 1.5)
	await _settle(player)
	Input.action_press("eat")
	for i in 3:
		await process_frame
	Input.action_release("eat")
	for i in 10:
		await physics_frame
	_check(quests.has_feed, "领取草料", "has_feed=%s" % str(quests.has_feed))
	_check(quests.side_state == 1, "支线进入投喂阶段")

	# —— 5. 支线：投喂毛蛋 ——
	var ax := quests.alpaca.global_position.x
	var az := quests.alpaca.global_position.z
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(ax, terrain.height_at(ax, az + 2.0) + 1.5, az + 2.0)
	await _settle(player)
	Input.action_press("eat")
	for i in 3:
		await process_frame
	Input.action_release("eat")
	for i in 10:
		await physics_frame
	_check(quests.side_state == 2, "投喂毛蛋（支线完成）", "side_state=%d" % quests.side_state)
	_check(quests.alpaca.fed, "毛蛋进入进食动画")

	# —— 6. HUD 完成度 2/2（QuestManager 有 0.25s 节流，多等一拍） ——
	for i in 25:
		await physics_frame
	_check(hud.task_label.text.contains("任务完成度：2/2"), "HUD 显示完成度 2/2",
		"text=%s" % hud.task_label.text.replace("\n", " | "))

	_finish()


## 传送后等待玩家稳定落地（先刷数帧让 is_on_floor 反映真实状态，再等落地）
func _settle(player: PlayerCow) -> void:
	for i in 5:
		await physics_frame
	var settle := 0
	while not player.is_on_floor() and settle < 150:
		await physics_frame
		settle += 1
	for i in 5:
		await physics_frame


func _finish() -> void:
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass_count, _failures.size()])
	for f in _failures:
		print("  失败项：%s" % f)
	quit(1 if not _failures.is_empty() else 0)
