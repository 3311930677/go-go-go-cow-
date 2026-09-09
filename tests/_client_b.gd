extends SceneTree
## 客户端B：连接服务器，发送状态，打印收到的快照

func _initialize() -> void:
	print("[B] 脚本启动")
	_run.call_deferred()


func _run() -> void:
	print("[B] _run 开始")
	var port := 24678
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
	print("[B] 端口=%d" % port)

	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = port

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var game = scene
	print("[B] 场景已加载 net=%s" % str(game.net != null))

	# 等待连接
	var waited := 0
	while not game.net.connected_ok and waited < 600:
		await physics_frame
		waited += 1
	if game.net.connected_ok:
		print("[B] 连接成功 id=%d" % root.get_multiplayer().get_unique_id())
	else:
		print("[B] 连接失败（等待 %d 帧）" % waited)
		quit(1)
		return

	# 移动一下，发送状态
	Input.action_press("move_forward")
	for i in 90:
		await physics_frame
	Input.action_release("move_forward")
	for i in 90:
		await physics_frame

	# 打印当前快照
	var my_id := root.get_multiplayer().get_unique_id()
	print("[B] my_id=%d players=%s" % [my_id, str(game.net.players.keys())])
	for pid in game.net.players:
		if pid != my_id:
			print("[B] 看到 A: pid=%d pos=%s" % [pid, game.net.players[pid].get("pos")])

	# 聊天测试：B 发一条，并收集收到的所有聊天（应含 A 的回复）
	var recv: Array = []
	game.net.chat_received.connect(func(pname, text): recv.push_back([pname, text]); print("[B] 收到聊天 [%s] %s" % [pname, text]))
	game.net.send_chat("哞~来自B的问候")

	# 全局事件测试：打印收到的事件（A 会在稍后广播）
	game.net.game_event_received.connect(func(data): print("[B] 收到事件 %s" % str(data)))
	game.net.send_game_event({"type": "ko", "attacker": "客户端B", "victim": "虚空"})
	for i in 400:
		await physics_frame

	quit(0)
