class_name WorldMap
extends CanvasLayer
## 全屏地图（M 键开关）：手绘简陋风——纯色方块 + 系统字体标签。
## 显示：地形范围、池塘、隐藏区、树、任务目标、玩家位置与朝向。

const WORLD_SIZE := 200.0  # 与 Grassland 世界一致
const LABEL_FONT_SIZE := 15

var player: Node3D
var terrain: Grassland
var quests: QuestManager
var battle: BattleRoyale
## 混沌调度器（free 模式由 game.gd 注入；画黑洞标记）。null = 无黑洞可画
var chaos: ChaosManager
## 商店世界坐标（free 模式由 game.gd 注入；画成金色"店"标记）。INF = 无商店不画
var shop_pos := Vector2.INF

var _panel: Control
var _open := false
## 输入开关（进入闪回/现实后由 game.gd 关闭）
var input_enabled := true


func _ready() -> void:
	layer = 30
	_panel = Control.new()
	_panel.name = "MapPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # 挡住游戏输入
	_panel.visible = false
	_panel.draw.connect(_draw_map)
	add_child(_panel)


func _process(_delta: float) -> void:
	# 按住 M 查看、松开即收（半透明底还能看到世界——不再挡视野）
	if input_enabled:
		if Input.is_action_just_pressed("map"):
			_open = true
			_panel.visible = true
		elif _open and not Input.is_action_pressed("map"):
			_open = false
			_panel.visible = false
	if _open:
		_panel.queue_redraw()  # 每帧重绘（任务目标/玩家会动）


func toggle() -> void:
	_open = not _open
	_panel.visible = _open
	if _open:
		_panel.queue_redraw()


## 世界坐标(XZ) → 地图像素坐标
func _world_to_map(world_x: float, world_z: float, origin: Vector2, scale: float) -> Vector2:
	return origin + Vector2(world_x + WORLD_SIZE * 0.5, world_z + WORLD_SIZE * 0.5) * scale


