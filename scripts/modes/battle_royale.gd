class_name BattleRoyale
extends Node3D
## 哞哞大逃杀：圈外是"未加载区域"——帧率归零即闪退出局，最后加载的牛获胜。
## 圈时间线锚定真实时钟（unix % 300）：联机各端天然同步（误差 < 1 秒），
## 晚进场的玩家直接跳到当前阶段——没有同步代码，这是特性。
## 圆环会穿山、陪练牛各自为战、每个客户端都有自己的物理——这当然也是特性。

const ZONE_RADII: Array[float] = [90.0, 60.0, 40.0, 25.0, 12.0, 5.0]
const GRACE_TIME := 20.0    # 每阶段收缩前等待
const SHRINK_TIME := 10.0   # 收缩耗时
const FINAL_HOLD := 60.0    # 最终圈保持时间
const FINAL_SHRINK := 60.0  # 终极收缩耗时（5 → 0.5 米，服务器"回收内存"）
const CYCLE := 300.0        # 时钟周期 = 6*30 + 60 + 60（wrap 后回到初始圈，"新的一局"）

const FPS_MAX := 60.0
const FPS_DECAY := 12.0   # 圈外每秒掉帧
const FPS_REGEN := 25.0   # 圈内每秒回帧
const NPC_OUT_TIME := 6.0 # 陪练牛圈外出局时长
const NPC_COUNT := 5      # 单机陪练牛数
const NPC_ONLINE := 3     # 联机陪练牛数（其他是真人）
const CLOCK_SEED := 20260903

var game: Game
var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank

var center := Vector2.ZERO      # 当前圈心（XZ）
var radius := ZONE_RADII[0]
var stage := 0                  # 0-5 = 六个圈阶段，6 = 终极收缩
var phase := 0                  # 0=等待收缩 1=收缩中
var fps := FPS_MAX
var eliminated := false
var won := false
var over := false               # 本局个人已结束（出局或胜利）
var rank := 0                   # 出局名次
var alive_npc := 0
var clock_override := -1.0      # 测试用（>= 0 时替代真实时钟）

var _centers: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()
var _ring: MeshInstance3D
var _ring_mesh: TorusMesh
var _dome: MeshInstance3D
var _dome_mesh: CylinderMesh
var _last_vis := Vector3(-9999.0, 0.0, -9999.0)  # 上次可视化的 (cx, r, cz)
var _hud_acc := 0.0
var _net_hooked := false
var _others_elim := 0           # 联机：其他玩家已闪退数
var kills := 0                  # 你的击杀数（处决/撞死/联机 KO）
var _knock_cd := 0.0            # 被撞击退/伤害冷却
var last_hitter := ""          # 最后命中我的人（出局时记击杀账）


func _ready() -> void:
	_build_centers()
	_build_visuals()
	_spawn_npcs()
	_apply_timeline(timeline_t())
	_refresh_visuals(true)


# ————————————————— 时间线（真实时钟驱动，联机免同步） —————————————————

func timeline_t() -> float:
	if clock_override >= 0.0:
		return clock_override
	return fmod(float(Time.get_unix_time_from_system()), CYCLE)


func _apply_timeline(t: float) -> void:
	var shrink_total := ZONE_RADII.size() * (GRACE_TIME + SHRINK_TIME)  # 180
	var last := ZONE_RADII.size() - 1
	if t < shrink_total:
		stage = int(t / (GRACE_TIME + SHRINK_TIME))
		var lt := fmod(t, GRACE_TIME + SHRINK_TIME)
		if lt < GRACE_TIME:
			phase = 0
			radius = ZONE_RADII[stage]
			center = _centers[stage]
		else:
			phase = 1
			# 最后一圈没有下一阶段，收缩目标钳制在自身（保持 5 米等终极收缩）
			var next := mini(stage + 1, ZONE_RADII.size() - 1)
			var k: float = (lt - GRACE_TIME) / SHRINK_TIME
			radius = lerpf(ZONE_RADII[stage], ZONE_RADII[next], k)
			center = _centers[stage].lerp(_centers[next], k)
	elif t < shrink_total + FINAL_HOLD:
		stage = last
		phase = 0
		radius = ZONE_RADII[last]
		center = _centers[last]
	else:
		stage = ZONE_RADII.size()
		phase = 1
		var k := clampf((t - shrink_total - FINAL_HOLD) / FINAL_SHRINK, 0.0, 1.0)
		radius = lerpf(ZONE_RADII[last], 0.5, k)
		center = _centers[last]


