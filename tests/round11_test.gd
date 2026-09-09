extends SceneTree
## 第 11 轮测试：多房间——同服务器按房间号分组，跨房不可见/不串聊天/模式各房独立/满员拒绝。
## 运行：Godot --headless --path D:\牛来 --script res://tests/round11_test.gd

const GODOT := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const PROJECT_PATH := "D:\\牛来"
const PORT := 24690

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
	print("==== 牛走 · 第 11 轮测试（多房间） ====")

	# 清理旧结果文件
	for key in ["b", "c", "d"]:
		var p := "user://room_%s.json" % key
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	# ———— 服务器：每房上限 2 头（顺便测满员） ————
	_srv_pid = OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH,
		"res://scenes/server.tscn", "--", "--port=%d" % PORT,
		"--event-interval=999", "--max-players=2"
	])
	_check(_srv_pid > 0, "多房间服务器启动（每房上限 2）")
	await create_timer(3.0).timeout

	# ———— 客户端 A（进程内，房间 1，想玩相扑） ————
	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = PORT
	NetConfig.room_id = "1"
	NetConfig.player_name = "客户端A"
	ModeConfig.mode = "sumo"

	var holder := Node.new()
	holder.name = "Main"
	root.add_child(holder)
	var net := NetManager.new()
	net.name = "NetManager"
	holder.add_child(net)

	var modes: Array = []
	var chats: Array = []
	net.mode_received.connect(func(m): modes.push_back(m))
	net.chat_received.connect(func(pname, text): chats.push_back([pname, text]))

	var waited := 0
	while not net.connected_ok and waited < 600:
		await physics_frame
		waited += 1
	_check(net.connected_ok, "客户端A 连接成功")
	_check(net.my_room == "1", "客户端A 房间号=my_room=1", net.my_room)
	await _wait_until(func(): return modes.size() >= 1, 4.0)
	_check(modes.size() >= 1 and modes[0] == "sumo", "房间1：第一头牛（A）定模式 sumo", str(modes))

	# ———— 客户端 B（子进程，房间 2，想玩大逃杀）；C（子进程，房间 1，想玩竞速→应被改成 sumo） ————
	var pid_b := OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH, "--script", "res://tests/_room_client.gd",
		"--", "--port=%d" % PORT, "--room=2", "--mode=battle", "--out=user://room_b.json"
	])
	var pid_c := OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH, "--script", "res://tests/_room_client.gd",
		"--", "--port=%d" % PORT, "--room=1", "--mode=race", "--out=user://room_c.json"
	])
	_check(pid_b > 0 and pid_c > 0, "客户端 B/C 子进程启动")

	# A 持续上报状态（保持在房间 1 快照里）
	var t := 0.0
	while t < 5.0:
		await physics_frame
		t += 1.0 / 60.0
		if fmod(t, 0.08) < 0.02:
			net.submit_state.rpc_id(1, Vector3(t, 1.0, 0.0), 0.0, "run", "客户端A")

	# A 的快照：应看到 C（同房），看不到 B（房间 2）
	var my_id := root.get_multiplayer().get_unique_id()
	var saw_c := false
	var saw_b := false
	for pid in net.players:
		if pid != my_id:
			var n: String = net.players[pid].get("name", "")
			if n == "客户端2":
				saw_b = true
			else:
				saw_c = true
	_check(saw_c, "同房互见：A（房间1）看到 C", str(net.players.keys()))
	_check(not saw_b, "跨房隔离：A（房间1）看不到 B（房间2）", str(net.players.keys()))

	# A 发聊天：房间 1 的 C 应收到，房间 2 的 B 不该收到
	net.send_chat("A房消息")

	# 再上报一会儿等 B/C 收完
	t = 0.0
	while t < 4.0:
		await physics_frame
		t += 1.0 / 60.0
		if fmod(t, 0.08) < 0.02:
			net.submit_state.rpc_id(1, Vector3(t, 1.0, 0.0), 0.0, "run", "客户端A")

	# ———— 客户端 D（子进程，房间 1 已满：A+C=2）→ 应收到 room_full ————
	var pid_d := OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH, "--script", "res://tests/_room_client.gd",
		"--", "--port=%d" % PORT, "--room=1", "--mode=free", "--out=user://room_d.json"
	])
	_check(pid_d > 0, "客户端 D 子进程启动（进满员房间）")

	# A 不该收到 B 的聊天
	var got_b_chat := false
	for c in chats:
		if c[1] == "房间2专用":
			got_b_chat = true
	_check(not got_b_chat, "聊天隔离：A 没收到 B（房间2）的聊天", str(chats))
	var a_loopback := false
	for c in chats:
		if c[1] == "A房消息":
			a_loopback = true
	_check(a_loopback, "聊天回环：A 收到自己发的消息", str(chats))

	# 等 B/C/D 结果文件落盘
	await _wait_until(func(): return FileAccess.file_exists("user://room_b.json") \
		and FileAccess.file_exists("user://room_c.json") \
		and FileAccess.file_exists("user://room_d.json"), 25.0)

	var rb := _read_json("user://room_b.json")
	var rc := _read_json("user://room_c.json")
	var rd := _read_json("user://room_d.json")

	_check(rb.get("connected", false), "B 连接成功（房间2）", str(rb))
	_check(rb.get("mode", "") == "battle", "房间2：B 第一头牛 → 模式 battle", str(rb))
	_check(not rb.get("saw_other", true), "跨房隔离：B（房间2）快照里没有别人", str(rb))
	_check(not rb.get("chat_from_a", true), "聊天隔离：B 没收到 A（房间1）的消息", str(rb))

	_check(rc.get("connected", false), "C 连接成功（房间1）", str(rc))
	_check(rc.get("mode", "") == "sumo", "房间1：C 想玩竞速但被房间模式改成 sumo", str(rc))
	_check(rc.get("saw_other", false), "同房互见：C（房间1）看到 A", str(rc))
	_check(rc.get("chat_from_a", false), "同房聊天：C 收到 A 的消息", str(rc))

	_check(rd.get("connected", false), "D 连接成功（试图进满员房间1）", str(rd))
	_check(rd.get("room_full", false), "满员拒绝：D 收到 room_full 事件", str(rd))
	_check(rd.get("snapshot_size", -1) == 0, "满员拒绝：D 未进房（快照为空）", str(rd))

	# 清理
	for p in [pid_b, pid_c, pid_d]:
		if p > 0:
			OS.kill(p)
	holder.queue_free()
	await create_timer(0.5).timeout
	if _srv_pid > 0:
		OS.kill(_srv_pid)

	for key in ["b", "c", "d"]:
		var path := "user://room_%s.json" % key
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_finish()


func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await create_timer(0.2).timeout
		t += 0.2


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text()) if f.get_as_text() != "" else {}


func _finish() -> void:
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
