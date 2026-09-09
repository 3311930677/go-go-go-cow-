class_name ChatBox
extends CanvasLayer
## 联机聊天面板（正经版）：半透明面板 + 滚动历史 + 名字配色。
## T 打开输入、Enter 发送、Esc 取消；关闭且无新消息 8 秒后整体淡出。
## 消息最多保留 50 条，打开时自动滚到底部。
## 注意：必须继承 CanvasLayer——Control 直接挂在 Game(Node3D) 下不渲染且尺寸为 0
## （曾有段时间"能打字但看不见任何框"就是这个原因）。

signal chat_submitted(text: String)

const PANEL_WIDTH := 440.0
const PANEL_HEIGHT := 200.0
const MAX_LINES := 50
const FADE_DELAY := 8.0  # 无活动多少秒后开始淡出

var chat_open := false

var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _log_box: VBoxContainer
var _input: LineEdit
var _idle := 0.0


func _ready() -> void:
	# 全屏根控件（CanvasLayer 里的 Control 以视口为父级，锚点/偏移才有意义）
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# —— 左下：聊天面板（背景 + 边框 + 滚动历史） ——
	# 偏移全部相对左下角锚点（position 是相对父容器左上角的绝对坐标，
	# 写负值会飘到屏幕上方之外）
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 12
	_panel.offset_top = -(PANEL_HEIGHT + 44)
	_panel.offset_right = PANEL_WIDTH + 12
	_panel.offset_bottom = -44
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.04, 0.55)
	style.border_color = Color(0.85, 0.82, 0.7, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_scroll)

	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_log_box)

	# —— 左下：输入框（默认隐藏；偏移同样相对左下角锚点） ——
	_input = LineEdit.new()
	_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_input.offset_left = 12
	_input.offset_top = -40
	_input.offset_right = PANEL_WIDTH + 12
	_input.offset_bottom = -10
	_input.add_theme_font_size_override("font_size", 15)
	_input.placeholder_text = "说点什么……（Enter 发送 / Esc 取消）"
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	_root.add_child(_input)


func _process(delta: float) -> void:
	if chat_open:
		return
	_idle += delta
	var alpha := 1.0 if _idle < FADE_DELAY else maxf(0.0, 1.0 - (_idle - FADE_DELAY) / 2.0)
	_panel.modulate.a = alpha
	if alpha <= 0.0:
		_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# Esc 关闭输入框（不发送）。注意：必须在 game.gd 的 ESC 处理之前吃到事件
	if chat_open and event.is_action_pressed("ui_cancel"):
		close(false)
		get_viewport().set_input_as_handled()


## 打开输入框（grab_focus 顺带拦住移动键——cow.gd 检测焦点属主）
func open() -> void:
	chat_open = true
	_idle = 0.0
	_panel.visible = true
	_panel.modulate.a = 1.0
	_input.visible = true
	_input.text = ""
	_input.grab_focus()
	_scroll_to_bottom()


## 关闭输入框；send=true 时把文本发出去
func close(send: bool) -> void:
	if send and _input.text.strip_edges() != "":
		chat_submitted.emit(_input.text.strip_edges())
		_idle = 0.0
	_input.text = ""
	_input.visible = false
	_input.release_focus()
	chat_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_submitted(text: String) -> void:
	close(true)


## 收到远端消息（game.gd 接 net.chat_received 后调这里）
func push_message(pname: String, text: String) -> void:
	var name_label := "[color=#%s]%s[/color]" % [_name_color(pname).to_html(false), pname]
	_push_line("%s：%s" % [name_label, _escape(text)], Color(1, 1, 0.85), true)


## 系统播报（KO/死亡/完赛等全局事件流——灰绿色，无名字）
func push_system(text: String) -> void:
	_push_line(text, Color(0.72, 0.85, 0.72))


## 最近是否有消息（供 HUD 提示用）
func has_activity() -> bool:
	return _idle < FADE_DELAY


# ————————————————— 内部 —————————————————

func _push_line(text: String, color: Color, bbcode := false) -> void:
	_idle = 0.0
	_panel.visible = true
	var label: Control
	if bbcode:
		var rich := RichTextLabel.new()
		rich.bbcode_enabled = true
		rich.fit_content = true
		rich.scroll_active = false
		rich.custom_minimum_size = Vector2(PANEL_WIDTH - 20.0, 0)
		rich.text = text
		label = rich
	else:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", color)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PANEL_WIDTH - 20.0, 0)
		l.text = text
		label = l
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_box.add_child(label)
	# 最多留 MAX_LINES 条（先 remove_child 再释放——queue_free 不会立刻移出树，
	# 直接 while 会死循环，内存拉满卡死）
	var excess := _log_box.get_child_count() - MAX_LINES
	for i in excess:
		var old := _log_box.get_child(0)
		_log_box.remove_child(old)
		old.queue_free()
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _scroll != null:
		_scroll.scroll_vertical = 1000000


## 名字 → 稳定配色（同名永远同色）
func _name_color(pname: String) -> Color:
	var h := float(pname.hash() % 360) / 360.0
	return Color.from_hsv(h, 0.55, 1.0)


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
