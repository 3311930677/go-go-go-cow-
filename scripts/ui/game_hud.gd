class_name GameHUD
extends CanvasLayer
## 极简 HUD：系统默认字体、无装饰、纯色方块进度条。
## 刻意的"简陋到极致"——不使用任何主题美化。

var task_label: Label
var fullness_label: Label
var help_label: Label
var msg_label: Label
var eat_bar_bg: ColorRect
var eat_bar_fg: ColorRect

var _msg_timer := 0.0
var hp_bottles: Array[ColorRect] = []  # P1-B 奶瓶血条
var flash_rect: ColorRect
var black_rect: ColorRect


func _ready() -> void:
	layer = 10
	_build()


func _process(delta: float) -> void:
	# 顶部消息 toast：计时隐藏
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			msg_label.visible = false


## 显示一条临时消息（荒诞文案专用通道）
func show_message(text: String, duration := 2.0) -> void:
	msg_label.text = text
	msg_label.reset_size()
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	msg_label.visible = true
	_msg_timer = duration


## 吃草进度：v ∈ [0,1]；v < 0 隐藏进度条
func set_eat_progress(v: float) -> void:
	if v < 0.0:
		eat_bar_bg.visible = false
		return
	eat_bar_bg.visible = true
	var w := eat_bar_bg.size.x - 4.0
	eat_bar_fg.size.x = maxf(2.0, w * clampf(v, 0.0, 1.0))


## 更新士气显示（原"吃饱度"——现在决定穿模冷却，但依然没什么大用）
func set_fullness(v: int) -> void:
	fullness_label.text = "士气：%d%%（穿模冷却 -%d%%，依然没什么大用）" % [v, int(round(v * 0.4))]


## 更新任务栏文本
func set_task(text: String) -> void:
	task_label.text = text


func _build() -> void:
	# —— 左上：任务（多行：主线/支线/完成度） ——
	task_label = _make_label(17)
	task_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	task_label.position = Vector2(14, 12)
	task_label.size = Vector2(960, 100)
	task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	task_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	task_label.text = "任务加载中……"
	add_child(task_label)

	# —— 左上任务栏下方：吃饱度 ——
	fullness_label = _make_label(16)
	fullness_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	fullness_label.position = Vector2(14, 118)
	fullness_label.size = Vector2(700, 26)
	fullness_label.text = "士气：0%（穿模冷却 -0%，依然没什么大用）"
	fullness_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.8))
	add_child(fullness_label)

	# —— 底部中央：操作说明 ——
	help_label = _make_label(15)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_label.position = Vector2(-420, -40)
	help_label.size = Vector2(840, 26)
	help_label.text = "WASD 移动    空格 跳跃（连跳3次飞天）    左键 冲撞（威力不讲道理）    按住E 吃草    M 地图    T 聊天    ESC 设置"
	help_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	add_child(help_label)

	# —— 顶部中央：消息 toast ——
	msg_label = _make_label(22)
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_label.visible = false
	add_child(msg_label)

	# —— 底部中央：吃草进度条（纯色方块，无圆角） ——
	eat_bar_bg = ColorRect.new()
	eat_bar_bg.color = Color(0.1, 0.1, 0.1)
	eat_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	eat_bar_bg.position = Vector2(-70, -84)
	eat_bar_bg.size = Vector2(140, 16)
	eat_bar_bg.visible = false
	add_child(eat_bar_bg)

	eat_bar_fg = ColorRect.new()
	eat_bar_fg.color = Color(0.3, 0.9, 0.25)  # 刺眼的绿
	eat_bar_fg.position = Vector2(2, 2)
	eat_bar_fg.size = Vector2(2, 12)
	eat_bar_bg.add_child(eat_bar_fg)

	# —— 右下角：常驻水印（截图自带"传播素材"标识） ——
	var watermark := _make_label(14)
	watermark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	watermark.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	watermark.position = Vector2(-330, -26)
	watermark.size = Vector2(316, 20)
	watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	watermark.text = "牛走 v1.0 · BUG 就是特性 · F12 截图"
	watermark.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	watermark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	add_child(watermark)

	# —— 左上任务下方：奶瓶血条（P1-B，3 格） ——
	for i in 3:
		var b := ColorRect.new()
		b.color = Color(0.95, 0.92, 0.82)
		b.position = Vector2(14 + i * 34, 148)
		b.size = Vector2(28, 34)
		var cap := ColorRect.new()
		cap.color = Color(0.8, 0.8, 0.85)
		cap.position = Vector2(4, 0)
		cap.size = Vector2(20, 8)
		b.add_child(cap)
		add_child(b)
		hp_bottles.append(b)

	# —— 全屏白闪（死亡瞬间 / 处决） ——
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.visible = false
	add_child(flash_rect)

	# —— 全屏黑幕（死亡表演） ——
	black_rect = ColorRect.new()
	black_rect.color = Color(0, 0, 0, 0)
	black_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_rect.visible = false
	add_child(black_rect)



## 奶瓶血条：v 满即亮，扣光变暗
func set_hp(v: int) -> void:
	for i in hp_bottles.size():
		var b := hp_bottles[i]
		b.color = Color(0.95, 0.92, 0.82) if i < v else Color(0.16, 0.16, 0.18)
		var cap := b.get_child(0) as ColorRect
		if cap != null:
			cap.color = Color(0.8, 0.8, 0.85) if i < v else Color(0.26, 0.26, 0.3)


## 全屏白闪：暴击瞬间的廉价演出
func flash_white() -> void:
	flash_rect.color = Color(1, 1, 1, 1)
	flash_rect.visible = true
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.5)
	tw.tween_callback(func(): flash_rect.visible = false)


## 全屏黑幕：淡入 → 停留 → 淡出（死亡表演。sec = 停留秒数）
func blackout(sec: float) -> void:
	black_rect.color = Color(0, 0, 0, 0)
	black_rect.visible = true
	var tw := create_tween()
	tw.tween_property(black_rect, "color:a", 1.0, 0.25)
	tw.tween_interval(sec)
	tw.tween_property(black_rect, "color:a", 0.0, 0.35)
	tw.tween_callback(func(): black_rect.visible = false)

## 统一创建"默认字体 + 黑描边"的 Label（系统默认字体的简陋风）
func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