## 下一阶段目标圈心（地图白色虚线圈标注用）
func next_center() -> Vector2:
	return _centers[mini(stage + 1, _centers.size() - 1)]


# ————————————————— 主循环 —————————————————

func _physics_process(delta: float) -> void:
	if over:
		return
	# 联机事件懒连接（NetManager 在 game.gd 末尾才创建，这里等它就绪）
	if not _net_hooked and game != null and game.net != null and game.net.connected_ok:
		game.net.game_event_received.connect(_on_net_event)
		_net_hooked = true

	# 真人互撞（同相扑哲学：各端只判"我被谁撞了"）
	_knock_cd = maxf(_knock_cd - delta, 0.0)
	if game != null and game.net != null and game.net.connected_ok and player != null and not player._dead and _knock_cd <= 0.0:
		var my_id := get_tree().get_multiplayer().get_unique_id()
		for pid in game.net.players:
			if pid == my_id:
				continue
			var st: Dictionary = game.net.players[pid]
			var rp: Vector3 = st["pos"]
			if st.get("act", "") == "charge" and rp.distance_to(player.global_position) < 2.3:
				on_human_hit(pid, st)
				break

	_apply_timeline(timeline_t())
	_refresh_visuals()

	# 掉出世界 = 掉进真正的未加载区域
	if player.global_position.y < -20.0:
		_eliminate("你掉出了世界。这次连加载都不会加载了。")
		return

	var d := Vector2(player.global_position.x, player.global_position.z).distance_to(center)
	if d > radius:
		fps -= FPS_DECAY * delta
		if fps <= 0.0:
			_eliminate("帧率归零——你掉进了未加载区域，闪退。")
			return
	else:
		fps = minf(fps + FPS_REGEN * delta, FPS_MAX)

	_hud_acc += delta
	if _hud_acc >= 0.1:
		_hud_acc = 0.0
		_update_hud(d)

	_check_win()


func _eliminate(reason: String) -> void:
	_finish_elim(reason, "")


## 玩家血量归零出局（game.gd 经 player_died 回调；hitter 为空时用 last_hitter）
func player_killed(hitter := "") -> void:
	if hitter == "":
		hitter = last_hitter
	if over:
		return
	_finish_elim("你被%s撞成了马赛克。" % (hitter if hitter != "" else "神秘力量"), hitter)


## 统一出局结算：演出 + 广播（击杀账归 last_hitter）
func _finish_elim(reason: String, hitter := "") -> void:
	if over:
		return
	over = true
	eliminated = true
	rank = _alive_count()
	fps = 0.0
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	# 观战视角：拉高俯瞰（看别人怎么死）
	if game != null and game.camera != null:
		game.camera.dist = 26.0
		game.camera.pitch = 0.9
	if hud != null:
		hud.show_message("%s（第 %d 名）\n按 R 重开" % [reason, rank], 8.0)
	if sfx != null:
		sfx.play("moo")
	if hitter != "":
		_broadcast({"type": "ko", "attacker": hitter, "victim": _my_name()})
	_broadcast({"type": "zone_elim", "name": _my_name(), "rank": rank})
	_update_hud(0.0)


# ————————————————— 竞技受击（P2 接线） —————————————————

## 击退玩家（无角 10 m/s；有角 15 m/s——角不只是伤害）
func _knock_player(dir: Vector3, speed: float) -> void:
	player.velocity = dir * speed + Vector3.UP * 6.0
	if sfx != null:
		sfx.play("charge")


## 真人冲撞命中我：掉 1 血 + 击退（击飞出圈 = fps 掉空 = 出局）
func on_human_hit(pid: int, st: Dictionary) -> void:
	if _knock_cd > 0.0 or player == null or player._dead or player.invincible_left > 0.0:
		return
	_knock_cd = 1.2
	var rp: Vector3 = st["pos"]
	var dir := player.global_position - rp
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.BACK
	dir = dir.normalized()
	_knock_player(dir, 15.0 if player.effective_horn() > 0 else 10.0)
	last_hitter = str(st.get("name", "神秘小牛"))
	player.take_combat_hit(1, _net_node_of(pid))
	if hud != null and not player._dead:
		hud.show_message("你被%s撞飞了！角呢？" % last_hitter, 2.0)


