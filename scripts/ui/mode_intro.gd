class_name ModeIntro
extends CanvasLayer
## 模式简介卡：进入任何模式时弹出——模式名 + 规则说明 + 按任意键继续。
## 不暂停游戏（联机不能暂停），只吃掉第一下按键用来关闭自己。

const TITLE_TEXT := {
	"free": "草 原 梦 境",
	"sumo": "牛 牛 相 扑",
	"survival": "天 降 正 义",
	"quest": "特 性 复 刻",
	"race": "飞 天 竞 速",
	"battle": "哞 哞 大 逃 杀",
}

var _panel: Control
var _shown := false


func _ready() -> void:
	layer = 25
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)


## 展示某模式的简介卡
func show_intro(mode_key: String) -> void:
	var info: Dictionary = ModeConfig.info(mode_key)
	var title_text: String = TITLE_TEXT.get(mode_key, "草 原 梦 境")

	# 半透明遮罩（游戏在后面继续跑）
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(dim)

	# 真正的居中容器（PRESET_CENTER 只把锚点放中心，卡片本身会往右下偏出屏幕）
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(center)

	# 居中卡片（PanelContainer 自适应内容，不会溢出）
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.09)
	style.border_color = Color(0.9, 0.85, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 40.0
	style.content_margin_right = 40.0
	style.content_margin_top = 30.0
	style.content_margin_bottom = 26.0
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(560, 0)
	box.add_child(col)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.98, 0.9, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var rules := Label.new()
	rules.text = str(info.get("rules", ""))
	rules.add_theme_font_size_override("font_size", 17)
	rules.add_theme_color_override("font_color", Color(0.92, 0.9, 0.85))
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(rules)

	var hint := Label.new()
	hint.text = "按任意键继续"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	_panel.visible = true
	_shown = true


func _unhandled_input(event: InputEvent) -> void:
	if not _shown:
		return
	# T（聊天）：关简介卡但不吞事件，让 game.gd 直接打开聊天框
	if event.is_action_pressed("chat"):
		_dismiss(false)
		return
	# 任意按键/点击关闭（吃掉这一下，防止误触 ESC 等）
	if event is InputEventKey and event.pressed and not event.echo:
		_dismiss()
	elif event is InputEventMouseButton and event.pressed:
		_dismiss()


func _dismiss(consume := true) -> void:
	_shown = false
	_panel.visible = false
	_panel.queue_free()
	if consume:
		get_viewport().set_input_as_handled()
