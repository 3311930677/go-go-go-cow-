class_name MeteorManager
extends Node
## 天降正义：天上往下砸彩色方块（石头/树/说不定还有整个牛棚的零件）。
## 每个客户端的陨石只存在于自己屏幕里——物理永不同步，各砸各的，这是特性。

const METEOR_GROUP := "meteors"
const MAX_METEORS := 40
const DEATH_RADIUS := 1.9
const DEATH_SPEED := 10.0

var game: Game
var player: PlayerCow
var hud: GameHUD
var sfx: SfxBank

var elapsed := 0.0
var best := 0.0
var deaths := 0
var invuln := 2.0
var _spawn_timer := 1.0
var _hud_acc := 0.0


func _physics_process(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	elapsed += delta

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_meteor()
		_spawn_timer = maxf(0.35, 1.4 - elapsed * 0.012) * randf_range(0.7, 1.3)

	_check_hits()
	_cleanup()

	_hud_acc += delta
	if _hud_acc > 0.25:
		_hud_acc = 0.0
		_update_task()


## 生成一颗陨石：出现在玩家上空随机方位，带一点预判提前量
func _spawn_meteor() -> void:
	var meteors := get_tree().get_nodes_in_group(METEOR_GROUP)
	if meteors.size() >= MAX_METEORS:
		(meteors[0] as Node).queue_free()

	var size := Vector3.ONE * randf_range(0.8, 2.0)
	var m := RigidBody3D.new()
	m.add_to_group(METEOR_GROUP)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	m.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(randf(), 0.65, 0.95)  # 随机鲜艳——廉价刺眼
	mat.roughness = 1.0
	mi.material_override = mat
	m.add_child(mi)
	add_child(m)

	var ang := randf() * TAU
	var r := randf_range(2.0, 12.0)
	m.global_position = Vector3(
		player.global_position.x + cos(ang) * r,
		player.global_position.y + 34.0,
		player.global_position.z + sin(ang) * r)
	var lead := player.global_position + player.velocity * 0.35
	m.linear_velocity = (lead - m.global_position).normalized() * randf_range(16.0, 24.0)
	m.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


## 命中判定：高速陨石贴身即"被砸中"
func _check_hits() -> void:
	if invuln > 0.0:
		return
	for node in get_tree().get_nodes_in_group(METEOR_GROUP):
		var rb := node as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		if rb.linear_velocity.length() > DEATH_SPEED \
				and rb.global_position.distance_to(player.global_position) < DEATH_RADIUS:
			die(rb.linear_velocity)
			break


## 被砸中：表演式飞天 + 计分 + 播报
func die(vel: Vector3) -> void:
	deaths += 1
	best = maxf(best, elapsed)
	invuln = 3.0
	# 生涯：本局存活时长（最高纪录）
	if game != null and game.career != null:
		game.career.set_max("survival_best", elapsed)
	player.velocity = Vector3(vel.x, 0.0, vel.z) * 0.8 + Vector3.UP * 14.0
	if sfx != null:
		sfx.play("horn")
	hud.show_message("你被天降正义砸中了！存活 %.1f 秒（最长 %.1f 秒）" % [elapsed, best], 3.5)
	if game != null and game.net != null and game.net.connected_ok:
		game.net.send_game_event({"type": "meteor", "name": game.net.my_name, "time": elapsed})
	elapsed = 0.0
	_update_task()


## 清理远离的陨石
func _cleanup() -> void:
	for node in get_tree().get_nodes_in_group(METEOR_GROUP):
		var n := node as Node3D
		if n != null and n.global_position.y < player.global_position.y - 60.0:
			n.queue_free()


func _update_task() -> void:
	hud.set_task("【天降正义】躲开天上掉下来的东西。\n存活 %.1f 秒 · 被砸 %d 次 · 最长 %.1f 秒" % [elapsed, deaths, best])
