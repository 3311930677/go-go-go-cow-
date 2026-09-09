class_name TitleScreen
extends Control
## 标题画面：刻意唯美的"国风水墨"背景 + 简陋到极致的方块按钮。
## 布局全部走容器（VBox/HBox）——任何窗口尺寸下都不会溢出/出屏。
## 模式按钮悬停显示一句话简介；联机面板是带遮罩的正经弹窗。

signal start_requested

var _sfx: SfxBank
var _online_panel: Control
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _room_edit: LineEdit
var _name_edit: LineEdit
var _settings_menu: SettingsMenu
var _desc_label: Label
var _career: Career
var _career_panel: CareerPanel
var _online_mode := "free"
var _online_mode_btns: Dictionary = {}

## 联机弹窗里的模式短标签（主按钮文案太长，选择器用短版）
const ONLINE_MODE_TAGS := {
	"free": "自由草原",
	"sumo": "牛牛相扑",
	"survival": "天降正义",
	"quest": "特性复刻",
	"race": "飞天竞速",
	"battle": "大逃杀",
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	queue_redraw()  # 绘制水墨背景（Control 自身绘制层，位于子节点之下）

	# —— 音效 ——
	_sfx = SfxBank.new()
	add_child(_sfx)

	# —— 主布局：全屏 VBox ——
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)

	# —— 标题 ——
	var title := Label.new()
	title.text = "牛 走"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.13, 0.12, 0.11))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# —— 副标题 ——
	var sub := Label.new()
	sub.text = "耗时 N 年 · 两人团队手搓的 3A 级（物理）大作"
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color(0.32, 0.3, 0.28))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(_spacer())

	# —— 主按钮：开始（free）/ 联机 / 设置 ——
	var start_btn := _make_block_button(ModeConfig.MODE_INFO["free"]["btn"], 24, 280)
	start_btn.name = "StartButton"
	start_btn.pressed.connect(_on_start)
	col.add_child(start_btn)

	var online_btn := _make_block_button("联 机 草 原", 20, 280)
	online_btn.pressed.connect(_toggle_online_panel)
	col.add_child(online_btn)

	var settings_btn := _make_block_button("设　　置", 20, 280)
	settings_btn.pressed.connect(_on_settings)
	col.add_child(settings_btn)

	# —— 生涯与成就：看看这些年的草都吃到哪去了 ——
	var career_btn := _make_block_button("生　　涯", 20, 280)
	career_btn.pressed.connect(_on_career)
	col.add_child(career_btn)

	# —— 分隔语 ——
	var sep := Label.new()
	sep.text = "── 或者，换个姿势做梦 ──"
	sep.add_theme_font_size_override("font_size", 15)
	sep.add_theme_color_override("font_color", Color(0.5, 0.48, 0.45))
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sep)

	# —— 模式按钮行（自动宽度，永不溢出） ——
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(mode_row)
	for m in ["sumo", "survival", "quest", "race", "battle"]:
		var mb := _make_block_button(ModeConfig.MODE_INFO[m]["btn"], 17, 0)
		mb.pressed.connect(_on_mode_button.bind(m))
		mb.mouse_entered.connect(_set_desc.bind(ModeConfig.MODE_INFO[m]["short"]))
		mb.mouse_exited.connect(_set_desc.bind(""))
		mode_row.add_child(mb)

	# —— 悬停简介（固定高度，内容变化不跳动） ——
	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 14)
	_desc_label.add_theme_color_override("font_color", Color(0.42, 0.4, 0.37))
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.custom_minimum_size = Vector2(0, 22)
	_desc_label.text = "把鼠标悬停在模式按钮上，看看它们都是什么牛"
	col.add_child(_desc_label)

	col.add_child(_spacer())

	# —— 底部小字 ——
	var foot := Label.new()
	foot.text = "在 AI 盛行的今天，依然有老抽象专家坚持手搓。"
	foot.add_theme_font_size_override("font_size", 14)
	foot.add_theme_color_override("font_color", Color(0.45, 0.43, 0.4))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)

	# —— 联机弹窗（默认隐藏，带遮罩 + 居中面板） ——
	_build_online_panel()

	# 回车也能开始
	start_btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# 生涯面板开着——先看完数字再说，回车不开始游戏
	if _career_panel != null and _career_panel.visible:
		return
	if event.is_action_pressed("ui_accept") and not _online_panel.visible and not _settings_open():
		_on_start()
	elif _online_panel.visible and event.is_action_pressed("ui_cancel"):
		_toggle_online_panel()


