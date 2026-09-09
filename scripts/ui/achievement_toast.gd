class_name AchievementToast
extends CanvasLayer
## 成就解锁弹窗：右上角滑入的一张"廉价奖状"——微倾斜，像随手钉上去的。
## 队列制：一次解锁潮也只一张张来，仪式感拉满。

const SHOW_TIME := 3.2   # 停留时长
const SLIDE_TIME := 0.3  # 滑入/滑出时长
const MARGIN_X := 18.0
const MARGIN_Y := 56.0

var sfx: SfxBank  # 可选（由 game.gd 注入；解锁时"叮"一声）

var _queue: Array = []
var _showing := false
var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _desc_label: Label


func _ready() -> void:
	layer = 15  # HUD(10) 之上、设置(20)/地图(30) 之下——不抢正经界面的戏
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡操作
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.rotation_degrees = -2.0  # 手钉的，歪是特性
	_panel.custom_minimum_size = Vector2(340, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.06, 0.94)
	style.border_color = Color(1.0, 0.82, 0.25)  # 金边——廉价奖状的尊严
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_panel.add_child(col)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 19)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title_label)

	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 14)
	_desc_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_desc_label)


## 队列里还有几张奖状没发（测试/调试用）
func pending() -> int:
	return _queue.size() + (1 if _showing else 0)


func notify(title: String, desc: String) -> void:
	_queue.append({"title": title, "desc": desc})
	if not _showing:
		_pop()


func _pop() -> void:
	if _queue.is_empty():
		return
	_showing = true
	var e: Dictionary = _queue.pop_front()
	_title_label.text = "成就解锁 · %s" % e["title"]
	_desc_label.text = str(e["desc"])
	if sfx != null:
		sfx.play("ding")
	_panel.visible = true
	# 等一帧，让 PanelContainer 算出实际尺寸（内容不定宽）
	await get_tree().process_frame
	if not is_inside_tree():
		_showing = false
		return
	var vp := _root.size
	var shown_x := vp.x - _panel.size.x - MARGIN_X
	var hidden_x := vp.x + 24.0
	_panel.position = Vector2(hidden_x, MARGIN_Y)
	var tw := create_tween()
	tw.tween_property(_panel, "position:x", shown_x, SLIDE_TIME).set_ease(Tween.EASE_OUT)
	await tw.finished
	if not is_inside_tree():
		_showing = false
		return
	await get_tree().create_timer(SHOW_TIME).timeout
	if not is_inside_tree():
		_showing = false
		return
	var tw2 := create_tween()
	tw2.tween_property(_panel, "position:x", hidden_x, SLIDE_TIME).set_ease(Tween.EASE_IN)
	await tw2.finished
	_panel.visible = false
	_showing = false
	_pop()
