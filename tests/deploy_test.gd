extends SceneTree
## 部署包验证：以"生产环境完全一致"的方式启动联机服务器——
## 不用源码 --path，而是 --main-pack game.pck + 位置参数场景 + 用户参数端口。
## 客户端连接，验证 连接/快照/事件 全链路。
## 运行方式：
##   Godot_v4.6.1-stable_win64.exe --headless --path D:\牛来 --script res://tests/deploy_test.gd

const GODOT_EXE := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const PCK_PATH := "D:/牛来/deploy/game.pck"
const TEST_PORT := 24677

var _failures: Array[String] = []
var _pass_count := 0
var _server_pid := -1


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
	print("==== 牛走 · 部署包验证（PCK 服务器，生产同款启动方式） ====")

	_check(FileAccess.file_exists(PCK_PATH), "game.pck 存在")
	if not FileAccess.file_exists(PCK_PATH):
		_finish()
		return

	# 与简幻欢 start.sh 完全一致的启动参数
	var args := ["--headless", "--main-pack", PCK_PATH, "res://scenes/server.tscn",
		"--", "--port=%d" % TEST_PORT, "--event-interval=2.0"]
	_server_pid = OS.create_process(GODOT_EXE, args)
	_check(_server_pid > 0, "PCK 服务器子进程启动", "pid=%d" % _server_pid)
	await create_timer(3.0).timeout

	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = TEST_PORT
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "主场景加载")
	if scene == null:
		_finish()
		return
	var main := scene.instantiate()
	root.add_child(main)
	var game = main
	_check(game.net != null, "联机模式下 NetManager 已挂载")

	var waited := 0
	while not game.net.connected_ok and waited < 600:
		await physics_frame
		waited += 1
	_check(game.net.connected_ok, "客户端连接 PCK 服务器成功")

	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	for i in 60:
		await physics_frame
	var my_id := root.get_multiplayer().get_unique_id()
	_check(game.net.players.has(my_id), "快照回环（含自己）")

	var event_waited := 0
	while game.net.last_event_msg == "" and event_waited < 300:
		await physics_frame
		event_waited += 1
	_check(game.net.last_event_msg != "", "收到服务器事件广播")

	_finish()


func _finish() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass_count, _failures.size()])
	for f in _failures:
		print("  失败项：%s" % f)
	quit(1 if not _failures.is_empty() else 0)
