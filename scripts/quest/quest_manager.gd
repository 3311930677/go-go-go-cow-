class_name QuestManager
extends Node
## 任务系统：主线"迷路的云雀" + 支线"给毛蛋送草料"。
## 刻意荒诞：云雀卡在地下/树里/天上，需要冲撞附近把它"撞出来"；
## 毛蛋出生在山顶/"水底"/半空等离谱位置。
## HUD 任务栏带八方向罗盘 + 距离提示。
## P3：巢每次开局随机漂移（穿模世界的坐标不稳）；
## 毛蛋吃饱后随机触发"毛蛋飞天"，引出隐藏 BOSS 战（会滚的巨石）。

## 巢的漂移范围（世界 XZ，以出生点为圆心的环带）——每次开局都不在老地方
const NEST_MIN_R := 45.0
const NEST_MAX_R := 80.0
const FEED_PILE_POSITION := Vector2(4.0, 6.0)  # 草料堆（出生点旁）
const UNSTICK_RADIUS := 4.0    # 冲撞"撞出"云雀的水平判定半径
const NEST_ARRIVE_RADIUS := 6.0
const PICKUP_RADIUS := 3.0
const FEED_RADIUS := 4.5

## 毛蛋飞天：投喂后 4~9 秒随机起飞，引出巨石 BOSS
const ALPACA_FLY_MIN_DELAY := 4.0
const ALPACA_FLY_MAX_DELAY := 9.0
const ALPACA_FLY_CHANCE := 0.6  # 不是每次都飞——毛蛋也有吃饱想睡觉的时候

signal quests_all_done
signal boss_started(boss: Node3D)

var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank

var lark: Lark
var alpaca: Alpaca
var nest_pos: Vector3
var feed_pile: Node3D

var main_state := 0  # 0 寻找云雀 / 1 护送回巢 / 2 完成
var side_state := 0  # 0 领草料 / 1 送给毛蛋 / 2 完成
var has_feed := false

var _alpaca_variant := 0  # 0 山顶 / 1 "水底" / 2 半空悬浮
var _hud_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _all_done_emitted := false
## 毛蛋飞天倒计时（<0 = 未排程）
var _alpaca_fly_in := -1.0
## 停用开关（进入闪回/现实后由 game.gd 关闭）
var enabled := true


func _ready() -> void:
	_rng.randomize()  # 每次开局的奇遇都不同——包括巢的位置
	var ang := _rng.randf() * TAU
	var r := _rng.randf_range(NEST_MIN_R, NEST_MAX_R)
	var nx := cos(ang) * r
	var nz := sin(ang) * r
	nest_pos = Vector3(nx, terrain.height_at(nx, nz), nz)
	_build_nest()
	_build_feed_pile()
	_spawn_lark()
	_spawn_alpaca()
	_update_task_text()


func _process(delta: float) -> void:
	if not enabled:
		return
	# 任务 2/2 → 通知 game 进入闪回
	if not _all_done_emitted and main_state == 2 and side_state == 2:
		_all_done_emitted = true
		quests_all_done.emit()
	# —— 主线：冲撞撞出云雀 ——
	if main_state == 0:
		if player._charge_timer > 0.0 and _horiz_dist(player.global_position, lark.global_position) < UNSTICK_RADIUS:
			lark.unstick()
			main_state = 1
			match lark.stuck_variant:
				0: hud.show_message("云雀被从土里撞了出来！它抖了抖身上的土。", 3.0)
				1: hud.show_message("云雀从树里撞了出来！树毫发无损。", 3.0)
				_: hud.show_message("你的冲撞震下来一只卡在天上的云雀。", 3.0)
	# —— 主线：护送到巢 ——
	elif main_state == 1:
		if player.is_on_floor() and _horiz_dist(player.global_position, nest_pos) < NEST_ARRIVE_RADIUS:
			main_state = 2
			lark.go_to_nest(nest_pos)
			if sfx != null:
				sfx.play("ding")
			hud.show_message("云雀回到了巢。它可能明天还会迷路。奖励：无。", 4.0)

	# —— 支线：领取草料 ——
	if side_state == 0:
		if Input.is_action_just_pressed("eat") and _horiz_dist(player.global_position, feed_pile.global_position) < PICKUP_RADIUS:
			has_feed = true
			side_state = 1
			feed_pile.visible = false
			hud.show_message("领取了草料。毛蛋正在某个离谱的地方等你。", 3.5)
	# —— 支线：投喂毛蛋 ——
	elif side_state == 1:
		if Input.is_action_just_pressed("eat") and _horiz_dist(player.global_position, alpaca.global_position) < FEED_RADIUS:
			side_state = 2
			alpaca.fed = true
			if sfx != null:
				sfx.play("ding")
			match _alpaca_variant:
				0: hud.show_message("毛蛋在山顶吃到了草料。风很大。", 3.5)
				1: hud.show_message("毛蛋在\u201c水底\u201d吃到了草料。（所谓水，是个蓝色圆盘）", 3.5)
				_: hud.show_message("你把草料抛给了半空中的毛蛋。它接住了。", 3.5)
			# 排程"毛蛋飞天"：吃饱了，随机起飞引出巨石 BOSS
			if _rng.randf() < ALPACA_FLY_CHANCE:
				_alpaca_fly_in = _rng.randf_range(ALPACA_FLY_MIN_DELAY, ALPACA_FLY_MAX_DELAY)
				hud.show_message("毛蛋吃得好饱。它看起来有点不对劲……", 3.5)

	# —— 毛蛋飞天 → 巨石 BOSS ——
	if _alpaca_fly_in > 0.0:
		_alpaca_fly_in -= delta
		if _alpaca_fly_in <= 0.0:
			_alpaca_fly_in = -1.0
			_trigger_alpaca_fly()

	# HUD 节流刷新
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.25
		_update_task_text()


