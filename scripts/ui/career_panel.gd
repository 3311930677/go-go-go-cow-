class_name CareerPanel
extends CanvasLayer
## 生涯面板：统计数字 + 成就墙（解锁金色 / 未解锁灰色带进度）。
## 从标题画面或设置菜单打开——不做游戏内热键（避免和 ESC / 地图 / 聊天打架）。

signal closed

var career: Career  # 数据源（game.gd / title_screen 注入）

var _panel: Control
var _subtitle: Label
var _stats_grid: GridContainer
var _ach_list: VBoxContainer
var _close_btn: Button


func _ready() -> void:
	layer = 35  # 地图(30)、设置(20) 之上——盖住一切看生涯
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	if career == null:
		return
	refresh()
	visible = true
	_close_btn.grab_focus()  # 拦住移动键（cow.gd 检测焦点属主）


func close_panel() -> void:
	visible = false
	closed.emit()


## 重建全部内容（打开时调用）
func refresh() -> void:
	if career == null:
		return
	# —— 统计格 ——
	for c in _stats_grid.get_children():
		_stats_grid.remove_child(c)
		c.queue_free()
	for line in career.summary_lines():
		var lbl := Label.new()
		lbl.text = "· " + str(line)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
		_stats_grid.add_child(lbl)
	# —— 成就墙 ——
	for c in _ach_list.get_children():
		_ach_list.remove_child(c)
		c.queue_free()
	for ach in career.achievement_list():
		_ach_list.add_child(_make_ach_row(ach))
	_subtitle.text = "成就 %d/%d ——（数字毫无意义，但牛都爱看）" % [career.unlocked_count(), Career.ACHIEVEMENTS.size()]


func _make_ach_row(ach: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# 状态块：解锁金色 / 未解锁灰
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(14, 14)
	chip.color = Color(1.0, 0.82, 0.25) if ach["unlocked"] else Color(0.35, 0.33, 0.3)
	row.add_child(chip)

	var txt := Label.new()
	if ach["unlocked"]:
		txt.text = "「%s」%s" % [ach["name"], ach["desc"]]
		txt.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	else:
		txt.text = "「%s」%s（%s）" % [ach["name"], ach["desc"], ach["progress"]]
		txt.add_theme_color_override("font_color", Color(0.55, 0.53, 0.5))
	txt.add_theme_font_size_override("font_size", 16)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	return row


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # 挡住背后的游戏输入
	add_child(_panel)

	# 遮罩
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(center)

	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.09)
	style.border_color = Color(0.75, 0.62, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 30.0
	style.content_margin_right = 30.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	box.add_child(col)

	var title := Label.new()
	title.text = "生 涯 与 成 就"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_subtitle)

	# —— 统计：3 列网格 ——
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 3
	_stats_grid.add_theme_constant_override("h_separation", 26)
	_stats_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(_stats_grid)

	# —— 成就墙：可滚动 ——
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 7)
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ach_list)

	# —— 关闭 ——
	_close_btn = Button.new()
	_close_btn.text = "回 到 游 戏"
	_close_btn.add_theme_font_size_override("font_size", 17)
	_close_btn.add_theme_color_override("font_color", Color.WHITE)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.22, 0.20, 0.18)
	btn_style.set_corner_radius_all(0)
	btn_style.content_margin_left = 24.0
	btn_style.content_margin_right = 24.0
	btn_style.content_margin_top = 8.0
	btn_style.content_margin_bottom = 8.0
	_close_btn.add_theme_stylebox_override("normal", btn_style)
	_close_btn.add_theme_stylebox_override("hover", btn_style)
	_close_btn.add_theme_stylebox_override("pressed", btn_style)
	_close_btn.pressed.connect(close_panel)
	col.add_child(_close_btn)
