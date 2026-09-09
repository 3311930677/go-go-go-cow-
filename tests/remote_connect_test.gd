extends SceneTree
## 公网连接验证：本机客户端直连简幻欢服务器 play.simpfun.cn:12699
## 运行：Godot --headless --path D:\牛来 --script res://tests/remote_connect_test.gd

const SERVER_IP := "play.simpfun.cn"
const SERVER_PORT := 12699

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


func _run() -> void:
	print("==== 公网连接验证：连 %s:%d ====" % [SERVER_IP, SERVER_PORT])

	# 先探测 UDP 端口是否有服务器在监听（ENet 创建 peer 不发包不会失败，只能靠真连接判断）
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "主场景加载")
	if scene == null:
		_finish()
		return

	NetConfig.enabled = true
	NetConfig.server_ip = SERVER_IP
	NetConfig.server_port = SERVER_PORT
	var main := scene.instantiate()
	root.add_child(main)
	var game = main
	_check(game.net != null, "NetManager 已挂载")

	print("等待连接（最长 20 秒）...")
	var waited := 0
	while not game.net.connected_ok and waited < 1200:
		await physics_frame
		waited += 1
	_check(game.net.connected_ok, "连接成功：%s:%d" % [SERVER_IP, SERVER_PORT],
		"等待了 %d 帧" % waited)

	if game.net.connected_ok:
		# 移动一下，验证状态同步链路
		Input.action_press("move_forward")
		for i in 60:
			await physics_frame
		Input.action_release("move_forward")
		for i in 90:
			await physics_frame
		var my_id := root.get_multiplayer().get_unique_id()
		_check(game.net.players.has(my_id), "快照回环（服务器在转发状态）")
		_check(game.net.players[my_id].get("pos", Vector3.ZERO) != Vector3.ZERO
			or game.net.players[my_id].get("pos", null) != null, "快照含坐标字段",
			str(game.net.players.get(my_id)))

	_finish()


func _finish() -> void:
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	print("[提示] 若连接失败：1) 面板是否已点启动 2) 面板分配端口是否确为 12699（游戏端口，非SFTP端口）")
	quit(1 if _fail > 0 else 0)
