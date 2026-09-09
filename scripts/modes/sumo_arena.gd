class_name SumoArena
extends Node3D
## 牛牛相扑：悬浮圆台 + 陪练牛。把陪练牛（或联机的别的牛）撞下台即 KO，先到 5 KO 获胜。
## 联机判定哲学：每个人只判定"我被谁撞了"——物理永不同步，各撞各的，这是特性。

const ARENA_CENTER := Vector3(120.0, 45.0, 120.0)
const PLATFORM_RADIUS := 15.0
const SPAWN := Vector3(120.0, 48.5, 120.0)
const ELIM_Y := 15.0        # 低于此高度 = 出局
const NPC_COUNT := 5
const NPC_ONLINE := 2       # 联机时陪练牛减少——台上主要是真人
const KO_TO_WIN := 5

var game: Game
var player: PlayerCow
var hud: GameHUD
var sfx: SfxBank

var kos := 0
var falls := 0
var _player_knock_cd := 0.0
var _won := false
var _net_hooked := false


func _ready() -> void:
	# 悬浮圆台（低模、无装饰——灾难级擂台）
	var body := StaticBody3D.new()
	body.position = ARENA_CENTER
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = PLATFORM_RADIUS
	shape.height = 2.0
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = PLATFORM_RADIUS
	mesh.bottom_radius = PLATFORM_RADIUS * 0.7  # 略收底——像块蛋糕
	mesh.height = 2.0
	mesh.radial_segments = 18
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.4, 0.28)
	mat.roughness = 1.0
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

	# 陪练牛（联机时减员——台上主要是真人）
	var npc_count := NPC_ONLINE if NetConfig.enabled else NPC_COUNT
	for i in npc_count:
		var npc := NpcSumoCow.new()
		npc.arena = self
		add_child(npc)
		npc.global_position = respawn_point()

	_update_task()


func _physics_process(delta: float) -> void:
	_player_knock_cd = maxf(0.0, _player_knock_cd - delta)

	# 联机事件懒连接（NetManager 在 game.gd 末尾才创建，这里等它就绪）
	if not _net_hooked and game != null and game.net != null and game.net.connected_ok:
		game.net.game_event_received.connect(_on_net_event)
		_net_hooked = true

	# 玩家掉下台
	if player.global_position.y < ELIM_Y:
		player_fell()

	# 联机：别的牛冲撞命中我（各客户端自行判定）
	if game != null and game.net != null and game.net.connected_ok and player_knock_ok():
		var my_id := get_tree().get_multiplayer().get_unique_id()
		for pid in game.net.players:
			if pid == my_id:
				continue
			var st: Dictionary = game.net.players[pid]
			var rp: Vector3 = st["pos"]
			if st.get("act", "") == "charge" and rp.distance_to(player.global_position) < 2.3:
				knock_player((player.global_position - rp).normalized())
				_broadcast({"type": "ko", "attacker": st.get("name", "神秘小牛"), "victim": game.net.my_name})
				hud.show_message("你被撞飞了！物理引擎表示无辜。", 2.0)
				break


func player_knock_ok() -> bool:
	return _player_knock_cd <= 0.0


## 把玩家撞飞（方向为水平撞击方向）
func knock_player(dir: Vector3) -> void:
	player.velocity = dir * 15.0 + Vector3.UP * 7.0
	_player_knock_cd = 1.5
	if sfx != null:
		sfx.play("charge")


## 联机：我把别的真人撞下台（对方客户端判定并播报）→ 给我计 KO
func _on_net_event(data: Dictionary) -> void:
	if data.get("type", "") != "ko":
		return
	if game == null or game.net == null:
		return
	var attacker := str(data.get("attacker", ""))
	var victim := str(data.get("victim", ""))
	if attacker != game.net.my_name or victim == game.net.my_name:
		return
	if victim == "陪练牛":
		return  # 本地陪练牛 KO 在 on_npc_fell 里计过，不重复
	kos += 1
	if sfx != null:
		sfx.play("ding")
	hud.show_message("你把 %s 撞出了世界！KO %d/%d" % [victim, kos, KO_TO_WIN], 2.5)
	_update_task()
	if kos >= KO_TO_WIN and not _won:
		_win()


