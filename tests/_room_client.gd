extends SceneTree
## 多房间测试·子进程客户端：轻量 NetManager（无游戏场景），
## 连接后手动上报状态，把收到的快照/聊天/事件/模式写入 JSON 供主测试断言。
## 参数：--room=1 --mode=free --port=24690 --out=user://room_b.json


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := "1"
	var mode := "free"
	var port := 24690
	var out := "user://room_client.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			room = arg.get_slice("=", 1)
		elif arg.begins_with("--mode="):
			mode = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			out = arg.get_slice("=", 1)

	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = port
	NetConfig.room_id = room
	NetConfig.player_name = "客户端" + room
	ModeConfig.mode = mode

	# RPC 节点路径必须与服务器一致：/root/Main/NetManager
	var holder := Node.new()
	holder.name = "Main"
	root.add_child(holder)
	var net := NetManager.new()
	net.name = "NetManager"
	holder.add_child(net)

	var res := {
		"connected": false, "mode": "", "saw_other": false,
		"chat_from_a": false, "room_full": false,
		"snapshot_size": 0, "chats": [],
	}
	var modes: Array = []
	var chats: Array = []
	var events: Array = []
	net.mode_received.connect(func(m): modes.push_back(m))
	net.chat_received.connect(func(pname, text): chats.push_back([pname, text]))
	net.game_event_received.connect(func(data): events.push_back(data))

	# 等连接（最长 10 秒）
	var waited := 0
	while not net.connected_ok and waited < 600:
		await physics_frame
		waited += 1
	res["connected"] = net.connected_ok
	if not net.connected_ok:
		_write(out, res)
		quit(1)
		return

	# 持续上报状态 ~8 秒（保持在房间快照里），期间收聊天/事件
	var t := 0.0
	while t < 8.0:
		await physics_frame
		t += 1.0 / 60.0
		if fmod(t, 0.08) < 0.02:  # ~15Hz
			net.submit_state.rpc_id(1, Vector3(t, 1.0, 0.0), 0.0, "run", "客户端" + room)
	# 发条本房间标记聊天
	net.send_chat("房间%s专用" % room)
	await create_timer(1.5).timeout

	var my_id := root.get_multiplayer().get_unique_id()
	for pid in net.players:
		if pid != my_id:
			res["saw_other"] = true
	res["snapshot_size"] = net.players.size()
	res["mode"] = modes[0] if modes.size() > 0 else ""
	for c in chats:
		(res["chats"] as Array).append("%s:%s" % [c[0], c[1]])
		if c[1] == "A房消息":
			res["chat_from_a"] = true
	for e in events:
		if e.get("type", "") == "room_full":
			res["room_full"] = true
	_write(out, res)
	quit(0)


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
