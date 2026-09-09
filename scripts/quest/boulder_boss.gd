class_name BoulderBoss
extends CharacterBody3D
## 巨石 BOSS：一块会滚的巨石，"耐心"是它的血条。
## 被玩家的冲撞撞一次就掉一份耐心；耐心归零，巨石失去耐心飞向远方（胜利）。
## 它的攻击方式：滚过来撞你（把你撞飞，很丢脸但不致命）。
## 如果玩家跑得太远太久，巨石追累了就回去睡觉（算它赢，很荒诞）。

const RADIUS := 2.2
const PATIENCE_MAX := 4          # 撞 4 下
const ROLL_SPEED := 6.5         # 追玩家的滚动速度
const CHARGE_SPEED := 13.0      # 不耐烦时的冲刺速度
const CHARGE_EVERY := 6.0       # 每隔几秒冲一次
const CHARGE_WINDUP := 0.8      # 冲刺前摇（发红光警告）
const KNOCK_CD := 1.2           # 撞飞玩家的冷却
const GIVEUP_DIST := 70.0       # 玩家跑多远算"追累了"
const GIVEUP_TIME := 12.0       # 持续跑多久算"追累了"
const RISE_DURATION := 1.5      # 从地下隆起的时长

signal boss_defeated(at: Vector3)  # 胜利掉落点（game/ItemManager 摆道具）

var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank
var net: NetManager

var patience := PATIENCE_MAX
var rising := true
var active := false
var hits_taken := 0     # 玩家撞了它几次
var bumps := 0          # 它撞了玩家几次

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _ring: MeshInstance3D     # 脚下的"耐心环"——廉价血条
var _label: Label3D           # 头顶名牌
var _charge_cd := CHARGE_EVERY
var _charging := false
var _charge_dir := Vector3.ZERO
var _knock_cd := 0.0
var _far_time := 0.0
var _dead := false
var _t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("boulder_bosses")  # 地图按组找 BOSS 画标记
	_build_model()
	_boss_say("一块巨石从地里隆起了。它看着你。它的耐心：%d/4" % patience)


func _build_model() -> void:
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	col.shape = shape
	col.position = Vector3(0, RADIUS * 0.6, 0)
	add_child(col)

	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 8
	_mesh.mesh = sphere
	_mesh.position = Vector3(0, RADIUS * 0.6, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.45, 0.42, 0.4)
	_mat.roughness = 1.0
	_mesh.material_override = _mat
	add_child(_mesh)

	# 廉价血条：脚下平放的环，耐心越少环越小
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 0.8
	torus.outer_radius = RADIUS * 1.05
	_ring.mesh = torus
	_ring.position = Vector3(0, 0.1, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.9, 0.25, 0.2)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.9, 0.2, 0.15)
	ring_mat.emission_energy_multiplier = 0.8
	_ring.material_override = ring_mat
	add_child(_ring)

	_label = Label3D.new()
	_label.text = "巨石（耐心 4/4）"
	_label.font_size = 44
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, RADIUS * 2.2, 0)
	_label.modulate = Color(1, 0.85, 0.8)
	add_child(_label)


## 从地下隆起：升到地面高度后开始追玩家
func rise_from_ground() -> void:
	var target_y: float = terrain.height_at(global_position.x, global_position.z)
	var tw := create_tween()
	tw.tween_property(self, "position:y", target_y, RISE_DURATION).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func():
		rising = false
		active = true
		if sfx != null:
			sfx.play("event"))


