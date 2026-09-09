extends SceneTree
## 第 9 轮测试：标题画面重做（按钮全部可见/容器布局）+ 联机弹窗 + 设置返回主菜单
## + 聊天面板重做 + 模式简介卡 + 离线 T 键提示
## 运行：Godot --headless --path D:\牛来 --script res://tests/round9_test.gd

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


func _reset(mode: String) -> void:
	ModeConfig.mode = mode
	NetConfig.enabled = false
	NetConfig.player_name = ""


func _run() -> void:
	print("==== 牛走 · 第 9 轮测试（UI 大修：标题/聊天/简介/退出） ====")

	# ============ A. 标题画面：所有按钮都在屏幕内 ============
	var title: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await create_timer(0.8).timeout
	var vp := root.get_visible_rect().size
	var buttons: Array = []
	_collect_buttons(title, buttons)
	_check(buttons.size() >= 10, "标题：按钮数量（开始/联机/设置/5模式/连接/取消）", str(buttons.size()))
	var all_inside := true
	var offscreen := ""
	for b in buttons:
		var rect: Rect2 = (b as Control).get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 \
				or rect.position.x + rect.size.x > vp.x + 1.0 \
				or rect.position.y + rect.size.y > vp.y + 1.0:
			all_inside = false
			offscreen += "%s@%s " % [(b as Control).name, str(rect.position)]
	_check(all_inside, "标题：所有按钮完整显示在屏幕内", offscreen)
	var start_btns := title.find_children("StartButton", "Button", true, false)
	_check(start_btns.size() == 1, "标题：开始按钮（StartButton）存在", str(start_btns.size()))

	# 悬停简介标签存在
	var has_desc := false
	for c in title.find_children("*", "Label", true, false):
		if (c as Label).text.find("悬停") != -1:
			has_desc = true
	_check(has_desc, "标题：模式悬停简介提示存在")

	# 联机弹窗：默认隐藏，可切换
	var panel: Control = title.get("_online_panel") if title.get("_online_panel") != null else null
	_check(panel != null and not panel.visible, "联机：弹窗默认隐藏")
	title.call("_toggle_online_panel")
	await create_timer(0.1).timeout
	_check(panel.visible, "联机：点击后弹窗打开")
	# 弹窗内输入框存在（牛名/IP/端口）
	var edits: Array = []
	_collect_edits(title, edits)
	_check(edits.size() >= 3, "联机：弹窗含 牛名/IP/端口 输入框", str(edits.size()))
	# 弹窗面板居中且完整显示在屏幕内（曾因 PRESET_CENTER 偏到右下角）
	await create_timer(0.2).timeout
	var vp2 := root.get_visible_rect().size
	var boxes: Array = title.find_children("*", "PanelContainer", true, false)
	var box_ok := false
	var box_detail := "no box"
	for b in boxes:
		if not (b as Control).is_visible_in_tree():
			continue
		var r: Rect2 = (b as Control).get_global_rect()
		var inside := r.position.x >= 0 and r.position.y >= 0 \
			and r.position.x + r.size.x <= vp2.x + 1.0 \
			and r.position.y + r.size.y <= vp2.y + 1.0
		var centered := absf((r.position.x + r.size.x * 0.5) - vp2.x * 0.5) <= vp2.x * 0.15
		box_detail = "r=%s vp=%s in=%s mid=%s" % [str(r), str(vp2), str(inside), str(centered)]
		box_ok = inside and centered
	_check(box_ok, "联机：弹窗居中且完整显示在屏幕内", box_detail)
	# 弹窗内 6 个模式选择按钮齐全
	_check(title.get("_online_mode_btns").size() == 6, "联机：弹窗含 6 个模式选择按钮",
		str(title.get("_online_mode_btns").size()))
	title.call("_toggle_online_panel")
	title.queue_free()
	await create_timer(0.5).timeout

	# ============ B. 单机模式：简介卡 + 离线 T 提示 ============
	_reset("battle")
	var game_b: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_b)
	await create_timer(1.5).timeout
	_check(game_b.intro != null and game_b.intro._shown, "简介卡：进入模式时显示")
	_check(game_b.intro._panel.get_child_count() >= 2, "简介卡：含遮罩与卡片")
	# 简介卡居中且完整显示在屏幕内（曾因 PRESET_CENTER 偏到右下角）
	var vp3 := root.get_visible_rect().size
	var intro_box: Control = null
	for b in game_b.intro.find_children("*", "PanelContainer", true, false):
		intro_box = b as Control
	if intro_box != null:
		var ir: Rect2 = intro_box.get_global_rect()
		var i_ok := ir.position.x >= 0 and ir.position.y >= 0 \
			and ir.position.x + ir.size.x <= vp3.x + 1.0 \
			and ir.position.y + ir.size.y <= vp3.y + 1.0 \
			and absf((ir.position.x + ir.size.x * 0.5) - vp3.x * 0.5) <= vp3.x * 0.15
		_check(i_ok, "简介卡：居中且完整显示在屏幕内",
			"r=%s vp=%s" % [str(ir), str(vp3)])
	else:
		_check(false, "简介卡：居中且完整显示在屏幕内", "PanelContainer 未找到")

	# 设置菜单面板也居中（曾因 PRESET_CENTER + 手写偏移随分辨率漂移）
	var esc_ev2 := InputEventAction.new()
	esc_ev2.action = "toggle_mouse"
	esc_ev2.pressed = true
	game_b._unhandled_input(esc_ev2)
	await create_timer(0.2).timeout
	var set_box: Control = null
	for b in game_b.settings.find_children("*", "PanelContainer", true, false):
		set_box = b as Control
	if set_box != null:
		var sr: Rect2 = set_box.get_global_rect()
		var s_ok := sr.position.x >= 0 and sr.position.y >= 0 \
			and sr.position.x + sr.size.x <= vp3.x + 1.0 \
			and sr.position.y + sr.size.y <= vp3.y + 1.0 \
			and absf((sr.position.x + sr.size.x * 0.5) - vp3.x * 0.5) <= vp3.x * 0.15
		_check(s_ok, "设置菜单：居中且完整显示在屏幕内",
			"r=%s vp=%s" % [str(sr), str(vp3)])
	else:
		_check(false, "设置菜单：居中且完整显示在屏幕内", "PanelContainer 未找到")
	game_b.settings.close_menu()
	await create_timer(0.2).timeout

	# 任意键关闭简介卡
	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = KEY_SPACE
	key_ev.pressed = true
	Input.parse_input_event(key_ev)
	await create_timer(0.3).timeout
	_check(not game_b.intro._shown, "简介卡：按任意键关闭")

	# 离线按 T：聊天框照样打开（发送时才注明只有自己可见）
	var t_ev := InputEventKey.new()
	t_ev.physical_keycode = KEY_T
	t_ev.pressed = true
	Input.parse_input_event(t_ev)
	await create_timer(0.3).timeout
	_check(game_b.chat.chat_open, "离线 T：聊天框照样打开")
	game_b.chat._input.text = "自言自语测试"
	game_b.chat.close(true)
	await create_timer(0.2).timeout
	var offline_self := false
	var offline_note := false
	for c in game_b.chat._log_box.get_children():
		var t := ""
		if c is Label:
			t = (c as Label).text
		elif c is RichTextLabel:
			t = (c as RichTextLabel).text
		if t.find("自言自语测试") != -1:
			offline_self = true
		if t.find("只有你自己能看到") != -1:
			offline_note = true
	_check(offline_self, "离线发送：消息本地显示")
	_check(offline_note, "离线发送：注明只有自己可见")

	# 灌 60 条消息：超过 50 条上限不死循环（曾因 queue_free 死循环内存拉满卡死）
	for i in 60:
		game_b.chat.push_system("压测消息 %d" % i)
	await create_timer(0.3).timeout
	_check(game_b.chat._log_box.get_child_count() == 50, "聊天：超过 50 条时数量钳制且不卡死",
		str(game_b.chat._log_box.get_child_count()))

	# 设置菜单：游戏内显示"返回主菜单"
	game_b.settings.open_menu(true)
	_check(game_b.settings.visible, "设置：ESC 菜单可打开")
	_check(game_b.settings.get("_quit_btn").visible, "设置：游戏内显示「返回主菜单」")
	game_b.settings.call("_quit_to_title")
	await create_timer(0.5).timeout
	_check(current_scene is TitleScreen, "退出：返回主菜单场景",
		str(current_scene.name) if current_scene != null else "null")
	game_b.queue_free()  # 手动挂载的场景不会被 change_scene 清掉
	await create_timer(0.5).timeout

	# ============ C. 联机：T 打开正经聊天面板 ============
	var srv_pid := OS.create_process("D:\\godot\\Godot_v4.6.1-stable_win64.exe", [
		"--headless", "--path", "D:\\牛来",
		"res://scenes/server.tscn", "--", "--port=24683", "--event-interval=999"
	])
	_check(srv_pid > 0, "测试服务器启动")
	await create_timer(3.0).timeout

	_reset("free")
	NetConfig.enabled = true
	NetConfig.server_ip = "127.0.0.1"
	NetConfig.server_port = 24683
	NetConfig.player_name = "聊天测试牛"
	var game_c: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game_c)
	await create_timer(3.0).timeout
	_check(game_c.net != null and game_c.net.connected_ok, "联机：连接成功")

	# 简介卡先关掉，再按 T
	Input.parse_input_event(key_ev)
	await create_timer(0.2).timeout
	Input.parse_input_event(t_ev)
	await create_timer(0.3).timeout
	_check(game_c.chat.chat_open, "联机 T：聊天框打开")
	_check(game_c.chat._input.visible and game_c.chat._panel.visible, "聊天：面板与输入框可见")
	# 面板与输入框必须真实落在屏幕内（曾因 position 负坐标飘到屏幕外：能打字但看不见框）
	var vp4 := root.get_visible_rect().size
	var prect: Rect2 = game_c.chat._panel.get_global_rect()
	var irect: Rect2 = game_c.chat._input.get_global_rect()
	_check(prect.position.x >= 0 and prect.position.y >= 0 \
		and prect.position.x + prect.size.x <= vp4.x + 1.0 \
		and prect.position.y + prect.size.y <= vp4.y + 1.0,
		"聊天：面板在屏幕内（左下角）",
		"r=%s vp=%s" % [str(prect), str(vp4)])
	_check(irect.position.x >= 0 and irect.position.y >= 0 \
		and irect.position.x + irect.size.x <= vp4.x + 1.0 \
		and irect.position.y + irect.size.y <= vp4.y + 1.0,
		"聊天：输入框在屏幕内（面板正下方）",
		"r=%s vp=%s" % [str(irect), str(vp4)])

	# 面板结构：滚动容器 + 消息历史
	_check(game_c.chat._scroll != null and game_c.chat._log_box != null, "聊天：滚动历史结构存在")

	# 发一条消息 → 面板出现带名字的记录
	game_c.chat._input.text = "正经聊天测试"
	game_c.chat.close(true)
	await create_timer(1.5).timeout
	var chat_text_ok := false
	for c2 in game_c.chat._log_box.get_children():
		var t2: String = (c2 as Control).get("text")
		if t2.find("聊天测试牛") != -1 and t2.find("正经聊天测试") != -1:
			chat_text_ok = true
	_check(chat_text_ok, "聊天：发送后历史显示「名字：内容」")

	# 系统播报
	game_c.chat.push_system("【测试】系统播报")
	await create_timer(0.2).timeout
	var sys_ok := false
	for c2 in game_c.chat._log_box.get_children():
		var t2: String = (c2 as Control).get("text")
		if t2.find("系统播报") != -1:
			sys_ok = true
	_check(sys_ok, "聊天：系统播报入列")
	game_c.queue_free()
	await create_timer(0.8).timeout
	OS.kill(srv_pid)

	# ============ D. 各模式简介卡文案 ============
	for m in ["free", "sumo", "survival", "quest", "race", "battle"]:
		var info: Dictionary = ModeConfig.info(m)
		_check(info.has("btn") and str(info["rules"]).length() > 10, "简介文案：%s" % m)

	_reset("free")
	_finish()


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button and c.visible and (c as Control).get_global_rect().size.x > 0:
			out.push_back(c)
		_collect_buttons(c, out)


func _collect_edits(node: Node, out: Array) -> void:
	for c in node.find_children("*", "LineEdit", true, false):
		out.push_back(c)


func _finish() -> void:
	var summary := "==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail]
	print(summary)
	var f := FileAccess.open("user://round9_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(summary)
		f.close()
	quit(1 if _fail > 0 else 0)
