extends SceneTree
## 第 2 轮测试：飞天BUG / 冲撞击飞 / 主动穿模 / 金草 / 三大崩坏事件。
## 运行方式：
##   Godot_v4.6.1-stable_win64.exe --headless --path . --script res://tests/round2_test.gd

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
	print("==== 牛走 · 第 2 轮测试（荒诞物理） ====")

	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "主场景加载")
	if scene == null:
		_finish()
		return
	var main := scene.instantiate()
	root.add_child(main)

	var player := main.get_node_or_null("PlayerCow") as PlayerCow
	var terrain := main.get_node_or_null("Grassland") as Grassland
	var chaos := main.get_node_or_null("ChaosManager") as ChaosManager
	if player == null or terrain == null or chaos == null:
		_check(false, "关键节点存在")
		_finish()
		return

	# —— 1. 飞天 BUG：1.35 秒内连跳 3 次 ——
	for i in 150:
		await physics_frame
	_check(player.is_on_floor(), "初始落地")
	var max_y := player.global_position.y
	for jump_i in 3:
		# 等待落地
		var wait := 0
		while not player.is_on_floor() and wait < 200:
			await physics_frame
			wait += 1
		Input.action_press("jump")
		await physics_frame
		Input.action_release("jump")
		await physics_frame
	_check(player._flying, "三连跳触发飞天 BUG")
	# 等待飞天结束（超时保护 1200 帧）
	var fly_frames := 0
	while player._flying and fly_frames < 1200:
		await physics_frame
		max_y = maxf(max_y, player.global_position.y)
		fly_frames += 1
	_check(not player._flying, "飞天最终落地")
	_check(max_y > 8.0, "飞天高度 > 8 米", "max_y=%.2f" % max_y)

	# —— 2. 冲撞击飞动态石头 ——
	for i in 30:
		await physics_frame
	var rock := RigidBody3D.new()
	var rock_col := CollisionShape3D.new()
	var rock_shape := SphereShape3D.new()
	rock_shape.radius = 0.45
	rock_col.shape = rock_shape
	rock.add_child(rock_col)
	main.add_child(rock)
	rock.global_position = player.global_position + Vector3(0, 0.5, 2.0)
	player.model.rotation.y = 0.0  # 面向 +Z
	var rock_start := rock.global_position
	Input.action_press("charge")
	await physics_frame
	Input.action_release("charge")
	for i in 40:
		await physics_frame
	var rock_moved := rock.global_position.distance_to(rock_start)
	_check(rock_moved > 1.0, "冲撞击飞石头", "石头位移 %.2f 米" % rock_moved)
	rock.queue_free()

	# —— 3. 主动穿模：冲撞穿过隐藏区南墙 ——
	for i in 90:
		await physics_frame  # 先耗掉上一次冲撞的冷却（1.32s）
	var cx := Grassland.SECRET_CENTER.x
	var cz := Grassland.SECRET_CENTER.y
	var wall_z := cz + Grassland.SECRET_HALF  # 南墙 Z 坐标
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(cx, terrain.height_at(cx, cz + 9.0) + 1.5, cz + 9.0)
	await _settle_player(player)
	player.model.rotation.y = PI  # 面向 -Z（朝墙）
	Input.action_press("charge")
	await physics_frame
	Input.action_release("charge")
	for i in 30:
		await physics_frame
	_check(player.global_position.z < wall_z - 0.8, "冲撞穿墙（进入隐藏区）",
		"player z=%.2f，墙 z=%.2f" % [player.global_position.z, wall_z])

	# —— 4. 金草：站隐藏区中心吃草 +50 ——
	for i in 60:
		await physics_frame
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(cx, terrain.height_at(cx, cz) + 1.5, cz)
	await _settle_player(player)
	var fullness_before := player.fullness
	Input.action_press("eat")
	for i in 150:
		await physics_frame
	Input.action_release("eat")
	_check(player.fullness - fullness_before >= 50, "金草 +50 饱食度",
		"增量 %d" % (player.fullness - fullness_before))

	# —— 5. 牛群迁徙事件 ——
	chaos.trigger_stampede()
	for i in 20:
		await physics_frame
	var cows := root.find_children("*", "NpcCow", true, false)
	_check(cows.size() >= STAMPEDE_EXPECTED, "牛群迁徙生成 NPC 牛", "数量 %d" % cows.size())
	# 观察数秒确认无崩溃
	for i in 120:
		await physics_frame

	# —— 6. 重力异常事件 ——
	chaos.trigger_gravity_anomaly()
	_check(player.gravity_scale < 1.0, "重力异常生效（倍率调低）",
		"scale=%.2f" % player.gravity_scale)
	for i in 330:  # 4 秒异常 + 余量
		await physics_frame
	_check(is_equal_approx(player.gravity_scale, 1.0), "重力异常结束后恢复",
		"scale=%.2f" % player.gravity_scale)

	# —— 7. 道具疯狂事件 ——
	var props := main.get_tree().get_nodes_in_group("dynamic_props")
	var sample: RigidBody3D = null
	for p in props:
		if p is RigidBody3D and is_instance_valid(p):
			sample = p
			break
	if sample != null:
		var sample_start := sample.global_position
		chaos.trigger_props_wild()
		for i in 60:
			await physics_frame
		var moved := sample.global_position.distance_to(sample_start)
		_check(moved > 0.3, "道具疯狂（石头乱飞）", "位移 %.2f 米" % moved)
	else:
		_check(false, "找到动态道具样本")

	_finish()


const STAMPEDE_EXPECTED := 6


## 传送后等待玩家稳定落地（先刷数帧让 is_on_floor 反映真实状态，再等落地）
func _settle_player(player: PlayerCow) -> void:
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