func _on_start() -> void:
	_sfx.play("click")
	NetConfig.enabled = false  # 单机梦境
	ModeConfig.mode = "free"
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## 新模式按钮：单机进入对应模式
func _on_mode_button(m: String) -> void:
	_sfx.play("click")
	NetConfig.enabled = false
	ModeConfig.mode = m
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## 悬停简介（空串恢复默认提示）
func _set_desc(text: String) -> void:
	if _desc_label == null:
		return
	_desc_label.text = text if text != "" else "把鼠标悬停在模式按钮上，看看它们都是什么牛"


## 牛名修改即保存（下次联机自动带上）
func _on_name_changed(_new_text: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsMenu.SAVE_PATH)  # 无存档时忽略错误，直接写入
	cfg.set_value("net", "name", _name_edit.text.strip_edges())
	cfg.save(SettingsMenu.SAVE_PATH)


func _toggle_online_panel() -> void:
	_sfx.play("click")
	_online_panel.visible = not _online_panel.visible


## 设置菜单（标题画面版：按钮文案"关闭"）
func _on_settings() -> void:
	_sfx.play("click")
	if _settings_menu == null:
		_settings_menu = SettingsMenu.new()
		add_child(_settings_menu)
		_settings_menu.career_requested.connect(_on_career)  # 设置里也能看生涯
	_settings_menu.open_menu(false)


## 生涯面板（懒加载：第一次点才建 Career 读档）
func _on_career() -> void:
	_sfx.play("click")
	if _career == null:
		_career = Career.new()
		add_child(_career)
	if _career_panel == null:
		_career_panel = CareerPanel.new()
		_career_panel.career = _career
		add_child(_career_panel)
	_career_panel.open_panel()


func _settings_open() -> bool:
	return _settings_menu != null and _settings_menu.visible


func _on_connect() -> void:
	_sfx.play("ding")
	NetConfig.enabled = true
	NetConfig.server_ip = _ip_edit.text.strip_edges()
	NetConfig.server_port = int(_port_edit.text.strip_edges()) if _port_edit.text.strip_edges().is_valid_int() else 24565
	NetConfig.player_name = _name_edit.text.strip_edges()
	NetConfig.room_id = _room_edit.text.strip_edges()
	ModeConfig.mode = _online_mode  # 想玩的模式上报服务器：先进房的第一头牛定，后进自动切
	# 房间号顺手存档（下次打开还在，方便和朋友约固定房）
	var cfg := ConfigFile.new()
	cfg.load(SettingsMenu.SAVE_PATH)
	cfg.set_value("net", "room", NetConfig.room_id)
	cfg.save(SettingsMenu.SAVE_PATH)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## 联机模式选择器：高亮当前选中
func _select_online_mode(m: String) -> void:
	_online_mode = m
	_sfx.play("click")
	for key in _online_mode_btns:
		var b: Button = _online_mode_btns[key]
		var sel: bool = str(key) == m
		b.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if sel else Color.WHITE)
		var style: StyleBoxFlat = (b.get_theme_stylebox("normal") as StyleBoxFlat)
		if style != null:
			style.bg_color = Color(0.45, 0.3, 0.1) if sel else Color(0.16, 0.14, 0.12)


# ————————————————— 联机弹窗 —————————————————

