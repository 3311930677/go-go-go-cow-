extends SceneTree
## 第 4 轮测试：标题画面 / 地图系统 / 梦境→闪回→现实 全链路。
## 运行方式：
##   Godot_v4.6.1-stable_win64.exe --headless --path . --script res://tests/round4_test.gd

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
	print("==== 牛走 · 第 4 轮测试（双模式+地图） ====")

	# —— 1. 标题画面 ——
	var title_scene: PackedScene = load("res://scenes/title.tscn")
	_check(title_scene != null, "标题场景加载")
	if title_scene != null:
		var title := title_scene.instantiate()
		root.add_child(title)
		var btns := title.find_children("StartButton", "Button", true, false)
		var btn := btns[0] as Button if btns.size() > 0 else null
		_check(btn != null and btn.text.contains("梦"), "开始按钮存在", "btn=%s text=%s" % [str(btn), btn.text if btn != null else ""])
		title.queue_free()
		await process_frame

	# —— 2. 主场景与地图 ——
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "主场景加载")
	if scene == null:
		_finish()
		return
	var main := scene.instantiate()
	root.add_child(main)
	# 不使用 "as Game" 强转：类缓存未就绪时全局类解析会失败，
	# 这里用无类型引用 + 显式类型标注，保证任何缓存状态下可解析。
	var game = main
	var player := main.get_node_or_null("PlayerCow") as PlayerCow
	var terrain := main.get_node_or_null("Grassland") as Grassland
	var quests := main.get_node_or_null("QuestManager") as QuestManager
	var world_map := main.get_node_or_null("WorldMap") as WorldMap
	if player == null or terrain == null or quests == null or world_map == null:
		_check(false, "关键节点存在")
		_finish()
		return
	_check(game.mode == 0, "初始为梦境模式")  # Game.Mode.DREAM

	# 地图开关（第 13 轮起：按住 M 查看、松开即收——peek 语义）
	Input.action_press("map")
	await process_frame
	_check(world_map._open, "按住 M 打开地图")
	Input.action_release("map")
	await process_frame
	_check(not world_map._open, "松开 M 收起地图")

	# —— 3. 落地后推进任务全流程 ——
	for i in 150:
		await physics_frame

	# 3a. 撞出云雀
	var lark := quests.lark
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(lark.global_position.x, terrain.height_at(lark.global_position.x, lark.global_position.z + 2.5) + 1.5, lark.global_position.z + 2.5)
	await _settle(player)
	player.model.rotation.y = PI
	Input.action_press("charge")
	await physics_frame
	Input.action_release("charge")
	for i in 30:
		await physics_frame
	_check(quests.main_state == 1, "撞出云雀")

	# 3b. 护送回巢
	var nx := quests.nest_pos.x
	var nz := quests.nest_pos.z
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(nx, terrain.height_at(nx, nz + 3.0) + 1.5, nz + 3.0)
	await _settle(player)
	for i in 10:
		await physics_frame
	_check(quests.main_state == 2, "主线完成")

	# 3c. 领草料
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
	_check(quests.side_state == 1, "领取草料")

	# 3d. 投喂毛蛋
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
	_check(quests.side_state == 2, "支线完成（2/2）")

	# —— 4. 闪回 → 现实 ——
	# 等待：3 秒延迟 + 闪回全程（4 行 * 0.9 + 1.2 ≈ 4.8 秒），留余量
	for i in 620:
		await physics_frame
		if game.mode == 2:  # Game.Mode.REALITY
			break
	_check(game.mode == 2, "闪回后进入现实模式", "mode=%d" % game.mode)  # Game.Mode.REALITY
	_check(game.barn != null and game.barn.weak_cow != null, "牛棚与孱弱小牛存在")
	_check(not terrain.visible, "梦境世界已隐藏")
	_check(not player.visible, "梦境主角已隐藏")

	var weak = game.barn.weak_cow  # WeakCow（无类型引用避免类缓存依赖）
	# —— 5. 现实：移动缓慢 ——
	for i in 30:
		await physics_frame
	var wstart: Vector3 = weak.global_position
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	var wmoved: float = weak.global_position.distance_to(wstart)
	_check(wmoved < 2.5, "现实移动缓慢", "1秒位移 %.2f 米（梦境是 6 米）" % wmoved)
	_check(wmoved > 0.3, "现实仍可移动", "位移 %.2f 米" % wmoved)

	# —— 6. 现实：跳跃被拒绝 ——
	var y0: float = weak.global_position.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for i in 30:
		await physics_frame
	var y_delta := absf(weak.global_position.y - y0)
	_check(y_delta < 0.3, "跳跃被孱弱的腿拒绝", "y 变化 %.2f" % y_delta)

	# —— 7. 现实：吃奶结局 ——
	weak.velocity = Vector3.ZERO
	weak.global_position = weak.milk_pos + Vector3(0, 1.0, 1.5)
	for i in 10:
		await physics_frame
	Input.action_press("eat")
	for i in 3:
		await process_frame
	Input.action_release("eat")
	for i in 5:
		await physics_frame
	_check(weak.ending, "奶盆前按 E 触发结局")
	_check(weak.model.rotation.x > 0.3, "结局后小牛躺倒", "rotation.x=%.2f" % weak.model.rotation.x)

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
