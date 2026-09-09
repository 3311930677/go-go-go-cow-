extends SceneTree
## 第 10 轮测试：大逃杀越界修复 + 全模式联机（房间模式同步 / 相扑真人 KO）。
## 运行：Godot --headless --path D:\牛来 --script res://tests/round10_test.gd

const GODOT := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const PROJECT_PATH := "D:\\牛来"
const MODE_PORT := 24681

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


func _run() -> void:
	print("==== 牛走 · 第 10 轮测试（越界修复 + 全模式联机） ====")

	# ———— A. 标题画面：联机弹窗模式选择器 ————
	var title: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await create_timer(0.8).timeout
	_check(title._online_mode_btns.size() == 6, "联机弹窗：6 个模式按钮", str(title._online_mode_btns.size()))
	_check(title._online_mode == "free", "联机模式默认自由草原", title._online_mode)
	title._select_online_mode("battle")
	_check(title._online_mode == "battle", "选择器可切换到大逃杀", title._online_mode)
	title.queue_free()
	await create_timer(0.5).timeout

	# ———— B. 大逃杀：第 5 阶段收缩不再越界（原 ZONE_RADII[6] 崩溃窗口） ————
	NetConfig.enabled = false
	ModeConfig.mode = "battle"
	var game_b: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_b)
	await create_timer(1.5).timeout
	var b = game_b.get_node("BattleRoyale")

	b.clock_override = 175.0
	b._apply_timeline(175.0)
	_check(b.stage == 5 and b.phase == 1 and absf(b.radius - 5.0) < 0.01,
		"大逃杀：t=175（原崩溃点）最后一圈收缩保持 5 米", "s=%d p=%d r=%f" % [b.stage, b.phase, b.radius])
	b.clock_override = 179.9
	b._apply_timeline(179.9)
	_check(absf(b.radius - 5.0) < 0.01, "大逃杀：t=179.9 收缩尾仍为 5 米", "r=%f" % b.radius)
	b.clock_override = 270.0
	b._apply_timeline(270.0)
	_check(b.stage == 6 and b.radius < 5.0, "大逃杀：t=270 终极收缩中", "s=%d r=%f" % [b.stage, b.radius])

	# 全时间线扫描（0→300 每 0.25 秒）：任何一点越界都会中断脚本
	var scan_ok := true
	var t := 0.0
	while t < 300.0:
		b._apply_timeline(t)
		if b.radius < 0.4 or b.radius > 91.0:
			scan_ok = false
			break
		t += 0.25
	_check(scan_ok, "大逃杀：全时间线扫描 1200 点无越界、半径合法", "t=%.2f r=%f" % [t, b.radius])
	game_b.queue_free()
	await create_timer(1.0).timeout

	# ———— C. 相扑联机：陪练牛减员 + 真人 KO 计分 ————
	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = 1  # 死端口：只验证逻辑，不真连
	ModeConfig.mode = "sumo"
	var game_s: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_s)
	await create_timer(1.5).timeout
	var sumo = game_s.get_node("SumoArena")
	var npcs: Array = sumo.find_children("*", "NpcSumoCow", true, false)
	_check(npcs.size() == 2, "相扑联机：陪练牛减为 2 头（真人为主）", str(npcs.size()))

	var net_s = game_s.net
	_check(net_s != null and net_s.my_name != "", "联机时 NetManager 已创建且有牛名", str(net_s.my_name if net_s != null else "null"))

	# 真人 KO 计分（对方客户端播报 ko 事件，attacker 是我）
	sumo._on_net_event({"type": "ko", "attacker": net_s.my_name, "victim": "路人牛"})
	_check(sumo.kos == 1, "相扑联机：我撞飞真人计 1 KO", str(sumo.kos))
	sumo._on_net_event({"type": "ko", "attacker": net_s.my_name, "victim": net_s.my_name})
	_check(sumo.kos == 1, "相扑联机：自己撞飞自己不计分", str(sumo.kos))
	sumo._on_net_event({"type": "ko", "attacker": net_s.my_name, "victim": "陪练牛"})
	_check(sumo.kos == 1, "相扑联机：陪练牛 KO 事件不重复计分", str(sumo.kos))
	sumo._on_net_event({"type": "ko", "attacker": "别人", "victim": "路人牛"})
	_check(sumo.kos == 1, "相扑联机：别人的 KO 不给我计分", str(sumo.kos))
	sumo._on_net_event({"type": "race", "name": "x", "time": 1.0})
	_check(sumo.kos == 1, "相扑联机：无关事件被忽略", str(sumo.kos))

	# 房间模式回调的守卫：无效/相同模式不切场景
	ModeConfig.mode = "sumo"
	game_s._on_net_mode_received("不存在的模式")
	_check(ModeConfig.mode == "sumo", "房间模式：无效模式键被忽略", ModeConfig.mode)
	game_s._on_net_mode_received("sumo")
	_check(ModeConfig.mode == "sumo", "房间模式：相同模式不重载场景", ModeConfig.mode)
	game_s.queue_free()
	await create_timer(1.0).timeout

	# ———— D. 房间模式同步（本地服务器回环） ————
	_srv_pid = OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH,
		"res://scenes/server.tscn", "--", "--port=%d" % MODE_PORT, "--event-interval=999"
	])
	_check(_srv_pid > 0, "模式同步测试服务器启动")
	await create_timer(3.0).timeout

	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = MODE_PORT
	ModeConfig.mode = "sumo"  # 我想玩相扑
	var modes: Array = []
	# RPC 节点路径必须与服务器一致：/root/Main/NetManager
	var main_holder := Node.new()
	main_holder.name = "Main"
	root.add_child(main_holder)
	var net := NetManager.new()
	net.name = "NetManager"  # RPC 按节点路径寻址，名字必须与服务器端一致
	net.mode_received.connect(func(m): modes.push_back(m))
	main_holder.add_child(net)
	await _wait_modes(modes, 1)
	_check(modes.size() >= 1 and modes[0] == "sumo", "房间模式：第一头牛（我）定模式 → 回发 sumo", str(modes))

	# 换模式：房间只有我 → 重新进房即换模式（独居时房间按我的模式重建）
	modes.clear()
	net.submit_join.rpc_id(1, "1", "battle")
	await _wait_modes(modes, 1)
	_check(modes.size() >= 1 and modes[0] == "battle", "房间模式：独居换模式成功 → 回发 battle", str(modes))

	# 非法模式 → 服务器兜底 free
	modes.clear()
	net.submit_join.rpc_id(1, "1", "胡乱写的")
	await _wait_modes(modes, 1)
	_check(modes.size() >= 1 and modes[0] == "free", "房间模式：非法模式兜底为 free", str(modes))

	main_holder.queue_free()
	await create_timer(0.5).timeout
	if _srv_pid > 0:
		OS.kill(_srv_pid)

	_finish()


func _wait_modes(arr: Array, want: int) -> void:
	var waited := 0.0
	while arr.size() < want and waited < 6.0:
		await create_timer(0.2).timeout
		waited += 0.2


func _finish() -> void:
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
