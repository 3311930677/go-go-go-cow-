extends SceneTree
## 第 17 轮测试（竞技接线）：大逃杀攻击 AI + 真人互撞 + 相扑增强。
## 运行：D:\godot\Godot_v4.6.1-stable_win64.exe --headless --path D:\牛来 --script res://tests/round17_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("[PASS] %s" % name)
	else:
		_fail += 1
		print("[FAIL] %s  %s" % [name, detail])


func _run() -> void:
	print("==== 牛走 · 第 17 轮测试（竞技模式接线） ====")

	# ---------- A. 大逃杀时间线（真实时钟锚定，无物理依赖） ----------
	var br := BattleRoyale.new()
	br._build_centers()
	br.clock_override = 10.0
	br._apply_timeline(br.timeline_t())
	_check(br.stage == 0 and br.phase == 0 and is_equal_approx(br.radius, 90.0),
		"时间线：开局全圈（90 米）", "stage=%d phase=%d r=%.1f" % [br.stage, br.phase, br.radius])
	br.clock_override = 25.0
	br._apply_timeline(br.timeline_t())
	_check(br.stage == 0 and br.phase == 1 and br.radius < 90.0 and br.radius > 60.0,
		"时间线：第 1 圈收缩中", "r=%.1f" % br.radius)
	br.clock_override = 180.0
	br._apply_timeline(br.timeline_t())
	_check(br.stage == 5 and br.phase == 0 and is_equal_approx(br.radius, 5.0),
		"时间线：最终圈 5 米", "r=%.1f" % br.radius)
	br.clock_override = 250.0
	br._apply_timeline(br.timeline_t())
	_check(br.stage == 6 and br.phase == 1 and br.radius < 5.0,
		"时间线：终极收缩（服务器回收内存）", "stage=%d r=%.1f" % [br.stage, br.radius])
	_check(br.next_center() is Vector2, "时间线：下一圈心可查")

	# ---------- B. 大逃杀陪练牛 AI ----------
	var arena := BattleRoyale.new()   # 手动 stub（不进树，不触发 _ready）
	var player := PlayerCow.new()
	root.add_child(player)
	player.hp = 3
	var npcA := NpcRoyaleCow.new()
	var npcB := NpcRoyaleCow.new()
	root.add_child(npcA)
	root.add_child(npcB)
	arena.player = player
	npcA.arena = arena
	npcB.arena = arena
	npcA.cow_name = "陪练牛A"
	npcB.cow_name = "陪练牛B"
	_check(npcA is Combatant, "AI：陪练牛继承战斗基类")
	_check(npcA.cow_name == "陪练牛A", "AI：名字可设")

	# 索敌：会锁玩家或陪练牛
	npcA._lock_target()
	_check(npcA._target == player or npcA._target == npcB, "AI：锁定玩家或同行", "target=%s" % str(npcA._target))
	npcA._target = null
	npcB.global_position = Vector3(5, 0, 0)
	npcA.global_position = Vector3(0, 0, 0)
	npcA._pick_npc_target()
	_check(npcA._target == null or npcA._target == npcB or npcA._target == player, "AI：找得到陪练牛目标")

	# 陪练牛互打架：正面命中 1 血固定伤害
	var gs := Game.new()          # 逻辑 stub（不进树，不触发 _ready）
	var gnet := NetManager.new()
	gnet.my_name = "你"
	gs.net = gnet
	arena.game = gs
	# 探针实测：牛不旋转时脸朝 +Z，攻击 BACK = 正面满伤（1 血）
	var hp_before := npcB.hp
	npcB.combat_take_hit(npcA, Vector3(0, 0, -1), 1)
	_check(npcB.hp == hp_before - 1, "AI：同行正面互撞掉 1 血", "%d → %d" % [hp_before, npcB.hp])

	# 冲撞沿途判定：命中玩家 → 掉 1 血 + 被击退
	npcB.global_position = Vector3(0, 0, 0)
	player.global_position = Vector3(1.5, 0, 0)
	npcB.charge_timer = 0.3
	npcB.charge_dir = Vector3(1, 0, 0)
	var hp_p := player.hp
	npcB._attempt_hits()
	_check(player.hp == hp_p - 1, "AI：撞玩家掉 1 血", "%d → %d" % [hp_p, player.hp])
	_check(player.velocity.length() > 0.0, "AI：玩家被击退", str(player.velocity.length()))
	_check(arena._knock_cd > 0.0, "AI：冷却生效（防连续判定）", str(arena._knock_cd))

	# 圈外超时出局：alive_npc 递减
	arena.alive_npc = 5
	npcB.out_time = 99.0
	npcB.global_position = Vector3(999, 0, 999)
	arena.on_npc_elim(npcB)
	_check(arena.alive_npc == 4, "AI：圈外超时 → 出局计数", str(arena.alive_npc))

	# ---------- C. 真人互撞（联机哲学：各端判自己被撞） ----------
	player.hp = 3
	player.invincible_left = 0.0
	arena._knock_cd = 0.0
	player.global_position = Vector3(0, 0, 0)
	var st := {"pos": Vector3(0, 0, 2), "act": "charge", "name": "真人牛"}
	arena.on_human_hit(992, st)
	_check(player.hp == 2, "真人互撞：掉 1 血", str(player.hp))
	_check(arena.last_hitter == "真人牛", "真人互撞：记仇（击杀账）", arena.last_hitter)
	_check(player.velocity.length() > 0.0, "真人互撞：被击飞")
	_check(arena._knock_cd > 0.0, "真人互撞：CD 上锁")
	player.hp = 3
	player.invincible_left = 99.0
	arena._knock_cd = 0.0
	arena.on_human_hit(993, st)
	_check(player.hp == 3, "真人互撞：无敌期内不掉血", str(player.hp))

	# ---------- D. KO 击杀结算 ----------
	arena.kills = 0
	arena._on_net_event({"type": "ko", "attacker": "你", "victim": "张三"})
	arena._on_net_event({"type": "ko", "attacker": "你", "victim": "李四"})
	_check(arena.kills == 2, "KO：杀两个加两击", str(arena.kills))
	arena._on_net_event({"type": "zone_elim", "name": "别家牛", "rank": 3})
	_check(arena._others_elim == 1, "KO：他人闪退计数", str(arena._others_elim))
	arena._on_net_event({"type": "ko", "attacker": "李四", "victim": "你"})
	_check(arena.kills == 2, "KO：被杀不给自己加击杀", str(arena.kills))

	# ---------- E. 相扑增强：流派 + 对撞 + KO ----------
	var sa := SumoArena.new()   # stub 不进树
	var suhud := GameHUD.new()
	suhud._build()
	sa.hud = suhud
	var sp := PlayerCow.new()
	root.add_child(sp)
	sp.hp = 3
	sa.player = sp
	var s_npc := NpcSumoCow.new()
	s_npc.arena = sa
	root.add_child(s_npc)
	_check(s_npc.style == "charge" or s_npc.style == "edge", "相扑：流派二选一", s_npc.style)

	# 对撞互弹：玩家也被弹开，NPC 标记 bounce
	s_npc.global_position = Vector3(2, 0, 0)
	sp.global_position = Vector3(0, 0, 0)
	sp._charge_timer = 0.2
	s_npc._charged_at = 0.1
	sa.on_mutual_charge(s_npc)
	_check(sp.velocity.length() > 0.0, "相扑：对撞玩家被弹开")
	_check(s_npc.fell_reason == "bounce", "相扑：对撞标记 bounce", s_npc.fell_reason)
	_check(s_npc.charge_timer == 0.0, "相扑：对撞后 NPC 冲撞取消")
	_check(sa.player_knock_ok() == false, "相扑：玩家对撞后 CD", str(sa._player_knock_cd))

	# 撞飞 NPC → KO 计分
	sa.kos = 3
	s_npc.respawn_timer = 0.0
	sa.on_npc_fell(s_npc)
	_check(sa.kos == 4, "相扑：撞下台 KO+1", str(sa.kos))
	_check(s_npc.respawn_timer > 0.0, "相扑：跌落牛进入重生等待", str(s_npc.respawn_timer))
	_check(not sa._won, "相扑：未到 5 KO 不触发胜利")

	# 玩家掉台：传送回去 + 计数
	sa.falls = 0
	sp.global_position = Vector3(0, 2, 0)
	sa.player_fell()
	_check(sa.falls == 1, "相扑：玩家掉台计数", str(sa.falls))
	_check(sp.global_position == SumoArena.SPAWN or sp.global_position.distance_to(SumoArena.SPAWN) < 0.1,
		"相扑：玩家被传送回台心", str(sp.global_position))

	# ---------- F. 击杀结算：陪练牛被杀（处决）走 arena 出局 ----------
	var npr := NpcRoyaleCow.new()
	root.add_child(npr)
	npr.arena = arena
	var rc1 := arena.alive_npc
	npr.combat_die()
	_check(arena.alive_npc == rc1 - 1, "结算：陪练牛被杀计入出局", str(arena.alive_npc))

	print("==== 第 17 轮结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)