class_name SettingsMenu
extends CanvasLayer
## 设置菜单：音量滑条 + 画质"灾难级 / 更灾难级"。
## 刻意只有两个画质档——本作的画质没有"好"这个选项。

signal closed
signal career_requested  # 点「生涯与成就」——由 game.gd / title_screen 接手打开面板

const SAVE_PATH := "user://settings.cfg"

var _panel: Control
var _vol_slider: HSlider
var _vol_label: Label
var _qrow: HBoxContainer
var _quality := 0  # 0=灾难级 1=更灾难级
var _close_btn: Button
var _quit_btn: Button  # 游戏内显示：返回主菜单
var _in_game := false  # 游戏内呼出（按钮文案"回到游戏"）vs 标题画面（"关 闭"）


static func load_settings() -> Dictionary:
	## 返回 {volume: int, quality: int}；无存档给默认值
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return {
			"volume": int(cfg.get_value("audio", "volume", 80)),
			"quality": int(cfg.get_value("video", "quality", 0)),
		}
	return {"volume": 80, "quality": 0}


static func apply_volume(v: int) -> void:
	var bus := 0  # Master
	var linear := clampf(v / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(bus, linear <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.001)))


static func apply_quality(q: int) -> void:
	# 0=灾难级（本来就是） 1=更灾难级（3D 分辨率减半，锯齿与糊感翻倍）
	var scale := 1.0 if q == 0 else 0.5
	Engine.max_fps = 0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = scale


func _ready() -> void:
	layer = 20
	_build()
	var s := load_settings()
	_set_quality(s.quality, false)
	_set_volume(s.volume, false)
	visible = false


## 打开（in_game=true 时按钮显示"回到游戏"，并显示"返回主菜单"）
func open_menu(in_game: bool) -> void:
	_in_game = in_game
	_close_btn.text = "回 到 游 戏" if in_game else "关 闭"
	_quit_btn.visible = in_game
	visible = true
	_close_btn.grab_focus()  # 顺带拦住移动键（cow.gd 检测焦点属主）


func close_menu() -> void:
	visible = false
	closed.emit()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", int(_vol_slider.value))
	cfg.set_value("video", "quality", _quality)
	cfg.save(SAVE_PATH)


func _set_volume(v: int, save: bool) -> void:
	_vol_slider.value = v
	_vol_label.text = "音量：%d%%" % v
	apply_volume(v)
	if save:
		_save()


func _set_quality(q: int, save: bool) -> void:
	_quality = q
	apply_quality(q)
	# 按钮高亮：选中的那个亮一点
	for btn in _qrow.get_children():
		if btn is Button:
			btn.modulate = Color(1.3, 1.3, 1.3) if btn.get_meta("q", -1) == q else Color.WHITE
	if save:
		_save()


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	# —— 半透明黑底（挡住游戏画面，但你知道它还在） ——
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)

	# —— 真正的居中容器（PRESET_CENTER + 手写偏移会随分辨率漂移） ——
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(center)

	# —— 中央面板：纯色方块（无圆角，简陋是特性） ——
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.11)
	style.set_corner_radius_all(0)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 26.0
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	box.add_child(col)

	# 标题
	var title := Label.new()
	title.text = "设 置"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# —— 音量 ——
	var vol_title := Label.new()
	vol_title.text = "音 量（调大了也一样难听）"
	vol_title.add_theme_font_size_override("font_size", 16)
	vol_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(vol_title)

	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0
	_vol_slider.max_value = 100
	_vol_slider.step = 1
	_vol_slider.custom_minimum_size = Vector2(300, 24)
	_vol_slider.value_changed.connect(func(_v: float): _set_volume(int(_v), true))
	col.add_child(_vol_slider)

	_vol_label = Label.new()
	_vol_label.add_theme_font_size_override("font_size", 15)
	_vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_vol_label)

	# —— 画质 ——
	var q_title := Label.new()
	q_title.text = "画 质（没有「好」这个选项）"
	q_title.add_theme_font_size_override("font_size", 16)
	q_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(q_title)

	var qrow := HBoxContainer.new()
	qrow.name = "QualityRow"
	qrow.add_theme_constant_override("separation", 14)
	qrow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(qrow)
	_qrow = qrow

	var q1 := _make_block_button("灾 难 级")
	q1.set_meta("q", 0)
	q1.pressed.connect(func(): _set_quality(0, true))
	qrow.add_child(q1)

	var q2 := _make_block_button("更灾难级")
	q2.set_meta("q", 1)
	q2.pressed.connect(func(): _set_quality(1, true))
	qrow.add_child(q2)

	var q_hint := Label.new()
	q_hint.text = "更灾难级 = 3D 分辨率减半。你确定要更灾难吗？"
	q_hint.add_theme_font_size_override("font_size", 13)
	q_hint.modulate = Color(0.75, 0.73, 0.7)
	q_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(q_hint)

	# —— 生涯与成就（看数字吹牛用） ——
	var career_btn := _make_block_button("生 涯 与 成 就")
	career_btn.pressed.connect(func(): career_requested.emit())
	col.add_child(career_btn)

	# —— 返回主菜单（仅游戏内：从任何模式退回标题画面） ——
	_quit_btn = _make_block_button("返 回 主 菜 单")
	_quit_btn.visible = false
	_quit_btn.pressed.connect(_quit_to_title)
	col.add_child(_quit_btn)

	# —— 关闭 ——
	_close_btn = _make_block_button("关 闭")
	_close_btn.pressed.connect(close_menu)
	col.add_child(_close_btn)


## 退出当前模式，回到标题画面
func _quit_to_title() -> void:
	visible = false
	NetConfig.enabled = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _make_block_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(0.9, 0.9, 0.9))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.20, 0.18)
	style.set_corner_radius_all(0)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)
	return b


func _unhandled_input(event: InputEvent) -> void:
	# 游戏内按 ESC 直接关闭
	if visible and event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