func _draw_map() -> void:
	var vp := _panel.get_viewport_rect().size
	var font := ThemeDB.fallback_font

	# —— 半透明黑底（能看到底下的世界——看地图不瞎走） ——
	_panel.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.06, 0.05, 0.62))

	# —— 地图区：居中正方形 ——
	var pad := 70.0
	var map_side := minf(vp.x, vp.y) - pad * 2.0
	var scale := map_side / WORLD_SIZE
	var origin := (vp - Vector2(map_side, map_side)) * 0.5

	# 地形底色（草原绿）
	_panel.draw_rect(Rect2(origin, Vector2(map_side, map_side)), Color(0.23, 0.5, 0.18))
	# 边框（白色双线——"手绘"感）
	_panel.draw_rect(Rect2(origin - Vector2(3, 3), Vector2(map_side + 6, map_side + 6)), Color(0.92, 0.9, 0.85), false, 2.0)
	_panel.draw_rect(Rect2(origin, Vector2(map_side, map_side)), Color(0.1, 0.1, 0.1), false, 1.0)

	# 池塘（蓝色圆盘）
	var pond := _world_to_map(Grassland.POND_POSITION.x, Grassland.POND_POSITION.y, origin, scale)
	var pond_r := 6.0 * scale
	_panel.draw_circle(pond, pond_r, Color(0.3, 0.5, 0.9))

	# 隐藏区（灰色方块 + 金色问号）
	var sc := _world_to_map(Grassland.SECRET_CENTER.x, Grassland.SECRET_CENTER.y, origin, scale)
	var sq := Grassland.SECRET_HALF * 2.0 * scale
	_panel.draw_rect(Rect2(sc - Vector2(sq, sq) * 0.5, Vector2(sq, sq)), Color(0.25, 0.25, 0.28))
	_panel.draw_string(font, sc - Vector2(7, -6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.3))

	# 树（深绿小方块）
	for tp in terrain.tree_positions:
		var p := _world_to_map(tp.x, tp.z, origin, scale)
		_panel.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.12, 0.38, 0.12))

	# —— 金草（金色小点——草原的硬通货） ——
	for gp in terrain.gold_positions_alive():
		var gpt := _world_to_map(gp.x, gp.z, origin, scale)
		_panel.draw_circle(gpt, 3.5, Color(1.0, 0.8, 0.15))

	# —— 牛哥商店（金色方块 + "店"，一块悬空的木板） ——
	if shop_pos != Vector2.INF:
		var sp := _world_to_map(shop_pos.x, shop_pos.y, origin, scale)
		_panel.draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), Color(1.0, 0.85, 0.25))
		_panel.draw_string(font, sp + Vector2(10, 5), "店", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(1.0, 0.9, 0.4))

	# —— 混沌黑洞（紫色漩涡——看得见才撞得上） ——
	if chaos != null and chaos._blackhole != null and is_instance_valid(chaos._blackhole):
		var bpos: Vector3 = chaos._blackhole.global_position
		var bp := _world_to_map(bpos.x, bpos.z, origin, scale)
		_panel.draw_circle(bp, 8.0, Color(0.4, 0.1, 0.65))
		_panel.draw_arc(bp, 5.0, 0.0, TAU * 0.75, 24, Color(0.85, 0.6, 1.0), 2.0)
		_panel.draw_string(font, bp + Vector2(11, 5), "洞", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.85, 0.6, 1.0))

	# —— 巨石 BOSS（灰色滚石——正朝你滚过来） ——
	for b in get_tree().get_nodes_in_group("boulder_bosses"):
		var qp := _world_to_map(b.global_position.x, b.global_position.z, origin, scale)
		_panel.draw_rect(Rect2(qp - Vector2(6, 6), Vector2(12, 12)), Color(0.55, 0.5, 0.48))
		_panel.draw_string(font, qp + Vector2(11, 5), "石", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.85, 0.8, 0.78))

	# —— 大逃杀安全圈（绿实线 = 当前圈，白细线 = 下一圈目标） ——
	if battle != null and battle.radius > 1.0:
		var zc := _world_to_map(battle.center.x, battle.center.y, origin, scale)
		_panel.draw_arc(zc, battle.radius * scale, 0.0, TAU, 96, Color(0.3, 1.0, 0.45), 3.0)
		if battle.phase == 0 and battle.stage < battle.ZONE_RADII.size():
			var nr: float = battle.ZONE_RADII[mini(battle.stage + 1, battle.ZONE_RADII.size() - 1)]
			var nc := battle.next_center()
			var npt := _world_to_map(nc.x, nc.y, origin, scale)
			_panel.draw_arc(npt, nr * scale, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.65), 1.5)
		_panel.draw_string(font, zc + Vector2(6, -6), "安全圈", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.3, 1.0, 0.45))

	# —— 任务目标 ——
	var markers: Array[Dictionary] = []
	if quests != null:
		if quests.main_state == 0:
			markers.append({"pos": quests.lark.global_position, "text": "云雀?", "color": Color(0.98, 0.85, 0.3)})
		if quests.main_state == 1:
			markers.append({"pos": quests.nest_pos, "text": "巢", "color": Color(0.85, 0.55, 0.2)})
		if quests.side_state == 0:
			markers.append({"pos": quests.feed_pile.global_position, "text": "草料", "color": Color(0.75, 0.8, 0.4)})
		if quests.side_state == 1:
			markers.append({"pos": quests.alpaca.global_position, "text": "毛蛋", "color": Color(0.98, 0.7, 0.8)})
	for m in markers:
		var p := _world_to_map(m["pos"].x, m["pos"].z, origin, scale)
		_panel.draw_circle(p, 6.0, m["color"])
		_panel.draw_string(font, p + Vector2(9, 5), m["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, m["color"])

	# —— 玩家：白色三角（朝向 = 模型 Y 旋转） ——
	if player != null:
		var p := _world_to_map(player.global_position.x, player.global_position.z, origin, scale)
		var ry: float = 0.0
		if player is PlayerCow:
			ry = (player as PlayerCow).model.rotation.y
		elif player is WeakCow:
			ry = (player as WeakCow).model.rotation.y
		# 世界 +Z 脸方向 → 地图向下
		var dir := Vector2(sin(ry), cos(ry)).normalized()
		var side := Vector2(-dir.y, dir.x)
		var tip := p + dir * 11.0
		var l := p - dir * 5.0 + side * 6.0
		var r := p - dir * 5.0 - side * 6.0
		_panel.draw_polygon(PackedVector2Array([tip, l, r]), PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]))
		_panel.draw_string(font, p + Vector2(10, -8), "你", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color.WHITE)

	# —— 标题与提示 ——
	_panel.draw_string(font, Vector2(origin.x, 34.0), "牛走 · 草原地图（手搓版）", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.92, 0.9, 0.85))
	_panel.draw_string(font, Vector2(vp.x * 0.5 - 100.0, vp.y - 26.0), "按住 M 查看，松开收起", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.58))
	# 罗盘标记
	_panel.draw_string(font, origin + Vector2(map_side * 0.5 - 8.0, -8.0), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.78))