## 陪练牛的冲撞命中了玩家
func on_player_knocked(npc: NpcSumoCow) -> void:
	if not player_knock_ok():
		return
	var dir := player.global_position - npc.global_position
	dir.y = 0.0
	knock_player(dir.normalized() if dir.length() > 0.01 else Vector3.BACK)
	hud.show_message("你被陪练牛撞飞了！颜面何在。", 2.5)


## 对撞互弹（NpcSumoCow 调用）：双方同时冲撞 → 一起弹飞，后出手者多退 30%
func on_mutual_charge(npc: NpcSumoCow) -> void:
	var bounce_dir := npc.global_position - player.global_position
	bounce_dir.y = 0.0
	if bounce_dir.length() < 0.01:
		bounce_dir = Vector3.BACK
	bounce_dir = bounce_dir.normalized()
	var n_late := npc._charged_at < (PlayerCow.CHARGE_TIME - player._charge_timer)  # npc 后出手
	var p_mul := 1.3 if not n_late else 1.0
	var n_mul := 1.3 if n_late else 1.0
	player.velocity = -bounce_dir * 16.0 * p_mul + Vector3.UP * 6.0
	_player_knock_cd = 1.5
	npc.velocity = bounce_dir * 16.0 * n_mul + Vector3.UP * 6.0
	npc.fell_reason = "bounce"
	npc.knocked_timer = 1.2
	npc.charge_timer = 0.0
	if sfx != null:
		sfx.play("charge")
	if hud != null:
		hud.show_message("对撞！双双弹开（后出手的多飞 30%）。", 2.0)

## 玩家冲撞命中陪练牛（音效/播报）
func on_npc_knocked(_npc: NpcSumoCow) -> void:
	if sfx != null:
		sfx.play("charge")
	if randf() < 0.4:
		hud.show_message("命中！陪练牛飞出去了。", 1.5)


## 陪练牛掉出台面 → 计 KO
func on_npc_fell(npc: NpcSumoCow) -> void:
	if npc.respawn_timer > 0.0:
		return
	npc.respawn_timer = 2.0
	npc.visible = false
	npc.velocity = Vector3.ZERO
	kos += 1
	if sfx != null:
		sfx.play("ding")
	hud.show_message("你把一头陪练牛撞出了世界！KO %d/%d" % [kos, KO_TO_WIN], 2.5)
	_broadcast({"type": "ko", "attacker": _my_name(), "victim": "陪练牛"})
	_update_task()
	if kos >= KO_TO_WIN and not _won:
		_win()


## 玩家自己掉下台
func player_fell() -> void:
	falls += 1
	hud.show_message("你掉下了擂台。这当然是特性。", 2.5)
	_broadcast({"type": "ko", "attacker": "虚空", "victim": _my_name()})
	player.global_position = SPAWN
	player.velocity = Vector3.ZERO
	_update_task()


## 台面上随机重生点
func respawn_point() -> Vector3:
	var ang := randf() * TAU
	var r := randf_range(2.0, PLATFORM_RADIUS - 3.0)
	return Vector3(ARENA_CENTER.x + cos(ang) * r, ARENA_CENTER.y + 2.5, ARENA_CENTER.z + sin(ang) * r)


func _win() -> void:
	_won = true
	if game != null and game.career != null:
		game.career.note_win()  # 生涯：相扑夺冠
	hud.show_message("你赢了！（并没有奖励）4 秒后重新开始。", 4.0)
	var t := get_tree().create_timer(4.0)
	await t.timeout
	if not is_inside_tree():
		return
	kos = 0
	falls = 0
	_won = false
	_update_task()


func _my_name() -> String:
	if game != null and game.net != null and game.net.connected_ok:
		return game.net.my_name
	return "你"


func _broadcast(data: Dictionary) -> void:
	if game != null and game.net != null and game.net.connected_ok:
		game.net.send_game_event(data)


func _update_task() -> void:
	hud.set_task("【牛牛相扑】把陪练牛撞下台！\nKO：%d/%d · 被击落：%d\n（联机时：冲撞也能把别的牛撞飞——在他自己的屏幕里）" % [kos, KO_TO_WIN, falls])