# ————————————————— 生成 —————————————————

func _spawn_lark() -> void:
	lark = Lark.new()
	lark.player = player
	lark.stuck_variant = _rng.randi() % 3
	var pos: Vector3
	match lark.stuck_variant:
		0:  # 半埋地下
			var p0 := _random_point(50.0)
			pos = Vector3(p0.x, terrain.height_at(p0.x, p0.y) - 0.25, p0.y)
		1:  # 卡在树冠里
			if terrain.tree_positions.is_empty():
				lark.stuck_variant = 2
				var p1 := _random_point(50.0)
				pos = Vector3(p1.x, terrain.height_at(p1.x, p1.y) + 12.0, p1.y)
			else:
				var tp: Vector3 = terrain.tree_positions[_rng.randi() % terrain.tree_positions.size()]
				pos = tp + Vector3(0, 3.2, 0)
		_:  # 悬浮天上
			var p2 := _random_point(50.0)
			pos = Vector3(p2.x, terrain.height_at(p2.x, p2.y) + 12.0, p2.y)
	get_parent().add_child(lark)
	lark.global_position = pos


func _spawn_alpaca() -> void:
	alpaca = Alpaca.new()
	_alpaca_variant = _rng.randi() % 3
	var pos: Vector3
	match _alpaca_variant:
		0:  # 山顶：网格采样找最高点
			var best := Vector2.ZERO
			var best_h := -999.0
			var x := -80.0
			while x <= 80.0:
				var z := -80.0
				while z <= 80.0:
					var h := terrain.height_at(x, z)
					if h > best_h:
						best_h = h
						best = Vector2(x, z)
					z += 8.0
				x += 8.0
			pos = Vector3(best.x, best_h, best.y)
		1:  # "水底"：蓝色圆盘池塘中央
			var px := Grassland.POND_POSITION.x
			var pz := Grassland.POND_POSITION.y
			pos = Vector3(px, terrain.height_at(px, pz), pz)
		_:  # 半空悬浮
			pos = Vector3(-45.0, terrain.height_at(-45.0, 45.0) + 8.0, 45.0)
	get_parent().add_child(alpaca)
	alpaca.global_position = pos


## 云雀的巢：8 根小木棍围一圈 + 一枚蛋
func _build_nest() -> void:
	var nest := Node3D.new()
	nest.name = "LarkNest"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.18)
	mat.roughness = 1.0
	for i in 8:
		var ang := TAU * i / 8.0
		var twig := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.12, 0.14)
		twig.mesh = mesh
		twig.material_override = mat
		twig.position = Vector3(cos(ang) * 0.5, 0.06, sin(ang) * 0.5)
		twig.rotation.y = -ang + PI / 2.0
		nest.add_child(twig)
	var egg := MeshInstance3D.new()
	var egg_mesh := SphereMesh.new()
	egg_mesh.radius = 0.12
	egg_mesh.height = 0.24
	egg_mesh.radial_segments = 6
	egg_mesh.rings = 3
	egg.mesh = egg_mesh
	var egg_mat := StandardMaterial3D.new()
	egg_mat.albedo_color = Color(0.95, 0.93, 0.85)
	egg_mat.roughness = 1.0
	egg.material_override = egg_mat
	egg.position = Vector3(0.1, 0.1, 0)
	nest.add_child(egg)
	get_parent().add_child(nest)
	nest.global_position = nest_pos


