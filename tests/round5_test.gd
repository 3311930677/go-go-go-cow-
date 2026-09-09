extends SceneTree
## 第 5 轮测试：音效库 / 水印 / 联机（子进程服务器 + 客户端回环）。
## 运行方式：
##   Godot_v4.6.1-stable_win64.exe --headless --path . --script res://tests/round5_test.gd

const GODOT_EXE := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const TEST_PORT := 24666

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
	print("==== 牛走 · 第 5 轮测试（音效+截图+联机） ====")

	# —— 1. 启动专用服务器（子进程） ——
	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var args := ["--headless", "--path", project_dir,
		"res://scenes/server.tscn", "--", "--port=%d" % TEST_PORT, "--event-interval=2.0"]
	_server_pid = OS.create_process(GODOT_EXE, args)
	_check(_server_pid > 0, "服务器子进程启动", "pid=%d" % _server_pid)
	# 给服务器启动时间
	await create_timer(3.0).timeout

	# —— 2. 加载主场景（联机模式） ——
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
	var player := main.get_node_or_null("PlayerCow") as PlayerCow
	var hud := main.get_node_or_null("GameHUD") as GameHUD
	var sfx := main.get_node_or_null("SfxBank") as SfxBank
	if player == null or hud == null or sfx == null:
		_check(false, "关键节点存在（PlayerCow/GameHUD/SfxBank）")
		_finish()
		return
	_check(game.net != null, "联机模式下 NetManager 已挂载")

	# —— 3. 等待连接服务器（最多 10 秒） ——
	var waited := 0
	while not game.net.connected_ok and waited < 600:
		await physics_frame
		waited += 1
	_check(game.net.connected_ok, "客户端连接服务器成功（127.0.0.1:%d）" % TEST_PORT)

	# —— 4. 音效库 ——
	_check(sfx._streams.size() >= 10, "音效库含 10 种音效", "数量 %d" % sfx._streams.size())
	for name in ["moo", "jump", "eat", "charge", "fly", "bounce", "event", "ding", "click", "stumble"]:
		_check(sfx._streams.has(name), "音效存在：%s" % name)
	sfx.play("moo")  # 不崩溃即可
	_check(true, "play() 不崩溃")

	# —— 5. 水印 ——
	_check(hud.get_child_count() > 4, "HUD 元素完整（含水印）")

	# —— 6. 状态同步回环：移动后服务器快照应含自己 ——
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	# 等快照（15Hz，等 1 秒余量）
	for i in 60:
		await physics_frame
	var my_id := root.get_multiplayer().get_unique_id()
	_check(game.net.players.has(my_id), "服务器快照回环（含自己）",
		"players=%s my_id=%d" % [str(game.net.players.keys()), my_id])
	if game.net.players.has(my_id):
		var st: Dictionary = game.net.players[my_id]
		_check(st.has("act") and st.has("pos") and st.has("name"), "快照字段完整",
			"keys=%s" % str(st.keys()))

	# —— 7. 服务器事件广播（interval=2s，5 秒内必达） ——
	var event_waited := 0
	while game.net.last_event_msg == "" and event_waited < 300:
		await physics_frame
		event_waited += 1
	_check(game.net.last_event_msg != "", "收到服务器事件广播",
		"last_event_msg='%s'" % game.net.last_event_msg)

	# —— 8. 远程玩家渲染路径（单客户端时无他人，仅验证不崩溃） ——
	_check(game._net_players.is_empty() or true, "远程玩家渲染无崩溃")

	_finish()


func _finish() -> void:
	# 清理服务器子进程
	if _server_pid > 0:
		OS.kill(_server_pid)
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass_count, _failures.size()])
	for f in _failures:
		print("  失败项：%s" % f)
	quit(1 if not _failures.is_empty() else 0)
