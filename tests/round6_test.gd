extends SceneTree
## 第 6 轮测试：改名"牛走" + 聊天框 + 设置菜单
## 运行：Godot --headless --path D:\牛来 --script res://tests/round6_test.gd

const GODOT := "D:\\godot\\Godot_v4.6.1-stable_win64.exe"
const PROJECT_PATH := "D:\\牛来"
const CHAT_PORT := 24680

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
	print("==== 牛走 · 第 6 轮测试（改名+聊天+设置） ====")

	# ———— 1. 项目名 ————
	_check(ProjectSettings.get_setting("application/config/name") == "牛走", "项目名已改为「牛走」",
		ProjectSettings.get_setting("application/config/name"))

	# ———— 2. 标题画面文字 ————
	var title_scene: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title_scene)
	await process_frame
	var title_ok := false
	for child in title_scene.find_children("*", "Label", true, false):
		if child is Label and (child as Label).text == "牛 走":
			title_ok = true
	_check(title_ok, "标题画面显示「牛 走」")
	title_scene.queue_free()
	await process_frame

	# ———— 3. 游戏场景：HUD 水印 / 聊天框 / 设置菜单 ————
	NetConfig.enabled = false
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1.5).timeout

	var hud = game.hud
	var wm_ok := false
	for child in hud.get_children():
		if child is Label and "牛走" in (child as Label).text:
			wm_ok = true
	_check(wm_ok, "HUD 水印含「牛走」")

	# ———— 4. 设置菜单：音量 / 画质 / 持久化 ————
	var settings = game.settings
	_check(settings != null and not settings.visible, "设置菜单存在且默认隐藏")

	settings._set_volume(50, false)
	var expect_db := linear_to_db(0.5)
	_check(absf(AudioServer.get_bus_volume_db(0) - expect_db) < 0.01, "音量 50% → 总线分贝正确",
		"db=%f expect=%f" % [AudioServer.get_bus_volume_db(0), expect_db])

	settings._set_quality(1, false)
	_check(absf(root.scaling_3d_scale - 0.5) < 0.001, "更灾难级 → 3D 分辨率减半",
		"scale=%f" % root.scaling_3d_scale)
	settings._set_quality(0, true)
	_check(absf(root.scaling_3d_scale - 1.0) < 0.001, "灾难级 → 3D 分辨率恢复")

	var s2: Dictionary = SettingsMenu.load_settings()
	_check(s2.get("quality", -1) == 0, "设置持久化（quality=0 回读）", str(s2))

	# ———— 5. ESC 呼出设置 / 关闭 ————
	var esc_ev := InputEventAction.new()
	esc_ev.action = "toggle_mouse"
	esc_ev.pressed = true
	game._unhandled_input(esc_ev)
	_check(settings.visible, "ESC 呼出设置菜单")
	settings.close_menu()
	await process_frame
	_check(not settings.visible, "设置菜单可关闭")

	# ———— 6. 聊天框：消息上屏 / 打字门控 / 发送信号 ————
	var chat = game.chat
	_check(chat != null, "聊天框已挂载")
	chat.push_message("哞王42", "大家好")
	await process_frame
	_check(chat._log_box.get_child_count() == 1, "聊天消息上屏")

	chat.open()
	await process_frame
	_check(chat.chat_open, "Enter 打开聊天输入框")
	_check(game.player._input_blocked(), "打字时小牛输入被拦截")
	chat._input.text = "哞——测试"
	var submitted: Array = []
	chat.chat_submitted.connect(func(t): submitted.push_back(t))
	chat.close(true)
	await process_frame
	_check(submitted.size() == 1 and submitted[0] == "哞——测试", "Enter 发送聊天（信号携带文本）", str(submitted))
	_check(not chat.chat_open and not game.player._input_blocked(), "关闭聊天后恢复控制")

	game.queue_free()
	await create_timer(1.0).timeout

	# ———— 7. 联机聊天：本地服务器回环 ————
	_srv_pid = OS.create_process(GODOT, [
		"--headless", "--path", PROJECT_PATH,
		"res://scenes/server.tscn", "--", "--port=%d" % CHAT_PORT, "--event-interval=999"
	])
	_check(_srv_pid > 0, "聊天测试服务器启动")
	await create_timer(3.0).timeout

	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = CHAT_PORT
	var game2: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game2)
	await create_timer(3.0).timeout
	_check(game2.net != null and game2.net.connected_ok, "客户端连接成功")

	var recv: Array = []
	game2.net.chat_received.connect(func(pname, text): recv.push_back([pname, text]))
	await create_timer(1.0).timeout  # 先让状态上报注册名字
	game2.net.send_chat("哞——联机测试")
	await create_timer(2.0).timeout

	var chat_ok := false
	var chat_detail := str(recv)
	for item in recv:
		if item[1] == "哞——联机测试" and item[0] == game2.net.my_name:
			chat_ok = true
	_check(chat_ok, "聊天回环：发送→服务器广播→收到自己的名字与文本", chat_detail)
	_check(game2.chat._log_box.get_child_count() >= 1, "联机聊天消息显示到列表")

	# ———— 收尾：恢复默认设置，避免污染后续回归 ————
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", 80)
	cfg.set_value("video", "quality", 0)
	cfg.save(SettingsMenu.SAVE_PATH)

	game2.queue_free()
	_finish()


func _finish() -> void:
	if _srv_pid > 0:
		OS.kill(_srv_pid)
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