## 陪练牛冲撞命中我：同样掉 1 血 + 击退
func on_npc_hits_player(npc: NpcRoyaleCow) -> void:
	if _knock_cd > 0.0 or player == null or player._dead or player.invincible_left > 0.0:
		return
	_knock_cd = 1.2
	var dir := player.global_position - npc.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.BACK
	dir = dir.normalized()
	_knock_player(dir, 15.0)
	last_hitter = npc.cow_name
	player.take_combat_hit(1, npc)
	if hud != null and not player._dead:
		hud.show_message("你被%s撞飞了！物理引擎表示感谢。" % last_hitter, 2.0)


func _net_node_of(pid: int) -> Node3D:
	if game != null:
		var n = game._net_players.get(pid)
		if n is Node3D:
			return n as Node3D
	return null


## 玩家处决/撞死陪练牛 → 广播 KO（击杀计入我）
func _on_npc_combat_defeated(by: Node3D, npc: NpcRoyaleCow) -> void:
	if by is PlayerCow and not npc.is_queued_for_deletion():
		_broadcast({"type": "ko", "attacker": _my_name(), "victim": npc.cow_name})


func _check_win() -> void:
	if alive_npc > 0:
		return
	if game != null and game.net != null and game.net.connected_ok:
		var others := game.net.players.size() - 1
		if others - _others_elim > 0:
			return
	over = true
	won = true
	if game != null and game.career != null:
		game.career.note_win()  # 生涯：大逃杀吃鸡
	if hud != null:
		hud.show_message("大逃杀胜利！你是最后加载的牛。（依然没有奖励）", 8.0)
	if sfx != null:
		sfx.play("ding")
	_broadcast({"type": "zone_win", "name": _my_name()})
	_update_hud(0.0)


## 陪练牛出局（圈外超时）
func on_npc_elim(npc: NpcRoyaleCow) -> void:
	if npc.is_queued_for_deletion():
		return  # 防重复淘汰
	alive_npc -= 1
	if hud != null:
		hud.show_message("%s 掉出加载范围，闪退了。" % npc.cow_name, 3.0)
	_broadcast({"type": "zone_elim", "name": npc.cow_name, "rank": _alive_count()})
	npc.queue_free()
	_update_hud(0.0)


