extends SceneTree
## 第 12 轮测试：道具杀伤力（号角/炸弹）+ 恋爱剧情（心上牛全流程）。
## 运行：Godot --headless --path D:\牛来 --script res://tests/round12_test.gd

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
	print("==== 牛走 · 第 12 轮测试（杀伤力+恋爱） ====")
	NetConfig.enabled = false
	ModeConfig.mode = "free"
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(2.0).timeout

	var player: PlayerCow = game.player
	var items: ItemManager = game.items
	var romance: Romance = game.romance
	_check(romance != null, "自由模式创建恋爱剧情", str(romance))
	_check(romance.crush != null and is_instance_valid(romance.crush), "心上牛已入场")
	# 武器测试别误伤心上牛（它也是 npcs——关战斗，后面剧情测试手动触发事故）
	romance.crush.combat_enabled = false

	# ———— 1. 道具杀伤力：号角 ————
	var cow1 := NpcCow.new()
	game.add_child(cow1)
	cow1.global_position = player.global_position + Vector3(5, 0, 0)
	cow1.hp = 3
	var hp_before := cow1.hp
	items._use_horn()
	await create_timer(0.3).timeout
	_check(cow1.hp < hp_before or cow1.is_dead_combat(), "号角波及 NPC 牛（掉血/致死）",
		"hp %d → %d" % [hp_before, cow1.hp])

	# 号角 2 格伤害（背面减半 → 至少掉 1）
	var cow2 := NpcCow.new()
	game.add_child(cow2)
	cow2.global_position = player.global_position + Vector3(6, 0, 0)
	cow2.hp = 3
	cow2.combat_take_hit(player, Vector3(1, 0, 0), 2)
	_check(cow2.hp < 3, "战斗判定原样可用（2 格伤害）", str(cow2.hp))
	cow1.queue_free()
	cow2.queue_free()

	# ———— 2. 道具杀伤力：笨笨炸弹 ————
	var cow3 := NpcCow.new()
	game.add_child(cow3)
	cow3.global_position = player.global_position + Vector3(3, 0, 0)
	cow3.model.rotation.y = -PI / 2.0  # 面朝玩家：正面挨打，1 格伤害全额生效
	var hp3 := cow3.hp
	items._use_bomb()
	await create_timer(0.5).timeout
	Engine.time_scale = 1.0  # 炸弹慢动作别影响后续测试
	_check(cow3.hp < hp3 or cow3.is_dead_combat(), "炸弹波及 NPC 牛", "hp %d → %d" % [hp3, cow3.hp])
	cow3.queue_free()

	# 半径外不受伤
	var cow4 := NpcCow.new()
	game.add_child(cow4)
	cow4.global_position = player.global_position + Vector3(60, 0, 60)
	cow4.hp = 3
	items._blast_combatants(15.0, 1, "测试")
	_check(cow4.hp == 3, "半径外毫发无伤", str(cow4.hp))
	cow4.queue_free()

	# ———— 3. 恋爱：打招呼 → 认识 ————
	var crush: CrushCow = romance.crush
	# 号角把玩家炸飞了——先放回地面（否则人在天上，距离判定全失效）
	player.velocity = Vector3.ZERO
	player._flying = false
	player._fly_bounces = 0
	player.global_position = Vector3(0, game.terrain.height_at(0, 0) + 1.5, 0)
	# 心上牛放到玩家身边（重置被波及的击退/速度）
	crush.knock_left = 0.0
	crush.velocity = Vector3.ZERO
	crush.global_position = player.global_position + Vector3(1.5, 0, 0)
	crush.home = crush.global_position
	await create_timer(0.5).timeout
	_check(romance.stage == 0, "初始阶段 0（未搭话）", str(romance.stage))
	_check(player.talk_target_active, "靠近时 E 键让给对话（吃草被门控）")
	romance._on_talk()
	_check(romance._dlg_lines.size() >= 3, "对话框打开（有台词）", str(romance._dlg_lines.size()))
	# 连按 E 走完对话
	for i in 10:
		romance._advance_dialogue()
	_check(romance.stage == 1, "打招呼完成 → 阶段 1（认识了）", str(romance.stage))

	# ———— 4. 恋爱：一起吃草 ×3 → 散步 ————
	romance._on_talk()  # 邀请一起吃草
	for i in 10:
		romance._advance_dialogue()
	_check(romance.stage == 2, "邀请完成 → 阶段 2（一起吃草中）", str(romance.stage))
	for i in 3:
		romance._on_player_ate(10)
	_check(romance.stage == 3, "一起吃草 ×3 → 阶段 3（散步中）", str(romance.stage))
	_check(crush.follow_target == player, "散步时心上牛跟着玩家")

	# 散步走完 → 可表白
	romance._walk_left = 0.01
	await create_timer(0.2).timeout
	_check(romance.stage == 4, "散步结束 → 阶段 4（可表白）", str(romance.stage))
	_check(crush.follow_target == null, "表白前它停下脚步")

	# ———— 5. 恋爱：表白 → 情侣 ————
	romance._on_talk()
	for i in 10:
		romance._advance_dialogue()
	_check(romance.stage == 5, "表白成功 → 阶段 5（情侣）", str(romance.stage))
	_check(crush.follow_target == player, "情侣：永远跟随")

	# ———— 6. 恋爱事故：情侣间撞一下 = 情趣（不清零） ————
	romance._on_crush_hurt(player)
	_check(romance.stage == 5, "情侣被撞：不清零（打情骂俏）", str(romance.stage))

	# ———— 7. 恋爱事故：对象没了 → 换下一头 ————
	romance._on_crush_died(player)
	_check(romance.crush == null and romance.stage == 0, "对象没了 → 等待下一头（阶段清零）",
		"crush=%s stage=%d" % [str(romance.crush), romance.stage])
	romance._respawn_in = 0.01
	await create_timer(0.2).timeout
	_check(romance.crush != null and is_instance_valid(romance.crush), "下一头心上牛准时到场")

	# ———— 8. 恋爱事故：撞了约会对象 → 好感清零 ————
	var crush2: CrushCow = romance.crush
	crush2.global_position = player.global_position + Vector3(1.5, 0, 0)
	romance._set_stage_raw(4)  # 假装已经走到表白前
	romance._on_crush_hurt(player)
	_check(romance.stage == 0, "撞了约会对象 → 好感清零", str(romance.stage))

	# ———— 9. 联机播报格式 ————
	var chat = game.chat
	var lines_before: int = chat._log_box.get_child_count()
	game._on_game_event({"type": "romance", "name": "哞王42", "crush": "哞莉", "text": "表白成功，脱单了"})
	await create_timer(0.2).timeout
	var got := false
	for c in chat._log_box.get_children():
		if c is Label and "哞王42" in c.text and "哞莉" in c.text and "脱单" in c.text:
			got = true
	_check(got, "联机播报：恋爱事件进聊天流", "")

	# ———— 10. 道具文案更新 ————
	var horn_desc: String = ItemDefs.INFO["horn"]["desc"]
	var bomb_desc: String = ItemDefs.INFO["bomb"]["desc"]
	_check("牛和狼" in horn_desc, "号角说明含杀伤力提示", horn_desc)
	_check("牛和狼" in bomb_desc, "炸弹说明含杀伤力提示", bomb_desc)

	game.queue_free()
	await create_timer(1.0).timeout
	_finish()


func _finish() -> void:
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
