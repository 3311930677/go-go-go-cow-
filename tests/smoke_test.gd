extends SceneTree
## 第 1 轮冒烟测试（headless 自动化自验证）。
## 运行方式：
##   Godot_v4.6.1-stable_win64.exe --headless --path . --script res://tests/smoke_test.gd
## 覆盖：主场景加载、玩家落地、移动、跳跃、出生点草丛、吃草、冲撞。

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
	print("==== 牛走 · 第 1 轮冒烟测试 ====")

	# —— 1. 主场景可加载 ——
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "主场景加载")
	if scene == null:
		_finish()
		return
	var main := scene.instantiate()
	root.add_child(main)

	# —— 2. 关键节点存在 ——
	var player := main.get_node_or_null("PlayerCow") as PlayerCow
	_check(player != null, "玩家小牛存在")
	var terrain := main.get_node_or_null("Grassland") as Grassland
	_check(terrain != null, "草原世界存在")
	var hud := main.get_node_or_null("GameHUD") as GameHUD
	_check(hud != null, "HUD 存在")
	var cam := main.get_node_or_null("CowCamera") as CowCamera
	_check(cam != null, "第三人称相机存在")
	if player == null or terrain == null:
		_finish()
		return

	# —— 3. 等待物理落地（150 帧 ≈ 2.5 秒） ——
	for i in 150:
		await process_frame
	_check(player.is_on_floor(), "小牛落地站稳", "y=%.2f" % player.global_position.y)
	_check(player.global_position.y > -3.0 and player.global_position.y < 8.0,
		"小牛位于合理高度", "y=%.2f" % player.global_position.y)

	# —— 4. 出生点附近有草 ——
	_check(terrain.has_grass_near(player.global_position, 6.0), "出生点附近有草丛")

	# —— 5. 前进移动 ——
	var start := player.global_position
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	var moved := player.global_position.distance_to(start)
	_check(moved > 2.0, "WASD 前进移动", "位移 %.2f 米" % moved)

	# —— 停稳 ——
	for i in 40:
		await physics_frame
	_check(player.is_on_floor(), "移动后仍站稳")

	# —— 6. 跳跃 ——
	var y0 := player.global_position.y
	var max_y := y0
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for i in 60:
		await physics_frame
		max_y = maxf(max_y, player.global_position.y)
	_check(max_y - y0 > 0.5, "空格跳跃", "上升 %.2f 米" % (max_y - y0))

	# —— 落回 ——
	for i in 50:
		await physics_frame
	_check(player.is_on_floor(), "跳跃后落回地面")

	# —— 7. 吃草：传送到出生草环的一丛草上 ——
	player.global_position = Vector3(2.6, terrain.height_at(2.6, 0.0) + 1.2, 0.0)
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	Input.action_press("eat")
	for i in 100:
		await physics_frame
	Input.action_release("eat")
	_check(player.fullness >= 10, "按住 E 吃草（吃饱度 +10）", "fullness=%d" % player.fullness)
	_check(not terrain.has_grass_near(Vector3(2.6, 0.0, 0.0), 1.0), "草丛被吃掉（实例消失）")

	# —— 8. 冲撞 ——
	for i in 30:
		await physics_frame
	var charge_start := player.global_position
	Input.action_press("charge")
	await physics_frame
	Input.action_release("charge")
	for i in 12:
		await physics_frame
	var charge_moved := player.global_position.distance_to(charge_start)
	_check(charge_moved > 1.5, "左键冲撞（前冲位移）", "位移 %.2f 米" % charge_moved)

	_finish()


func _finish() -> void:
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass_count, _failures.size()])
	for f in _failures:
		print("  失败项：%s" % f)
	quit(1 if not _failures.is_empty() else 0)