func _build_online_panel() -> void:
	_online_panel = Control.new()
	_online_panel.name = "OnlinePanel"
	_online_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_online_panel.visible = false
	add_child(_online_panel)

	# 遮罩：挡住背后的按钮
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.04, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_online_panel.add_child(dim)

	# 真正的居中容器（PRESET_CENTER 只把锚点放中心，控件本身会往右下偏出屏幕）
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_online_panel.add_child(center)

	# 居中面板（PanelContainer 随内容自适应大小）
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.94, 0.88)
	style.border_color = Color(0.2, 0.18, 0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 22.0
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)

	var title := Label.new()
	title.text = "联 机 草 原"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.15, 0.14, 0.12))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# —— 输入行工厂：标签 + 输入框 ——
	var mk_row := func(label_text: String, placeholder: String, width: float) -> LineEdit:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.25, 0.23, 0.2))
		row.add_child(lbl)
		var edit := LineEdit.new()
		edit.placeholder_text = placeholder
		edit.add_theme_font_size_override("font_size", 16)
		edit.max_length = 60
		edit.custom_minimum_size = Vector2(width, 32)
		row.add_child(edit)
		col.add_child(row)
		return edit

	_name_edit = mk_row.call("牛名：", "随机牛名", 240)
	_ip_edit = mk_row.call("服务器：", "play.simpfun.cn", 240)
	_ip_edit.text = "play.simpfun.cn"
	_port_edit = mk_row.call("端口：", "12699", 120)
	_port_edit.text = "12699"
	_room_edit = mk_row.call("房间号：", "1", 120)

	# —— 模式选择器：联机也能玩全部模式（先进房的第一头牛定，后进的自动切） ——
	var mode_lbl := Label.new()
	mode_lbl.text = "联机模式（先进房的牛决定，后进自动跟上）"
	mode_lbl.add_theme_font_size_override("font_size", 15)
	mode_lbl.add_theme_color_override("font_color", Color(0.25, 0.23, 0.2))
	mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(mode_lbl)

	# 两行 3+3：小窗口下也不会横向溢出
	var mode_rows: Array[HBoxContainer] = []
	for r in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(row)
		mode_rows.push_back(row)
	var btn_idx := 0
	for m in ONLINE_MODE_TAGS:
		var mb := _make_block_button(ONLINE_MODE_TAGS[m], 15, 0)
		mb.pressed.connect(_select_online_mode.bind(m))
		mode_rows[btn_idx / 3].add_child(mb)
		_online_mode_btns[m] = mb
		btn_idx += 1
	_select_online_mode("free")

	# 读回已保存的牛名 / 房间号
	var cfg := ConfigFile.new()
	if cfg.load(SettingsMenu.SAVE_PATH) == OK:
		_name_edit.text = str(cfg.get_value("net", "name", ""))
		_room_edit.text = str(cfg.get_value("net", "room", "1"))
	if _room_edit.text.strip_edges() == "":
		_room_edit.text = "1"
	_name_edit.text_changed.connect(_on_name_changed)

	# —— 连接 / 取消 ——
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)
	var connect_btn := _make_block_button("连 接", 18, 130)
	connect_btn.pressed.connect(_on_connect)
	btn_row.add_child(connect_btn)
	var cancel_btn := _make_block_button("取 消", 18, 130)
	cancel_btn.pressed.connect(_toggle_online_panel)
	btn_row.add_child(cancel_btn)


# ————————————————— 工具 —————————————————

## 弹性占位（把主按钮组推到视觉中部）
func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## 纯色方块按钮工厂：宽度自适应文字（min_w 只是下限），永不截断
func _make_block_button(text: String, font_size: int, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.95, 0.95, 0.9))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.8))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.14, 0.12)
	style.set_corner_radius_all(0)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)
	if min_w > 0.0:
		b.custom_minimum_size = Vector2(min_w, 0)
	return b


# ————————————————— 水墨背景（保持原味） —————————————————