func _physics_process(delta: float) -> void:
	if _dead or player == null or terrain == null:
		return
	_t += delta
	_knock_cd = maxf(0.0, _knock_cd - delta)

	if rising:
		move_and_slide()
		return

	if not active:
		return

	# 重力（塌方时贴地即可）
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# —— 玩家跑太远：追累了 ——
	if dist > GIVEUP_DIST:
		_far_time += delta
		if _far_time >= GIVEUP_TIME:
			_give_up()
			return
	else:
		_far_time = 0.0

	# —— 行为：平时慢滚逼近，定时冲刺 ——
	if _charging:
		velocity.x = _charge_dir.x * CHARGE_SPEED
		velocity.z = _charge_dir.z * CHARGE_SPEED
		if fmod(_t, 0.5) < delta:
			_mat.albedo_color = Color(0.8, 0.2, 0.15)  # 冲刺时发红
	else:
		_charge_cd -= delta
		if _charge_cd <= 0.0 and dist < 45.0:
			_start_charge(to_player / maxf(dist, 0.01))
		var slow := ROLL_SPEED * (1.0 + 0.4 * (PATIENCE_MAX - patience) / float(PATIENCE_MAX))  # 越没耐心越快
		if dist > RADIUS + 1.5:
			var dir := to_player / maxf(dist, 0.01)
			velocity.x = dir.x * slow
			velocity.z = dir.z * slow
		else:
			velocity.x *= 0.9
			velocity.z *= 0.9

	# 滚动动画：绕垂直于速度的水平轴转
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() > 0.1:
		var axis := horiz.normalized().cross(Vector3.UP)
		_mesh.global_rotate(axis, horiz.length() * delta / RADIUS)

	# —— 撞到玩家：把它撞飞（不致命，很丢脸） ——
	if _knock_cd <= 0.0 and horiz.length() > 2.0:
		if dist < RADIUS + 1.6:
			_bump_player()

	move_and_slide()


func _start_charge(dir: Vector3) -> void:
	_charging = true
	_charge_dir = dir
	_charge_cd = CHARGE_EVERY
	_boss_say("巨石失去了一些矜持，朝你滚过来了！")
	if sfx != null:
		sfx.play("charge")
	# 冲刺 1.6 秒后收手
	var t := get_tree().create_timer(1.6)
	t.timeout.connect(func():
		_charging = false
		_mat.albedo_color = Color(0.45, 0.42, 0.4))


func _bump_player() -> void:
	_knock_cd = KNOCK_CD
	bumps += 1
	var dir := (player.global_position - global_position).normalized()
	player.velocity = dir * 14.0 + Vector3.UP * 8.0
	if sfx != null:
		sfx.play("moo")
	hud.show_message("被巨石碾了一下。疼倒是不疼，主要是丢脸。（被撞 %d 次）" % bumps, 2.5)
	_broadcast("被巨石「%s」碾飞了" % net.my_name if net != null and net.connected_ok else "")


## 玩家冲撞命中巨石（由 Area 检测，charge_hitbox 走不进来——这里由 game.gd/cow 桥接调用）
func on_player_charged(charge_dir: Vector3) -> void:
	if _dead or rising or not active:
		return
	patience -= 1
	hits_taken += 1
	# 被撞退
	velocity = charge_dir * 9.0 + Vector3.UP * 2.5
	_mat.albedo_color = Color(0.7, 0.55, 0.5)
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(func():
		if not _charging:
			_mat.albedo_color = Color(0.45, 0.42, 0.4))
	_refresh_bars()
	if sfx != null:
		sfx.play("event")
	if patience > 0:
		_boss_say("巨石被撞得不轻。它的耐心：%d/4" % patience)
	else:
		_defeat()


func _refresh_bars() -> void:
	_label.text = "巨石（耐心 %d/%d）" % [patience, PATIENCE_MAX]
	# 耐心环缩小
	var k := float(patience) / float(PATIENCE_MAX)
	_ring.scale = Vector3(maxf(k, 0.15), 1.0, maxf(k, 0.15))


func _defeat() -> void:
	_dead = true
	active = false
	_boss_say("巨石彻底失去了耐心！它骂骂咧咧地飞向了远方。")
	hud.show_message("你撞服了一块巨石。（没有奖励——哦等等，它掉东西了）", 4.5)
	if sfx != null:
		sfx.play("fly")
		sfx.play("ding")
	# 胜利演出：巨石升空飞走
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", global_position.y + 50.0, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation:y", rotation.y + TAU * 3.0, 2.2)
	tw.chain().tween_callback(queue_free)
	_broadcast("把巨石 BOSS 撞上了天")
	# 掉落奖励：在巨石原地（趁它还没飞远）
	boss_defeated.emit(global_position)


func _give_up() -> void:
	_dead = true
	active = false
	_boss_say("巨石追累了。它决定回去睡回笼觉。")
	hud.show_message("巨石觉得追一头牛不值得，回去睡了。（这算它赢还是你赢？）", 4.0)
	var tw := create_tween()
	tw.tween_property(self, "position:y", global_position.y - 8.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _boss_say(text: String) -> void:
	if hud != null:
		hud.show_message(text, 3.5)


func _broadcast(text: String) -> void:
	if net != null and net.connected_ok and text != "":
		net.send_game_event({"type": "boss", "name": net.my_name, "text": text})
