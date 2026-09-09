class_name CowShop
extends Node3D
## 牛哥商店：一块悬浮在空中的木板（为什么悬空？穿模世界的地基不稳，这是特性）。
## 金草 = 货币。价格随购买次数递增——牛哥说要控制通胀。

signal menu_closed

const INTERACT_RADIUS := 6.0
const HINT_COOLDOWN := 6.0

## 各道具基础价（金草）；实价 = 基础价 + 本商店累计购买次数
const BASE_PRICES := {
	"potion": 2,
	"bomb": 2,
	"boots": 3,
	"horn": 3,
	"rewind": 4,
	"whistle": 5,
}

var player: PlayerCow
var items: Node  # ItemManager（避免循环类型引用）
var hud: GameHUD
var sfx: SfxBank

var menu_open := false
var purchases := 0

var _menu: CanvasLayer
var _panel: PanelContainer
var _title: Label
var _buy_btns: Dictionary = {}  # id → Button
var _hint_cd := 0.0
var _t := 0.0


func _ready() -> void:
	_build_plank()


func _process(delta: float) -> void:
	_t += delta
	if _hint_cd > 0.0:
		_hint_cd -= delta
	# 木板轻微摇晃——悬空的东西就该晃
	rotation.z = sin(_t * 0.8) * 0.03
	# 靠近提示
	if not menu_open and player != null and hud != null:
		if global_position.distance_to(player.global_position) < INTERACT_RADIUS:
			if _hint_cd <= 0.0:
				_hint_cd = HINT_COOLDOWN
				hud.show_message("牛哥商店：按 E 光顾（金草余额 %d 根）" % items.gold_balance(), 3.0)


func place(x: float, z: float) -> void:
	var y: float = 0.0
	if items != null and items.terrain != null:
		y = items.terrain.height_at(x, z)
	global_position = Vector3(x, y + 5.0, z)


## —————————— 木板本体 ——————————

func _build_plank() -> void:
	var plank := MeshInstance3D.new()
	plank.name = "Plank"
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 0.35, 2.5)
	plank.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.4, 0.25)
	mat.roughness = 1.0
	plank.material_override = mat
	plank.position = Vector3(0, -0.2, 0)
	add_child(plank)

	# 支撑柱（一根——半吊子工程美学）
	var pole := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.3, 5.0, 0.3)
	pole.mesh = pbox
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.4, 0.3, 0.2)
	pmat.roughness = 1.0
	pole.material_override = pmat
	pole.position = Vector3(0, -2.6, 0)
	add_child(pole)

	var light := OmniLight3D.new()
	light.omni_range = 6.0
	light.light_energy = 0.9
	light.position = Vector3(0, 1.5, 0)
	add_child(light)

	# 招牌（Label3D：字就是招牌）
	var sign := Label3D.new()
	sign.text = "牛哥商店"
	sign.font_size = 52
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 1.8, 0)
	sign.modulate = Color(1.0, 0.9, 0.4)
	add_child(sign)


## —————————— 菜单 UI ——————————

func _unhandled_input(event: InputEvent) -> void:
	if menu_open:
		if event.is_action_pressed("toggle_mouse") or event.is_action_pressed("eat"):
			_close()
		return
	if player == null or items == null:
		return
	if event.is_action_pressed("eat") and _ui_blocked() == false:
		if global_position.distance_to(player.global_position) < INTERACT_RADIUS:
			_open()


func _ui_blocked() -> bool:
	var vp := get_viewport()
	return vp != null and vp.gui_get_focus_owner() != null


func _open() -> void:
	menu_open = true
	_build_menu()
	_refresh_menu()
	_menu.visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if sfx != null:
		sfx.play("click")


func _close() -> void:
	menu_open = false
	if _menu != null:
		_menu.visible = false
	menu_closed.emit()


func _build_menu() -> void:
	if _menu != null:
		return
	_menu = CanvasLayer.new()
	_menu.name = "ShopMenu"
	_menu.layer = 30
	add_child(_menu)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.08, 0.96)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1.0, 0.9, 0.4)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(360, 0)
	_panel.add_child(vb)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	vb.add_child(_title)

	var tip := Label.new()
	tip.text = "金草只收吃完的。墙上那几根……墙是脆的。"
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)

	for id in ["potion", "bomb", "boots", "horn", "rewind", "whistle"]:
		var btn := Button.new()
		btn.text = "……"
		btn.pressed.connect(_on_buy.bind(id))
		vb.add_child(btn)
		_buy_btns[id] = btn

	var close_tip := Label.new()
	close_tip.text = "ESC 关闭（牛哥不送客）"
	close_tip.add_theme_font_size_override("font_size", 12)
	close_tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	close_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(close_tip)

	# 打开即聚焦第一个按钮——顺便屏蔽移动输入（正在谈生意）
	await get_tree().process_frame
	if _buy_btns.size() > 0 and menu_open:
		(_buy_btns.values()[0] as Button).grab_focus()


func _refresh_menu() -> void:
	if _title == null:
		return
	_title.text = "牛哥商店 —— 金草余额：%d 根" % items.gold_balance()
	for id in _buy_btns:
		var price: int = items.shop_price(id)
		var owned: int = items.count_of(id)
		(_buy_btns[id] as Button).text = "%s（有 %d）—— %d 金草" % [ItemDefs.name_of(id), owned, price]
	_title.text += "\n（本店已成交 %d 笔，价格只会越来越牛）" % purchases if purchases > 0 else ""


func _on_buy(id: String) -> void:
	var price: int = items.shop_price(id)
	if items.gold_balance() < price:
		if hud != null:
			hud.show_message("金草不够。去隐藏区薅一点——墙是脆的，你知道的。", 3.0)
		if sfx != null:
			sfx.play("moo")
		return
	if not items.add_item(id):
		if hud != null:
			hud.show_message("牛蹄已满（三个槽）。用掉一个再来。", 3.0)
		return
	items.spend_gold(price)
	purchases += 1
	if hud != null:
		hud.show_message("买到手了：%s（金草剩 %d 根）" % [ItemDefs.name_of(id), items.gold_balance()], 3.0)
	if sfx != null:
		sfx.play("ding")
	_refresh_menu()
