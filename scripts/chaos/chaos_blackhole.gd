class_name ChaosBlackhole
extends Node3D
## 混沌黑洞：草原中心定时刷出，吸入周围的动态物体。
## 玩家需要冲撞进去把它撞碎（3 下），否则 60 秒后它"吃饱了"——
## 把吸到的 NPC 吐到一个新的离谱地方（毛蛋/云雀的"传送"黑历史）。
## 撞碎掉落：弹射号角（黑洞内部塞满了历代飞天失败的牛留下的号角）。

signal smashed(at: Vector3)   # 撞碎位置（ItemManager 在这摆奖励）
signal swallowed_npc(npc: Node3D)  # NPC 被吞（ChaosManager 负责善后/播报）
signal ate_and_left  # 60 秒没被撞碎：吃饱飘走了（调度器清引用，好让下一个刷出来）

const RADIUS := 1.8
const SUCTION_RADIUS := 22.0
const SUCTION_FORCE := 14.0
const PLAYER_PULL := 3.5       # 对玩家的拉力（温和——主要威胁是道具被吸走）
const HITS_TO_SMASH := 3
const LIFETIME := 60.0        # 60 秒不撞碎就"吃饱"

var player: PlayerCow
var hud: GameHUD
var sfx: SfxBank
var net: NetManager

var hits_left := HITS_TO_SMASH
var _life := LIFETIME
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _aura: MeshInstance3D     # 吸力范围提示（暗紫半透明球）
var _label: Label3D
var _t := 0.0
var _dead := false


func _ready() -> void:
	_build()


func _build() -> void:
	# 本体：深黑球——什么都进得来，什么都出不去（包括光和逻辑）
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 10
	_mesh.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.02, 0.0, 0.06)
	_mat.emission_enabled = true
	_mat.emission = Color(0.35, 0.05, 0.5)
	_mat.emission_energy_multiplier = 1.2
	_mesh.material_override = _mat
	add_child(_mesh)

	# 吸力范围：暗紫半透明大球（看得见危险区——这游戏难得的良心）
	_aura = MeshInstance3D.new()
	var aura_sphere := SphereMesh.new()
	aura_sphere.radius = SUCTION_RADIUS
	aura_sphere.height = SUCTION_RADIUS * 2.0
	aura_sphere.radial_segments = 24
	aura_sphere.rings = 12
	_aura.mesh = aura_sphere
	var aura_mat := StandardMaterial3D.new()
	aura_mat.albedo_color = Color(0.4, 0.1, 0.6, 0.08)
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_mat.emission_enabled = true
	aura_mat.emission = Color(0.3, 0.05, 0.45)
	aura_mat.emission_energy_multiplier = 0.25
	aura_mat.no_depth_test = true
	_aura.material_override = aura_mat
	add_child(_aura)

	_label = Label3D.new()
	_label.text = "混沌黑洞（撞它 %d 下）" % hits_left
	_label.font_size = 40
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, RADIUS * 2.4, 0)
	_label.modulate = Color(0.85, 0.6, 1.0)
	add_child(_label)

	# 可撞物理体（玩家冲撞判定用——黑科技：黑洞也有实体，很合理）
	var solid := StaticBody3D.new()
	solid.name = "HittableBody"
	var scol := CollisionShape3D.new()
	var sshape := SphereShape3D.new()
	sshape.radius = RADIUS * 1.2
	scol.shape = sshape
	scol.position = Vector3(0, RADIUS, 0)
	solid.add_child(scol)
	add_child(solid)

	if sfx != null:
		sfx.play("event")


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	_life -= delta

	# 自转 + 脉动
	_mesh.rotation.y += 2.0 * delta
	var k := 1.0 + sin(_t * 3.0) * 0.08
	_mesh.scale = Vector3(k, k, k)
	_aura.rotation.y -= 0.4 * delta

	# 吸力：动态道具被拽向中心（转着吸——廉价漩涡感）
	for body in get_tree().get_nodes_in_group("dynamic_props"):
		if body is RigidBody3D:
			var rb := body as RigidBody3D
			var d := rb.global_position.distance_to(global_position)
			if d < SUCTION_RADIUS and d > 0.5:
				var pull := (global_position - rb.global_position).normalized()
				var strength := SUCTION_FORCE * (1.0 - d / SUCTION_RADIUS) * rb.mass
				rb.apply_central_force(pull * strength)
				# 切向分量：转着吸
				var tangent := pull.cross(Vector3.UP)
				rb.apply_central_force(tangent * strength * 0.4)

	# 温和拉玩家（威胁感，但不夺走操作）
	if player != null:
		var pd := player.global_position.distance_to(global_position)
		if pd < SUCTION_RADIUS and pd > 1.0:
			var pull_dir := (global_position - player.global_position).normalized()
			player.velocity += pull_dir * PLAYER_PULL * delta * 10.0

	# 倒计时警示
	if _life <= 10.0 and fmod(_t, 5.0) < delta:
		_label.text = "混沌黑洞（%d 秒后吃饱）" % int(_life)

	if _life <= 0.0:
		_eat_and_leave()


## 玩家冲撞命中（由 PlayerCow 的 charged 信号桥接，或直接调用）
func on_player_charged() -> void:
	if _dead:
		return
	hits_left -= 1
	# 被撞时闪一下
	_mat.emission_energy_multiplier = 3.0
	var t := get_tree().create_timer(0.2)
	t.timeout.connect(func():
		if not _dead:
			_mat.emission_energy_multiplier = 1.2)
	if sfx != null:
		sfx.play("event")
	if hits_left > 0:
		_label.text = "混沌黑洞（再撞 %d 下）" % hits_left
		if hud != null:
			hud.show_message("黑洞被撞得晃了一下。（还差 %d 下）" % hits_left, 2.0)
	else:
		_smash()


func _smash() -> void:
	_dead = true
	if hud != null:
		hud.show_message("黑洞被撞碎了！里面掉出来一些历代飞天失败的遗物。", 4.0)
	if sfx != null:
		sfx.play("ding")
		sfx.play("event")
	_broadcast("把混沌黑洞撞碎了")
	# 破碎演出：快速膨胀后炸开消失
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3(3.0, 3.0, 3.0), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mesh, "scale", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	smashed.emit(global_position)


## 60 秒没被撞碎：吞掉身边的 NPC，吃饱走牛
func _eat_and_leave() -> void:
	_dead = true
	ate_and_left.emit()
	if hud != null:
		hud.show_message("黑洞吃饱了，慢悠悠地飘走了。\n（刚才被吸走的东西，出现在了别的地方）", 4.5)
	if sfx != null:
		sfx.play("fly")
	_broadcast("放任混沌黑洞吃饱了，现在它带着大家的东西跑了")
	# 吞 NPC：把范围内最近的 NPC 吐到新地方（交给 ChaosManager 善后）
	if player != null:
		for node in get_parent().get_children():
			if node is Lark or node is Alpaca or node is NpcCow:
				if node.global_position.distance_to(global_position) < SUCTION_RADIUS:
					swallowed_npc.emit(node)
	# 飘走演出
	var tw := create_tween()
	tw.tween_property(self, "position:y", global_position.y + 40.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_mesh, "scale", Vector3(0.1, 0.1, 0.1), 3.0)
	tw.tween_callback(queue_free)


func _broadcast(text: String) -> void:
	if net != null and net.connected_ok:
		net.send_game_event({"type": "chaos", "name": net.my_name, "text": text})
