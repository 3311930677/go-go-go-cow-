class_name SkyRace
extends Node3D
## 飞天竞速：连跳起飞，按顺序穿过空中浮环。
## 金色 = 下一环 · 绿色 = 已过 · 灰色 = 还没轮到。按 R 重新开始。

const RING_COUNT := 10
const RING_RADIUS := 40.0
const PASS_RADIUS := 3.8
const BEST_PATH := "user://race_best.txt"

const DIRS := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]

var game: Game
var player: PlayerCow
var hud: GameHUD
var sfx: SfxBank

var ring_positions: Array[Vector3] = []
var state := 0  # 0=等第一环 1=计时中 2=完赛
var idx := 0
var start_ms := 0
var best := INF
var _rings: Array[Node3D] = []
var _mats := {}
var _t := 0.0
var _hud_acc := 0.0


func _ready() -> void:
	best = _load_best()
	_build_mats()
	_build_rings()
	_update_task()


func _process(delta: float) -> void:
	_t += delta
	# 浮环缓缓上下浮动
	for i in _rings.size():
		_rings[i].position.y = ring_positions[i].y + sin(_t * 1.5 + i) * 0.4
	# 计时中：任务栏实时刷新
	if state == 1:
		_hud_acc += delta
		if _hud_acc > 0.1:
			_hud_acc = 0.0
			_update_task()


func _physics_process(_delta: float) -> void:
	if state == 2:
		return
	if player.global_position.distance_to(ring_positions[idx]) < PASS_RADIUS:
		if state == 0:
			state = 1
			start_ms = Time.get_ticks_msec()
		if sfx != null:
			sfx.play("ding")
		idx += 1
		if idx >= ring_positions.size():
			_finish()
		_apply_ring_states()
		_update_task()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		reset()


## 重置：环全灰、从第一环重新开始（玩家留在原地）
func reset() -> void:
	state = 0
	idx = 0
	_apply_ring_states()
	_update_task()
	hud.show_message("计时已重置。三连跳，起飞。", 2.0)


func elapsed_sec() -> float:
	if state == 1:
		return (Time.get_ticks_msec() - start_ms) / 1000.0
	return 0.0


func _finish() -> void:
	state = 2
	if game != null and game.career != null:
		game.career.note_win()  # 生涯：竞速完赛
	var t := elapsed_sec()
	if t < best:
		best = t
		_save_best(t)
		hud.show_message("完赛！用时 %.1f 秒——新纪录！（依然没有奖励）" % t, 5.0)
	else:
		hud.show_message("完赛！用时 %.1f 秒（最佳 %.1f 秒）" % [t, best], 5.0)
	if game != null and game.net != null and game.net.connected_ok:
		game.net.send_game_event({"type": "race", "name": game.net.my_name, "time": t})


# ———— 构建 ————

func _build_mats() -> void:
	for key in ["pending", "current", "passed"]:
		var m := StandardMaterial3D.new()
		m.roughness = 0.8
		match key:
			"pending":
				m.albedo_color = Color(0.55, 0.55, 0.55)
			"current":
				m.albedo_color = Color(1.0, 0.83, 0.25)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.75, 0.1)
				m.emission_energy_multiplier = 0.9
			"passed":
				m.albedo_color = Color(0.3, 0.8, 0.35)
		_mats[key] = m


func _build_rings() -> void:
	# 第 0 环在出生点正上方；其余绕大圈，高度起伏
	ring_positions.append(Vector3(0, 14, 0))
	for i in RING_COUNT - 1:
		var ang := TAU * (i + 1) / float(RING_COUNT - 1)
		ring_positions.append(Vector3(
			cos(ang) * RING_RADIUS,
			13.0 + 4.0 * sin(i * 2.0),
			sin(ang) * RING_RADIUS))

	for i in ring_positions.size():
		var holder := Node3D.new()
		holder.position = ring_positions[i]
		var next_pos: Vector3 = ring_positions[(i + 1) % ring_positions.size()]
		holder.look_at(next_pos, Vector3.UP)  # 环面朝向下一环
		var mi := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.45
		mesh.outer_radius = 3.0
		mi.mesh = mesh
		mi.rotation_degrees.x = 90.0  # 立起来
		mi.material_override = _mats["pending"]
		holder.add_child(mi)
		add_child(holder)
		_rings.append(holder)
	_apply_ring_states()


func _apply_ring_states() -> void:
	for i in _rings.size():
		var key := "pending"
		if i < idx:
			key = "passed"
		elif i == idx and state != 2:
			key = "current"
		_rings[i].get_child(0).material_override = _mats[key]


# ———— HUD ————

func _update_task() -> void:
	if state == 0:
		hud.set_task("【飞天竞速】三连跳起飞，穿过头顶的金环开始计时\n下一环：头顶（高度约 14 米）\n（按 R 重新开始）")
	elif state == 1:
		hud.set_task("【飞天竞速】第 %d/%d 环 · %.1f 秒\n下一环：%s · %d 米（按 R 重开）" % [
			idx + 1, ring_positions.size(), elapsed_sec(),
			_dir_text(ring_positions[idx]),
			int(player.global_position.distance_to(ring_positions[idx]))])
	else:
		hud.set_task("【飞天竞速】完赛！最佳 %.1f 秒\n按 R 再跑一圈" % best)


## 八方向罗盘文本（与任务系统同款手感）
func _dir_text(target: Vector3) -> String:
	var d := target - player.global_position
	var ang := atan2(d.x, -d.z)
	var i := int(round(ang / (PI / 4.0)))
	i = ((i % 8) + 8) % 8
	return DIRS[i]


# ———— 最佳成绩 ————

func _load_best() -> float:
	var f := FileAccess.open(BEST_PATH, FileAccess.READ)
	if f == null:
		return INF
	var t := f.get_as_text().to_float()
	f.close()
	return t if t > 0.0 else INF


func _save_best(t: float) -> void:
	var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("%.3f" % t)
		f.close()
