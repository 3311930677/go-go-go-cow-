extends SceneTree
## 第 8 轮测试：哞哞大逃杀（缩圈时间线 / 帧率机制 / 陪练牛 / 淘汰与胜利 / 地图标注）
## 运行：Godot --headless --path D:\牛来 --script res://tests/round8_test.gd

const GODOT := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const PROJECT_PATH := "D:\\牛来"

var _pass := 0
var _fail := 0


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
	print("==== 牛走 · 第 8 轮测试（哞哞大逃杀） ====")
	_check(ModeConfig.is_valid("battle"), "配置：battle 为有效模式")

	# ============ A. 场景结构与缩圈时间线 ============
	_reset("battle")
	var game_b: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_b)
	await create_timer(1.5).timeout
	_check(game_b.battle != null, "大逃杀：管理器已生成")
	_check(game_b.quests == null and game_b.chaos == null, "大逃杀：任务/崩坏事件已停用")
	_check(game_b.world_map.battle == game_b.battle, "大逃杀：地图已注入引用")
	_check(game_b.hud.help_label.text.find("掉帧") != -1, "大逃杀：操作提示已切换")
	var b = game_b.battle
	_check(b._ring != null and b._dome != null, "大逃杀：发光圆环与安全罩已生成")

	# 时间线：等待期 / 收缩期 / 收缩完成 / 最终保持 / 终极收缩
	b.clock_override = 5.0
	b._physics_process(0.016)
	_check(b.radius == 90.0 and b.phase == 0, "时间线：t=5 → 初始圈 90 米等待", "r=%f p=%d" % [b.radius, b.phase])
	b.clock_override = 25.0
	b._physics_process(0.016)
	_check(b.phase == 1 and b.radius < 90.0 and b.radius > 60.0, "时间线：t=25 → 90→60 收缩中", "r=%f p=%d" % [b.radius, b.phase])
	b.clock_override = 30.0
	b._physics_process(0.016)
	_check(b.stage == 1 and absf(b.radius - 60.0) < 0.01, "时间线：t=30 → 第 2 圈 60 米", "r=%f s=%d" % [b.radius, b.stage])
	b.clock_override = 200.0
	b._physics_process(0.016)
	_check(b.stage == 5 and absf(b.radius - 5.0) < 0.01, "时间线：t=200 → 最终圈 5 米保持", "r=%f s=%d" % [b.radius, b.stage])
	b.clock_override = 270.0
	b._physics_process(0.016)
	_check(b.stage == 6 and b.radius < 5.0, "时间线：t=270 → 终极收缩中", "r=%f s=%d" % [b.radius, b.stage])

	# ============ B. 帧率机制 ============
	b.clock_override = 5.0
	b.fps = 10.0
	b.player.global_position = Vector3(0, 1, 0)
	b._physics_process(1.0)
	_check(b.fps > 10.0 and b.fps <= 60.0, "帧率：圈内每秒回帧", str(b.fps))
	b.player.global_position = Vector3(0, 1, 150)
	b.fps = 60.0
	b._physics_process(1.0)
	_check(absf(b.fps - 48.0) < 0.5, "帧率：圈外每秒 -12", str(b.fps))
	b._update_hud(150.0)
	_check(b.hud.task_label.text.find("未加载区域") != -1, "HUD：圈外显示未加载区域警告")

	# ============ C. 陪练牛 ============
	var npc_count := 0
	var an_npc = null
	for c in b.get_children():
		if c is NpcRoyaleCow:
			npc_count += 1
			if an_npc == null:
				an_npc = c
	_check(npc_count == 5, "陪练：5 头陪练牛", str(npc_count))
	_check(an_npc != null and an_npc.cow_name.begins_with("陪练牛"), "陪练：命名规范", an_npc.cow_name if an_npc != null else "null")
	# 圈外超时 → 出局
	an_npc.global_position = Vector3(0, 1, 150)
	an_npc._physics_process(6.5)
	_check(b.alive_npc == 4, "陪练：圈外超时出局", str(b.alive_npc))
	_check(an_npc.is_queued_for_deletion(), "陪练：出局后已清理")

	# ============ D. 胜利 ============
	var to_elim: Array = []
	for c in b.get_children():
		if c is NpcRoyaleCow and not c.is_queued_for_deletion():
			to_elim.append(c)
	for c in to_elim:
		b.on_npc_elim(c)
	_check(b.alive_npc == 0, "胜利：陪练牛全灭")
	b.clock_override = 5.0
	b.player.global_position = Vector3(0, 1, 0)
	b._physics_process(0.016)
	_check(b.won and b.over, "胜利：玩家成为最后加载的牛", "won=%s over=%s" % [str(b.won), str(b.over)])
	var expect_center: Vector2 = b._centers[1]  # 场景释放前留档（圈心确定性比对用）
	game_b.queue_free()
	await create_timer(1.0).timeout

	# ============ E. 玩家出局（圈外帧率归零） ============
	_reset("battle")
	var game_e: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_e)
	await create_timer(1.5).timeout
	var b2 = game_e.battle
	_check(b2._centers.size() == 6 and b2._centers[1] == expect_center, "圈心：序列确定性（同种子）")
	b2.clock_override = 5.0
	b2.player.global_position = Vector3(0, 1, 150)
	for i in 6:
		b2._physics_process(1.0)
	_check(b2.eliminated and b2.over, "出局：圈外帧率归零闪退", "fps=%f elim=%s" % [b2.fps, str(b2.eliminated)])
	_check(b2.rank == 6, "出局：名次 = 剩余牛数（第 6 名）", str(b2.rank))
	_check(not b2.player.is_physics_processing(), "出局：玩家已冻结")
	game_e.queue_free()
	await create_timer(1.0).timeout

	# ============ F. 掉出世界 = 出局 ============
	_reset("battle")
	var game_f: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_f)
	await create_timer(1.5).timeout
	var b3 = game_f.battle
	b3.clock_override = 5.0
	game_f.player.global_position = Vector3(0, -30.0, 0)
	game_f._process(0.016)
	_check(game_f.player.global_position.y < -20.0, "掉世界：不触发常规重生（battle 已排除）", str(game_f.player.global_position))
	b3._physics_process(0.016)
	_check(b3.eliminated, "掉世界：判定为闪退出局", str(b3.eliminated))
	game_f.queue_free()
	await create_timer(0.5).timeout

	_reset("free")
	_finish()


func _finish() -> void:
	var summary := "==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail]
	print(summary)
	var f := FileAccess.open("user://round8_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(summary)
		f.close()
	quit(1 if _fail > 0 else 0)