## 联机：闪退计数（胜利判定）+ KO 击杀结算
func _on_net_event(data: Dictionary) -> void:
	var typ := str(data.get("type", ""))
	if typ == "zone_elim":
		var nm := str(data.get("name", ""))
		if game == null or game.net == null or nm == game.net.my_name:
			return
		_others_elim += 1
		if hud != null:
			hud.show_message("%s 闪退了。" % nm, 3.0)
	elif typ == "ko":
		var attacker := str(data.get("attacker", ""))
		var victim := str(data.get("victim", ""))
		if attacker == _my_name() and victim != _my_name():
			kills += 1
			if hud != null:
				hud.show_message("击杀：%s！击杀数 %d。" % [victim, kills], 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


# ————————————————— HUD —————————————————

func _update_hud(d: float) -> void:
	if hud == null:
		return
	var lines: Array[String] = []
	lines.append("【哞哞大逃杀】剩余 %d 头牛 · 你的击杀 %d" % [_alive_count(), kills])
	if over:
		if won:
			lines.append("胜利！你是最后加载的牛。")
		else:
			lines.append("你已闪退（第 %d 名）。" % rank)
		lines.append("按 R 重开")
		hud.set_task("\n".join(lines))
		return
	var t := timeline_t()
	var shrink_total := ZONE_RADII.size() * (GRACE_TIME + SHRINK_TIME)
	if t < shrink_total:
		if phase == 0:
			var wait := GRACE_TIME - fmod(t, GRACE_TIME + SHRINK_TIME)
			var nr: float = ZONE_RADII[mini(stage + 1, ZONE_RADII.size() - 1)]
			lines.append("下一圈：%.0f 秒后收缩（→ %.0f 米）" % [wait, nr])
		else:
			lines.append("圈正在收缩……（%.0f 米）" % radius)
	elif t < shrink_total + FINAL_HOLD:
		lines.append("最终圈（5 米）：%.0f 秒后终极收缩" % [shrink_total + FINAL_HOLD - t])
	else:
		lines.append("终极收缩！%.1f 米——服务器正在回收内存" % radius)
	var fps_line := "帧率：%d fps" % int(fps)
	if d > radius:
		fps_line += "  ⚠ 你在未加载区域！快回圈！"
	lines.append(fps_line)
	lines.append("距圈心 %d 米 / 圈半径 %.0f 米" % [int(d), radius])
	hud.set_task("\n".join(lines))


# ————————————————— 构建 —————————————————

## 圈心序列：固定种子 → 联机各端完全一致
func _build_centers() -> void:
	_rng.seed = CLOCK_SEED
	_centers.append(Vector2.ZERO)
	for i in range(1, ZONE_RADII.size()):
		var max_off := (ZONE_RADII[i - 1] - ZONE_RADII[i]) * 0.7
		var ang := _rng.randf_range(0.0, TAU)
		var off := _rng.randf_range(0.0, max_off)
		var c := _centers[i - 1] + Vector2(cos(ang), sin(ang)) * off
		var lim := 100.0 - ZONE_RADII[i] - 2.0  # 圈整体留在世界内
		c = c.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		_centers.append(c)


## 发光圆环（安全边界）+ 半透明绿色安全罩
func _build_visuals() -> void:
	_ring_mesh = TorusMesh.new()
	_ring_mesh.rings = 64
	_ring_mesh.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.9, 0.3)
	mat.emission_energy_multiplier = 1.1
	mat.roughness = 0.6
	_ring = MeshInstance3D.new()
	_ring.name = "ZoneRing"
	_ring.mesh = _ring_mesh
	_ring.material_override = mat
	add_child(_ring)

	_dome_mesh = CylinderMesh.new()
	_dome_mesh.radial_segments = 48
	_dome_mesh.height = 80.0
	var dmat := StandardMaterial3D.new()
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.25, 1.0, 0.45, 0.07)
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dmat.roughness = 1.0
	_dome = MeshInstance3D.new()
	_dome.name = "ZoneDome"
	_dome.mesh = _dome_mesh
	_dome.material_override = dmat
	add_child(_dome)


## 陪练牛：随机撒在初始圈内
func _spawn_npcs() -> void:
	var n := NPC_COUNT if not NetConfig.enabled else NPC_ONLINE
	for i in n:
		var npc := NpcRoyaleCow.new()
		npc.arena = self
		npc.cow_name = "陪练牛%d" % (i + 1)
		add_child(npc)
		var ang := TAU * i / float(n) + randf_range(-0.4, 0.4)
		var r := randf_range(18.0, 60.0)
		var px := cos(ang) * r
		var pz := sin(ang) * r
		npc.global_position = Vector3(px, terrain.height_at(px, pz) + 1.2, pz)
		npc.combat_defeated.connect(_on_npc_combat_defeated.bind(npc))
	alive_npc = n


## 可视化刷新（半径/圈心变化时才重建网格）
func _refresh_visuals(force := false) -> void:
	var key := Vector3(center.x, radius, center.y)
	if not force and key == _last_vis:
		return
	_last_vis = key
	var y := 0.0
	if terrain != null:
		y = terrain.height_at(center.x, center.y)
	_ring_mesh.outer_radius = radius + 0.9
	_ring_mesh.inner_radius = maxf(radius - 0.9, 0.1)
	_ring.global_position = Vector3(center.x, y + 1.2, center.y)
	_dome_mesh.top_radius = radius
	_dome_mesh.bottom_radius = radius
	_dome.global_position = Vector3(center.x, y + 40.0, center.y)


# ————————————————— 工具 —————————————————

func _broadcast(data: Dictionary) -> void:
	if game != null and game.net != null and game.net.connected_ok:
		game.net.send_game_event(data)


func _my_name() -> String:
	if game != null and game.net != null and game.net.connected_ok:
		return game.net.my_name
	return "你"


## 存活牛数（自己 + 陪练 + 联机真人）
func _alive_count() -> int:
	var n := 1 + alive_npc
	if game != null and game.net != null and game.net.connected_ok:
		n += maxi(game.net.players.size() - 1 - _others_elim, 0)
	return n
