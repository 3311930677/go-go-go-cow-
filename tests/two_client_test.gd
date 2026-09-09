extends SceneTree
## 双客户端联机测试：两个客户端连同一服务器，验证互相可见
## 运行：Godot --headless --path D:\牛来 --script res://tests/two_client_test.gd

const GODOT := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const PROJECT_PATH := "D:\\牛来"
const PORT := 24678
const SERVER_IP := "127.0.0.1"

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
	print("==== 双客户端联机测试 ====")

	# 启动服务器
	_srv_pid = OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH,
		"res://scenes/server.tscn", "--", "--port=%d" % PORT, "--event-interval=999"
	])
	_check(_srv_pid > 0, "服务器启动")
	await create_timer(3.0).timeout

	# 创建客户端 A
	NetConfig.enabled = true
	NetConfig.server_ip = SERVER_IP
	NetConfig.server_port = PORT
	var scene_a: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene_a)
	var game_a = scene_a
	_check(game_a.net != null, "客户端A NetManager 挂载")
	await create_timer(2.0).timeout
	_check(game_a.net.connected_ok, "客户端A 连接成功")

	# Godot 单进程只能有一个 MultiplayerAPI，用子进程跑客户端B
	var pid_b := OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH,
		"--script", "res://tests/_client_b.gd",
		"--", "--port=%d" % PORT
	])
	_check(pid_b > 0, "客户端B 子进程启动")
	await create_timer(3.0).timeout

	# 此时服务器应该有两个玩家
	# 客户端A 的快照应该包含客户端B
	var my_id_a := root.get_multiplayer().get_unique_id()
	print("客户端A ID=%d, players=%s" % [my_id_a, str(game_a.net.players.keys())])
	var has_other := false
	for pid in game_a.net.players:
		if pid != my_id_a:
			has_other = true
			print("  客户端A 看到 B: pid=%d pos=%s name=%s" % [pid, game_a.net.players[pid].get("pos"), game_a.net.players[pid].get("name")])
	_check(has_other, "客户端A 在快照中看到客户端B", "players=%s" % str(game_a.net.players.keys()))

	# 检查 NetPlayer 是否创建
	var has_net_player := false
	for child in game_a.get_children():
		if child is NetPlayer:
			has_net_player = true
			print("  NetPlayer: pid=%d pos=%s name=%s" % [child.peer_id, child.global_position, child.player_name])
	_check(has_net_player, "客户端A 创建了 NetPlayer 节点")

	# —— 聊天互发：A 发一条，B 也发一条，A 应收到 B 的 ——
	var recv: Array = []
	game_a.net.chat_received.connect(func(pname, text): recv.push_back([pname, text]))
	game_a.net.send_chat("哞~来自A的问候")

	# —— 全局游戏事件：B 会广播一条 KO；A 也发一条验证回环 ——
	var ev_recv: Array = []
	game_a.net.game_event_received.connect(func(data): ev_recv.push_back(data))
	game_a.net.send_game_event({"type": "ko", "attacker": "客户端A", "victim": "虚空"})

	await create_timer(7.0).timeout  # B 子进程会在 ~3s 后发自己的聊天与事件

	var chat_from_b := false
	var chat_detail := str(recv)
	for item in recv:
		if item[1] == "哞~来自B的问候" and item[0] != "…" and item[0] != "神秘小牛":
			chat_from_b = true
	_check(chat_from_b, "客户端A 收到B的聊天（含真实牛名）", chat_detail)

	var ev_from_b := false
	var ev_loopback := false
	var ev_detail := str(ev_recv)
	for d in ev_recv:
		if d.get("attacker") == "客户端B":
			ev_from_b = true
		if d.get("attacker") == "客户端A":
			ev_loopback = true
	_check(ev_from_b, "客户端A 收到B的全局游戏事件", ev_detail)
	_check(ev_loopback, "客户端A 收到自己广播的全局事件（回环）", ev_detail)

	OS.kill(pid_b)
	_finish()


func _finish() -> void:
	if _srv_pid > 0:
		OS.kill(_srv_pid)
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
