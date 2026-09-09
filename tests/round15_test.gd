extends SceneTree
## 第 15 轮测试（P4）：生涯统计 / 成就解锁 / 弹窗 / 面板 / 存档 / 各系统钩子。
## 运行：D:\godot\Godot_v4.6.1-stable_win64.exe --headless --path D:\牛来 --script res://tests/round15_test.gd
## 注意：headless 下 Career 不写盘——测试前后备份/还原真实存档，确保零污染。

const REAL_SAVE := "user://career.json"
const TEMP_SAVE := "user://test_career_r15.json"
const TEMP_BAD := "user://test_career_r15_bad.json"

var _pass := 0
var _fail := 0
# 信号回调写成员变量——GDScript 的 lambda 按值捕获局部变量，写副本外层看不见
var _got_key := ""
var _unlock_count := 0


func _on_career_unlocked(key: String, _ach: Dictionary) -> void:
	_got_key = key
	_unlock_count += 1


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
	print("==== 牛走 · 第 15 轮测试（P4：生涯与成就） ====")

	# —— 备份真实生涯档，写一份干净档（集成测试的读档基线） ——
	# 顺带清掉上一轮遗留的临时档（不然单元 Career 会读到旧数据——202 的由来）
	var dclean := DirAccess.open("user://")
	for fname in ["test_career_r15.json", "test_career_r15_bad.json"]:
		if dclean.file_exists(fname):
			dclean.remove(fname)
	var had_real := FileAccess.file_exists(REAL_SAVE)
	var backup := PackedByteArray()
	if had_real:
		var rf := FileAccess.open(REAL_SAVE, FileAccess.READ)
		backup = rf.get_buffer(rf.get_length())
		rf.close()
	var wf := FileAccess.open(REAL_SAVE, FileAccess.WRITE)
	wf.store_string('{"stats":{},"unlocked":{},"modes_played":{}}')
	wf.close()

	# ============ A. Career 单元测试（临时档，persist 开） ============
	var c := Career.new()
	c.persist = true
	c.save_path = TEMP_SAVE
	root.add_child(c)
	c.unlocked.connect(_on_career_unlocked)

	var all_zero := true
	for s in Career.STATS:
		if float(c.stats[s]) != 0.0:
			all_zero = false
	_check(all_zero, "生涯：新建全零")
	_check(Career.ACHIEVEMENTS.size() == 19, "生涯：共 19 个成就", str(Career.ACHIEVEMENTS.size()))

	c.add("grass_eaten")
	c.add("grass_eaten")
	c.add("grass_eaten")
	_check(float(c.stats["grass_eaten"]) == 3.0, "生涯：累加统计")
	_check(c.is_unlocked("first_grass"), "生涯：达到阈值解锁（first_grass）")
	_check(_unlock_count == 1, "生涯：解锁信号恰好发一次", str(_unlock_count))

	c.add("grass_eaten", 97.0)  # 凑到 100
	_check(c.is_unlocked("graze_100"), "生涯：跨阈值解锁（graze_100）")
	c.add("grass_eaten", 1.0)  # 101——不重复解锁
	_check(_unlock_count == 2, "生涯：已解锁不重复发信号", str(_unlock_count))

	c.set_max("fly_peak", 60.0)
	_check(float(c.stats["fly_peak"]) == 60.0, "生涯：set_max 记录最高值")
	c.set_max("fly_peak", 30.0)
	_check(float(c.stats["fly_peak"]) == 60.0, "生涯：set_max 不回退")
	_check(c.is_unlocked("sky_50m"), "生涯：飞天 50 米成就")

	c.note_mode("free")
	c.note_mode("free")
	c.note_mode("sumo")
	_check(int(c.stats["modes_count"]) == 2, "生涯：模式去重计数", str(c.stats["modes_count"]))

	c.add("nope_stat")  # 未知字段：不炸不改
	_check(float(c.stats["grass_eaten"]) == 101.0, "生涯：未知字段被忽略")
	c.unlock("hole_1")
	c.unlock("bad_key")  # 未知成就：不炸
	_check(c.is_unlocked("hole_1") and not c.is_unlocked("bad_key"), "生涯：手动解锁/未知键安全")

	var achv_list := c.achievement_list()
	_check(achv_list.size() == 19, "生涯：成就列表 19 条")
	_check(str(achv_list[0]["progress"]).find("/") != -1, "生涯：成就带进度（x/y）", str(achv_list[0]["progress"]))
	_check(c.summary_lines().size() == 15, "生涯：统计摘要 15 行", str(c.summary_lines().size()))

	# —— 存/读档回环 ——
	var c2 := Career.new()
	c2.persist = true
	c2.save_path = TEMP_SAVE
	root.add_child(c2)
	_check(float(c2.stats["grass_eaten"]) == 101.0, "存档：统计回读", str(c2.stats["grass_eaten"]))
	_check(c2.is_unlocked("graze_100") and c2.is_unlocked("sky_50m"), "存档：解锁状态回读")
	_check(int(c2.stats["modes_count"]) == 2, "存档：模式回读")
	# 同名信号/字典不冲突：读档后还能再解锁，已解锁的不补发
	c2.unlocked.connect(_on_career_unlocked)
	_unlock_count = 0  # 基线归零
	c2.add("blackholes_smashed")  # hole_1 存档里已解锁 → 不补发信号
	_check(_unlock_count == 0, "存档：已解锁的不补发信号", str(_unlock_count))
	c2.add("charge_hits", 50.0)  # 新成就
	_check(c2.is_unlocked("charge_50") and _unlock_count == 1, "存档：读档后可继续解锁", str(_unlock_count))

	# —— 坏档容忍 ——
	var wb := FileAccess.open(TEMP_BAD, FileAccess.WRITE)
	wb.store_string("{{{not json at all")
	wb.close()
	var c3 := Career.new()
	c3.persist = false
	c3.save_path = TEMP_BAD
	root.add_child(c3)
	_check(float(c3.stats["grass_eaten"]) == 0.0 and c3.unlocked_count() == 0, "存档：坏档从零开始")

	# ============ B. 解锁弹窗 ============
	var toast := AchievementToast.new()
	root.add_child(toast)
	toast.notify("测试成就", "测试描述")
	await create_timer(0.5).timeout
	_check(toast._panel.visible == true, "弹窗：解锁后显示")
	await create_timer(4.5).timeout
	_check(toast._panel.visible == false, "弹窗：3 秒后自动收起")
	toast.notify("甲", "a")
	toast.notify("乙", "b")
	_check(toast.pending() == 2, "弹窗：排队一张张来", str(toast.pending()))

	# ============ C. 生涯面板 ============
	var panel := CareerPanel.new()
	panel.career = c
	root.add_child(panel)
	panel.open_panel()
	_check(panel.visible == true, "面板：能打开")
	_check(panel._stats_grid.get_child_count() == 15, "面板：统计格 15 项", str(panel._stats_grid.get_child_count()))
	_check(panel._ach_list.get_child_count() == 19, "面板：成就墙 19 行", str(panel._ach_list.get_child_count()))
	panel.close_panel()
	_check(panel.visible == false, "面板：能关闭")

	# ============ D. 集成：自由模式全链路 ============
	_reset("free")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.5).timeout
	var career: Node = game.get("career")
	var player: Node = game.get("player")
	var chaos: Node = game.get("chaos")
	var quests: Node = game.get("quests")
	var items: Node = game.get("items")

	_check(career != null, "集成：game 建了 Career")
	_check(int(career.stats["modes_count"]) == 1, "集成：进模式即记录（free）", str(career.stats["modes_count"]))

	# 吃草 / 金草（信号 → 生涯）
	player.grass_eaten.emit(10)
	player.grass_eaten.emit(50)
	_check(float(career.stats["grass_eaten"]) == 2.0, "集成：吃草计数", str(career.stats["grass_eaten"]))
	_check(float(career.stats["golden_eaten"]) == 1.0, "集成：金草单独计数", str(career.stats["golden_eaten"]))
	_check(career.is_unlocked("first_grass") and career.is_unlocked("first_gold"), "集成：吃草成就解锁")

	# 冲撞击飞
	player.charged_prop.emit(player)
	_check(float(career.stats["charge_hits"]) == 1.0, "集成：冲撞击飞计数")

	# 道具使用 + 购物
	items.call("add_item", "potion")
	items.call("use_slot", 0)
	_check(float(career.stats["items_used"]) == 1.0, "集成：道具使用计数", str(career.stats["items_used"]))
	items.call("spend_gold", 3)
	_check(float(career.stats["purchases"]) == 1.0, "集成：商店成交计数")
	_check(career.is_unlocked("shop_1"), "集成：购物成就解锁")

	# 飞天峰值（game._process 结算）
	player.set("_flying", true)
	player.global_position = Vector3(0, 60, 0)
	await create_timer(0.3).timeout
	player.set("_flying", false)
	await create_timer(0.3).timeout
	_check(float(career.stats["fly_count"]) == 1.0, "集成：飞天次数", str(career.stats["fly_count"]))
	_check(float(career.stats["fly_peak"]) >= 55.0, "集成：飞天峰值≈60 米", str(career.stats["fly_peak"]))
	_check(career.is_unlocked("first_fly") and career.is_unlocked("sky_50m"), "集成：飞天成就解锁")
	player.global_position = Vector3(0, 6, 0)
	player.set("velocity", Vector3.ZERO)

	# 掉出世界（game._process 重生 + 计数）
	player.global_position = Vector3(0, -30, 0)
	await create_timer(0.3).timeout
	_check(float(career.stats["falls"]) == 1.0, "集成：掉出世界计数", str(career.stats["falls"]))
	_check(player.global_position.y > 0.0, "集成：掉出后已重生", str(player.global_position))

	# 黑洞撞碎（chaos 信号 → 生涯）
	chaos.call("spawn_blackhole")
	var bh: Node = chaos.get("_blackhole")
	_check(bh != null, "集成：黑洞刷出")
	bh.call("on_player_charged")
	bh.call("on_player_charged")
	bh.call("on_player_charged")
	await create_timer(0.3).timeout
	_check(float(career.stats["blackholes_smashed"]) == 1.0, "集成：撞碎黑洞计数", str(career.stats["blackholes_smashed"]))
	_check(career.is_unlocked("hole_1"), "集成：黑洞成就解锁")

	# 聊天
	game.call("_on_chat_submitted", "生涯测试哞")
	_check(float(career.stats["chat_sent"]) == 1.0, "集成：聊天计数")

	# 全任务完成（触发闪回流——放最后）
	quests.quests_all_done.emit()
	await create_timer(3.6).timeout
	_check(float(career.stats["quests_done"]) == 1.0, "集成：全任务计数", str(career.stats["quests_done"]))
	_check(career.is_unlocked("dreamer"), "集成：梦醒时分解锁")

	# 弹窗确实在收成就（队列或正在展示）
	_check(game.get("achv_toast").call("pending") >= 1, "集成：解锁潮进弹窗队列", str(game.get("achv_toast").call("pending")))

	game.queue_free()
	await create_timer(0.5).timeout

	# ============ E. 集成：相扑夺冠 ============
	_reset("sumo")
	var game2: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game2)
	await create_timer(1.5).timeout
	var career2: Node = game2.get("career")
	var sumo: Node = game2.get("sumo")
	_check(sumo != null, "集成：相扑场就位")
	sumo.call("_win")
	_check(float(career2.stats["wins"]) == 1.0, "集成：相扑夺冠计数", str(career2.stats["wins"]))
	_check(career2.is_unlocked("win_1"), "集成：冠军相解锁")
	_check(int(career2.stats["modes_count"]) == 1, "集成：新场景新生涯（headless 不串档）", str(career2.stats["modes_count"]))
	game2.queue_free()
	await create_timer(0.5).timeout

	# ============ 收尾：还原真实存档 + 清理临时档 ============
	if had_real:
		var rf := FileAccess.open(REAL_SAVE, FileAccess.WRITE)
		rf.store_buffer(backup)
		rf.close()
	else:
		var d := DirAccess.open("user://")
		if d.file_exists("career.json"):
			d.remove("career.json")
	var d2 := DirAccess.open("user://")
	for fname in ["test_career_r15.json", "test_career_r15_bad.json"]:
		if d2.file_exists(fname):
			d2.remove(fname)

	_finish()


func _finish() -> void:
	var summary := "==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail]
	print(summary)
	var f := FileAccess.open("user://round15_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(summary)
		f.close()
	quit(1 if _fail > 0 else 0)
