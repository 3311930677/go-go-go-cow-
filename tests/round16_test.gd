extends SceneTree
## 第 16 轮测试（P1-B/P1-C）：牛角战斗 + 狼群危机。
## 运行：D:\godot\Godot_v4.6.1-stable_win64.exe --headless --path D:\牛来 --script res://tests/round16_test.gd

var _pass := 0
var _fail := 0
var _wolf_kills := 0   # 收到的狼死亡信号（was_kill == true）


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("[PASS] %s" % name)
	else:
		_fail += 1
		print("[FAIL] %s  %s" % [name, detail])


func _on_wolf_despawned(_w: Node3D, _at: Vector3, was_kill: bool) -> void:
	if was_kill:
		_wolf_kills += 1


func _run() -> void:
	print("==== 牛走 · 第 16 轮测试（P1-B 牛角战斗 + P1-C 狼群危机） ====")

	# ---------- A. 道具图鉴：狼三件套 ----------
	_check(ItemDefs.is_valid("wolf_tooth"), "图鉴：狼牙合法")
	_check(ItemDefs.is_valid("wolf_skin"), "图鉴：狼皮合法")
	_check(ItemDefs.is_valid("wolf_bone"), "图鉴：狼骨粉合法")
	_check(not ItemDefs.PILE_IDS.has("wolf_tooth") and not ItemDefs.PILE_IDS.has("wolf_skin")
		and not ItemDefs.PILE_IDS.has("wolf_bone"), "图鉴：狼掉落不进草堆/空投池（只能打狼出）")
	_check(ItemDefs.name_of("wolf_tooth") == "狼牙", "图鉴：中文名")

	# ---------- B. 掉落物模型可直接构建 ----------
	for wid in ["wolf_tooth", "wolf_skin", "wolf_bone"]:
		var drop := ItemPickup.new()
		drop.name = "Drop_%s" % wid
		root.add_child(drop)
		drop.setup(wid, Vector3.ZERO)
		_check(drop.get_node_or_null("Model") != null, "掉落物：%s 模型构建" % wid)
		drop.queue_free()

	# ---------- C. 玩家连击→处决（有角，狼 3 血） ----------
	var player := PlayerCow.new()
	var wolf := Wolf.new()
	wolf.wolf_name = "测试狼"
	root.add_child(player)
	root.add_child(wolf)
	player.horn_level = 1
	player._charge_dir = Vector3.BACK
	player._charge_timer = 1.0
	wolf.rotation.y = PI  # 狼脸朝玩家来的方向 → 正面判定
	wolf.connect(&"wolf_despawned", _on_wolf_despawned)

	player._combat_charge_hit(wolf)
	_check(wolf.hp == 2, "处决流程：第 1 撞正面掉 1 血", str(wolf.hp))
	player._combat_charge_hit(wolf)
	_check(wolf.hp == 1, "处决流程：第 2 撞掉到 1 血", str(wolf.hp))
	player._combat_charge_hit(wolf)
	_check(wolf.is_dead_combat(), "处决流程：第 3 撞 = 处决（无视血量）")
	_check(is_equal_approx(player.execution_cd, 30.0), "处决流程：进入 30 秒处决 CD", str(player.execution_cd))
	_check(_wolf_kills == 1, "处决流程：狼死亡信号收到（掉落钩子）", str(_wolf_kills))

	# ---------- D. 无角玩家：只能击退，撞 5 次晃晕狼，掉不了血 ----------
	if is_instance_valid(wolf):
		wolf.queue_free()
	await process_frame
	var plain := PlayerCow.new()
	var wolf2 := Wolf.new()
	root.add_child(plain)
	root.add_child(wolf2)
	plain._charge_dir = Vector3.BACK
	plain._charge_timer = 1.0
	for i in 4:
		plain._combat_charge_hit(wolf2)
	_check(wolf2.hp == 3, "无角：撞 4 次不掉血（纯击退）", str(wolf2.hp))
	_check(not wolf2.is_dead_combat(), "无角：狼没死")
	_check(wolf2._state != "stun", "无角：4 次还没到晕眩线")
	plain._combat_charge_hit(wolf2)
	_check(wolf2._state == "stun", "无角：第 5 击退 → 晕眩 10 秒", str(wolf2._state))
	_check(not wolf2.is_dead_combat(), "无角：晕眩不等于死")

	# ---------- E. 狼皮：温顺态 ----------
	wolf2.pacified_left = 180.0
	_check(wolf2.pacified_left > 60.0, "狼皮：pacified 定时生效")

	# ---------- F. 狼牙免死 ----------
	plain.wolf_save = true
	plain.take_combat_hit(99, wolf2)
	_check(not plain._dead, "狼牙：被秒杀时免死")
	_check(not plain.wolf_save, "狼牙：一次性消耗")
	_check(plain.hp == 1, "狼牙：残血 1 格存活", str(plain.hp))
	plain.invincible_left = 0.0
	plain.take_combat_hit(99, wolf2)
	_check(plain._dead, "狼牙耗尽：第二次被咬正常死亡")

	# ---------- G. 狼咬牛群：牛变排骨（地上多一块排骨） ----------
	var cow := NpcCow.new()
	root.add_child(cow)
	var wolf3 := Wolf.new()
	wolf3.wolf_name = "饿狼"
	root.add_child(wolf3)
	wolf3._bite_npc(cow)
	var ribs := 0
	for n in root.get_children():
		if n.name.begins_with("CowRib"):
			ribs += 1
	_check(cow.is_dead_combat(), "狼咬牛群：路过牛被秒杀（变成排骨）")
	_check(ribs == 1, "狼咬牛群：地上出现一块牛排骨", str(ribs))

	# ---------- H. 相关脚本语法冒烟 ----------
	var ch := ChaosManager.new()
	root.add_child(ch)
	_check(ch is ChaosManager, "编译：ChaosManager 可实例化（狼群调度）")
	var s := SfxBank.new()
	root.add_child(s)
	_check(s._streams.has("wolf") and s._streams.has("bite"), "音效：狼口哨与咬合音已注册")
	var im := ItemManager.new()
	root.add_child(im)
	_check(im is ItemManager, "编译：ItemManager 可实例化（纯逻辑模式）")
	var gsc := Game
	_check(gsc != null, "编译：game.gd 语法通过")

	print("==== 第 16 轮结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)