## 草料堆：三层枯草色方盒
func _build_feed_pile() -> void:
	feed_pile = Node3D.new()
	feed_pile.name = "FeedPile"
	var x := FEED_PILE_POSITION.x
	var z := FEED_PILE_POSITION.y
	var y := terrain.height_at(x, z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.6, 0.25)
	mat.roughness = 1.0
	for i in 3:
		var b := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9 - i * 0.2, 0.3, 0.7 - i * 0.15)
		b.mesh = mesh
		b.material_override = mat
		b.position = Vector3(0, 0.15 + i * 0.3, 0)
		b.rotation.y = i * 0.35
		feed_pile.add_child(b)
	get_parent().add_child(feed_pile)
	feed_pile.global_position = Vector3(x, y, z)


# ————————————————— 毛蛋飞天 → 巨石 BOSS —————————————————

## 毛蛋飞天：垂直升空消失，然后地面隆起一块巨石——隐藏 BOSS 战开始
func _trigger_alpaca_fly() -> void:
	if alpaca == null or not is_instance_valid(alpaca):
		return
	if sfx != null:
		sfx.play("fly")
		sfx.play("event")
	hud.show_message("毛蛋垂直起飞了！！它越飞越高，越飞越远……\n（远处传来石头摩擦的声音）", 5.0)
	# 毛蛋起飞：每帧升高，飞出视野后隐藏
	var fly_target_y: float = alpaca.global_position.y + 60.0
	var t := get_tree().create_timer(3.0)
	_fly_alpaca_away(fly_target_y)
	await t.timeout
	if alpaca != null and is_instance_valid(alpaca):
		alpaca.visible = false
	# 巨石从地下隆起（在毛蛋原位置附近）
	_spawn_boulder_boss()


func _fly_alpaca_away(target_y: float) -> void:
	# 简陋起飞：用补间式每帧抬升（毛蛋没有物理，直接动 position）
	var tw := create_tween()
	tw.tween_property(alpaca, "position:y", target_y, 2.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 顺手加个自转——起飞的毛蛋要有排面
	var tw2 := create_tween()
	tw2.set_loops(8)
	tw2.tween_property(alpaca, "rotation:y", alpaca.rotation.y + TAU, 0.3)


func _spawn_boulder_boss() -> void:
	if player == null or terrain == null:
		return
	# 出生点：玩家 25 米外的随机方向——够近够有压迫感，又给玩家反应时间
	var ang := _rng.randf() * TAU
	var bx: float = player.global_position.x + cos(ang) * 25.0
	var bz: float = player.global_position.z + sin(ang) * 25.0
	var by: float = terrain.height_at(bx, bz) - 2.0  # 从地下隆起
	var boss := BoulderBoss.new()
	boss.name = "BoulderBoss"
	boss.player = player
	boss.terrain = terrain
	boss.hud = hud
	boss.sfx = sfx
	get_parent().add_child(boss)
	boss.global_position = Vector3(bx, by, bz)
	boss.rise_from_ground()
	boss_started.emit(boss)


# ————————————————— HUD —————————————————

func _update_task_text() -> void:
	var lines: Array[String] = []
	if main_state == 0:
		lines.append("【主线】寻找迷路的云雀：冲撞它附近把它撞出来（%s）" % _hint(lark.global_position))
	elif main_state == 1:
		lines.append("【主线】护送云雀回巢（%s）" % _hint(nest_pos))
	else:
		lines.append("【主线】云雀回巢（已完成）")
	if side_state == 0:
		lines.append("【支线】在出生点的草料堆领取草料（%s）" % _hint(feed_pile.global_position))
	elif side_state == 1:
		lines.append("【支线】把草料送给毛蛋（%s）" % _hint(alpaca.global_position))
	else:
		lines.append("【支线】投喂毛蛋（已完成）")
	lines.append("任务完成度：%d/2" % (int(main_state == 2) + int(side_state == 2)))
	hud.set_task("\n".join(lines))


## 导航提示：近处"就在附近"，远处"八方向·距离"
func _hint(target: Vector3) -> String:
	var d := _horiz_dist(player.global_position, target)
	if d < 15.0:
		return "就在附近"
	return "%s·%d米" % [_compass(player.global_position, target), int(d)]


# ————————————————— 工具 —————————————————

## 水平距离（忽略 Y——离谱高度的 NPC 也能交互）
func _horiz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## 八方向罗盘（北 = -Z，东 = +X）
func _compass(from: Vector3, to: Vector3) -> String:
	var ang := atan2(to.x - from.x, -(to.z - from.z))
	var names := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
	var idx := int(round(ang / (TAU / 8.0))) % 8
	if idx < 0:
		idx += 8
	return names[idx]


## 出生点半径 radius 内的随机点（避开出生点核心区）
func _random_point(radius: float) -> Vector2:
	while true:
		var p := Vector2(_rng.randf_range(-radius, radius), _rng.randf_range(-radius, radius))
		if p.length() > 12.0:
			return p
	return Vector2.ZERO
