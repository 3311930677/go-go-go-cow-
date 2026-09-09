class_name ItemBar
extends CanvasLayer
## 道具栏：右下角三个槽位。刻意的"像素简陋"风——
## 纯色方块 + 默认字体 + 描边数字，与全游戏的灾难级美术保持统一。
## 悬停槽位显示说明卡（不然谁知道瓶里装的是啥）。

const SLOT_SIZE := 64.0
const MARGIN := 18.0
const SEP := 8.0
const TIP_WIDTH := 380.0

var _slots: Array = []      # Panel
var _glyphs: Array = []     # Label
var _counts: Array = []     # Label
var _keys: Array = []       # Label（快捷键提示）
var _tip: PanelContainer    # 说明卡（道具栏上方）
var _tip_label: Label
var _tip_index := -1        # 当前悬停槽位（-1 = 无）

# 槽位内容缓存（refresh() 维护，悬停说明取用）
var _ids: Array = ["", "", ""]
var _nums: Array = [0, 0, 0]


func _ready() -> void:
	layer = 8
	_build()


func _build() -> void:
	var hb := HBoxContainer.new()
	hb.name = "ItemBarBox"
	hb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var total_w := SLOT_SIZE * 3.0 + SEP * 2.0 + MARGIN
	hb.offset_left = -total_w
	hb.offset_right = -MARGIN
	hb.offset_top = -SLOT_SIZE - MARGIN
	hb.offset_bottom = -MARGIN
	hb.add_theme_constant_override("separation", int(SEP))
	add_child(hb)

	_tip = _build_tip()
	add_child(_tip)

	for i in 3:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP  # 悬停查看说明
		panel.mouse_entered.connect(_show_tip.bind(i))
		panel.mouse_exited.connect(_hide_tip)
		hb.add_child(panel)

		var key := Label.new()
		key.text = str(i + 1)
		key.position = Vector2(4, 0)
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(key)

		var glyph := Label.new()
		glyph.text = "空"
		glyph.position = Vector2(0, 14)
		glyph.size = Vector2(SLOT_SIZE, 36)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 26)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(glyph)

		var count := Label.new()
		count.text = ""
		count.position = Vector2(SLOT_SIZE - 30, SLOT_SIZE - 24)
		count.add_theme_font_size_override("font_size", 14)
		count.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(count)

		_slots.append(panel)
		_glyphs.append(glyph)
		_counts.append(count)
		_keys.append(key)

		_style_slot(i, false, Color(0.5, 0.5, 0.5))


func _build_tip() -> PanelContainer:
	var tip := PanelContainer.new()
	tip.name = "ItemTip"
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip.offset_left = -TIP_WIDTH - MARGIN
	tip.offset_right = -MARGIN
	tip.offset_top = -SLOT_SIZE - MARGIN - 130
	tip.offset_bottom = -SLOT_SIZE - MARGIN - SEP
	tip.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.05, 0.96)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1, 0.95, 0.6)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	tip.add_theme_stylebox_override("panel", sb)

	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 14)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(_tip_label)
	return tip


## 刷新显示：inventory = [{id, count}, ...]（长度 ≤ 3）
func refresh(inventory: Array) -> void:
	for i in 3:
		if i < inventory.size():
			var entry: Dictionary = inventory[i]
			var id: String = entry.get("id", "")
			_ids[i] = id
			_nums[i] = int(entry.get("count", 1))
			(_glyphs[i] as Label).text = ItemDefs.glyph_of(id)
			(_counts[i] as Label).text = "x%d" % _nums[i]
			_style_slot(i, true, ItemDefs.color_of(id))
		else:
			_ids[i] = ""
			_nums[i] = 0
			(_glyphs[i] as Label).text = "空"
			(_counts[i] as Label).text = ""
			_style_slot(i, false, Color(0.5, 0.5, 0.5))
	# 背包变了，悬停说明可能过期——立即刷新悬停中的说明
	if _tip_index >= 0 and _tip.visible:
		_update_tip_content(_tip_index)


# ———————— 说明卡 ————————

func _show_tip(i: int) -> void:
	_tip_index = i
	_update_tip_content(i)
	_tip.visible = true


func _hide_tip() -> void:
	_tip_index = -1
	_tip.visible = false


func _update_tip_content(i: int) -> void:
	if _tip_label == null or i < 0 or i >= _ids.size():
		return
	if _ids[i] == "":
		_tip_label.text = "空槽。牛蹄一般。\n（按 1/2/3 使用道具；发光的小玩意就是道具）"
		return
	var id: String = _ids[i]
	_tip_label.text = "%s ×%d\n%s" % [
		ItemDefs.name_of(id), _nums[i],
		str(ItemDefs.INFO.get(id, {}).get("desc", ""))]
	var sb: StyleBoxFlat = (_tip.get_theme_stylebox("panel").duplicate()) as StyleBoxFlat
	if sb != null:
		sb.border_color = ItemDefs.color_of(id)
		_tip.add_theme_stylebox_override("panel", sb)


func _style_slot(i: int, filled: bool, c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = c if filled else Color(0.35, 0.35, 0.35, 0.8)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	(_slots[i] as Panel).add_theme_stylebox_override("panel", sb)
	(_glyphs[i] as Label).add_theme_color_override("font_color",
		c if filled else Color(1, 1, 1, 0.3))