## 程序化"水墨"：宣纸底色渐变 + 三座淡墨远山 + 白日 + 两笔飞鸟
func _draw() -> void:
	var vp := get_viewport_rect().size
	var ink := Color(0.16, 0.15, 0.14)
	var pale := Color(0.55, 0.53, 0.5)

	# 宣纸底：垂直多段渐变（手动画 60 条色带——够廉价也够"手工"）
	var paper_top := Color(0.97, 0.96, 0.92)
	var paper_bot := Color(0.9, 0.88, 0.82)
	var bands := 60
	for i in bands:
		var c := paper_top.lerp(paper_bot, float(i) / bands)
		var y0 := vp.y * i / bands
		var y1 := vp.y * (i + 1) / bands + 1.0
		draw_rect(Rect2(0, y0, vp.x, y1 - y0), c)

	# 白日（偏右上）
	draw_circle(Vector2(vp.x * 0.78, vp.y * 0.2), 56.0, Color(1.0, 0.99, 0.95))
	# 日晕
	draw_arc(Vector2(vp.x * 0.78, vp.y * 0.2), 64.0, 0.0, TAU, 48, Color(1, 0.99, 0.95, 0.5), 3.0)

	# 三座淡墨远山（近深远浅）
	var horizon := vp.y * 0.62
	_mountain(Vector2(0, horizon), vp.x * 0.55, vp.y * 0.30, Color(ink.r, ink.g, ink.b, 0.16))
	_mountain(Vector2(vp.x * 0.35, horizon), vp.x * 0.5, vp.y * 0.24, Color(ink.r, ink.g, ink.b, 0.26))
	_mountain(Vector2(vp.x * 0.6, horizon), vp.x * 0.55, vp.y * 0.18, Color(ink.r, ink.g, ink.b, 0.4))

	# 水面留白 + 一道淡墨波纹
	draw_line(Vector2(vp.x * 0.1, horizon + 40.0), Vector2(vp.x * 0.5, horizon + 40.0), Color(pale.r, pale.g, pale.b, 0.4), 2.0)
	draw_line(Vector2(vp.x * 0.3, horizon + 64.0), Vector2(vp.x * 0.75, horizon + 64.0), Color(pale.r, pale.g, pale.b, 0.28), 2.0)

	# 两笔飞鸟（V 字）
	var bird1 := Vector2(vp.x * 0.6, vp.y * 0.22)
	var bird2 := Vector2(vp.x * 0.66, vp.y * 0.26)
	draw_line(bird1 + Vector2(-14, 0), bird1, ink, 2.5)
	draw_line(bird1, bird1 + Vector2(14, -4), ink, 2.5)
	draw_line(bird2 + Vector2(-11, 0), bird2, ink, 2.0)
	draw_line(bird2, bird2 + Vector2(11, -3), ink, 2.0)

	# 左上一枚朱红印章（水墨画标配）
	var seal := Rect2(40.0, 40.0, 44.0, 44.0)
	draw_rect(seal, Color(0.72, 0.2, 0.16))
	var font := ThemeDB.fallback_font
	draw_string(font, seal.position + Vector2(7, 19), "牛", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.97, 0.95, 0.9))
	draw_string(font, seal.position + Vector2(7, 38), "走", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.97, 0.95, 0.9))


## 单座山：等腰三角 + 底部虚化（叠两层三角模拟墨晕）
func _mountain(base: Vector2, width: float, height: float, color: Color) -> void:
	var peak := base + Vector2(0, -height)
	var left := base + Vector2(-width * 0.5, 0)
	var right := base + Vector2(width * 0.5, 0)
	draw_polygon(PackedVector2Array([peak, left, right]), PackedColorArray([color, color, color]))
	# 墨晕层
	var color2 := Color(color.r, color.g, color.b, color.a * 0.5)
	var peak2 := peak + Vector2(width * 0.08, height * 0.12)
	draw_polygon(PackedVector2Array([peak2, left + Vector2(width * 0.06, 0), right - Vector2(width * 0.02, 0)]), PackedColorArray([color2, color2, color2]))
