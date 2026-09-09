class_name ItemManager
extends Node
## 道具系统总管：3 格背包（1/2/3 使用）、发光草堆刷新、六种道具效果、
## 获取钩子（撞树根 / 高空坠物 / 飞天常客 / 原地转圈 / 吃草概率 / 全任务奖励）。
## 荒诞守则：道具效果只改本地——联机时别人只看到播报，这是特性。

const SLOT_COUNT := 3
const STACK_MAX := 3

const PILE_COUNT := 7
const PILE_RESPAWN := 45.0
const PILE_DRIFT := 3.0             # 重生漂移半径（致敬穿模）
const PILE_MIN_R := 35.0            # 草堆离出生点最小距离
const PILE_MAX_R := 90.0            # 最大距离

const CHARGE_HITS_FOR_POTION := 10  # 撞飞多少个东西掉穿模药水
const FLY_COUNT_FOR_HORN := 3       # 累计飞天几次掉弹射号角
const HIGH_ALT_FOR_BOOTS := 25.0    # 飞天高度掉反向重力靴
const SPIN_TURNS_FOR_REWIND := 3    # 原地转几圈掉时光回闪
const SPIN_GAP := 0.5               # 转圈中断判定（秒）
const BOMB_EAT_CHANCE := 0.01       # 吃草"拉"出笨笨炸弹的概率

const GHOST_DURATION := 5.0
const BOOTS_DURATION := 8.0
const BOMB_DURATION := 3.0
const BOMB_TIME_SCALE := 0.35
const BOMB_RADIUS := 15.0
const HORN_BLAST_RADIUS := 20.0
const HORN_LAUNCH_VELOCITY := 24.0
const REWIND_SECONDS := 5.0
const REWIND_SAMPLE_DT := 0.2

const FULL_MSG_COOLDOWN := 3.0
const WOLF_SKIN_TIME := 180.0   # 狼皮：3 分钟狼不主动咬你

## 商店出生点（地图标记共用这个常量）
const SHOP_POS := Vector2(58.0, -58.0)

## 竞技模式（相扑/躲陨石/竞速/大逃杀）：无商店、无获取钩子，
## 改为开局送 1 个 + 定时空投补给——玩家在哪，空投投哪（台上、空中都行）。
var competitive := false

const AIRDROP_INTERVAL := 40.0
const AIRDROP_FIRST := 15.0
const AIRDROP_HEIGHT := 22.0
const AIRDROP_DRIFT := 5.0  # 空投漂移小一点——相扑台边缘外全是深渊，别投歪了

## 外部依赖（由 game.gd 注入；离线逻辑测试可不注入）
var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank
var camera: CowCamera
var chat: ChatBox
var net: NetManager
var career: Career  # 生涯统计（道具使用/购物）——game.gd 注入；可为 null

## 背包：[{id: String, count: int}]，长度 ≤ 3
var inventory: Array = []

var bar: ItemBar
var fx: RewindFx
var shop: CowShop

var gold_spent := 0
var _companion: Node3D = null

# —— 获取进度 ——
var _charge_hits := 0
var _boots_dropped := false
var _horn_dropped := false
var _rewind_dropped := false
var _whistle_granted := false

# —— 运行时状态 ——
var _boots_left := 0.0
var _bomb_left := 0.0
var _time_scale_held := false
var _rewind_samples: Array = []
var _rewind_acc := 0.0
var _spin_acc := 0.0
var _last_yaw := 0.0
var _last_spin_at := -100.0
var _piles: Array = []
var _respawn_queue: Array = []
var _elapsed := 0.0
var _full_msg_cd := 0.0
var _next_airdrop := AIRDROP_INTERVAL
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# 纯逻辑模式（headless 单元测试不注入 player）：到此为止
	if player == null:
		return
	bar = ItemBar.new()
	bar.name = "ItemBar"
	add_child(bar)

	fx = RewindFx.new()
	fx.name = "RewindFx"
	add_child(fx)

	if competitive:
		# 竞技模式：开局送一个 + 空投补给（无商店、无获取钩子）
		var gift := ItemDefs.random_pile_id(_rng)
		add_item(gift)
		if hud != null:
			hud.show_message("开局奖励：%s（按 1/2/3 使用。悬停道具栏看说明）" % ItemDefs.name_of(gift), 4.5)
		_next_airdrop = AIRDROP_FIRST
		return

	shop = CowShop.new()
	shop.name = "CowShop"
	shop.player = player
	shop.items = self
	shop.hud = hud
	shop.sfx = sfx
	add_child(shop)
	shop.place(SHOP_POS.x, SHOP_POS.y)

	_spawn_piles()

	# 获取钩子
	player.charged_prop.connect(_on_charged_prop)
	player.grass_eaten.connect(_on_grass_eaten)


func _process(delta: float) -> void:
	if player == null:
		return
	_elapsed += delta
	if _full_msg_cd > 0.0:
		_full_msg_cd -= delta

	_update_rewind_buffer(delta)
	_update_boots(delta)
	_update_bomb(delta)

	if competitive:
		_update_airdrop(delta)
	else:
		_update_acquisitions()
		_update_spin(delta)
		_update_respawns()


## 空投补给（竞技模式）：玩家附近从天而降一份道具——像一片不太可靠的羽毛
func _update_airdrop(delta: float) -> void:
	_next_airdrop -= delta
	if _next_airdrop > 0.0:
		return
	_next_airdrop = AIRDROP_INTERVAL
	var p := player.global_position
	p.x += _rng.randf_range(-AIRDROP_DRIFT, AIRDROP_DRIFT)
	p.z += _rng.randf_range(-AIRDROP_DRIFT, AIRDROP_DRIFT)
	if terrain != null:
		var gy: float = terrain.height_at(p.x, p.z) + 0.2
		# 空投目标点比玩家更高时（相扑台/空中），以玩家高度为地面
		var floor_y: float = maxf(gy, player.global_position.y + 0.2)
		p.y = floor_y + AIRDROP_HEIGHT
		var pile := ItemPickup.new()
		pile.name = "Airdrop%d" % int(_elapsed)
		pile.picked.connect(_on_pile_picked)
		add_child(pile)
		pile.setup(ItemDefs.random_pile_id(_rng), p)
		pile.start_airdrop(floor_y)
		if hud != null:
			hud.show_message("补给空投降落中——去抢。", 3.0)


# ————————————————— 背包 —————————————————

## 捡/买道具：同类叠加（上限 3），满员即拒（不占新槽）；否则占新槽
func add_item(id: String) -> bool:
	if not ItemDefs.is_valid(id):
		return false
	for entry in inventory:
		if entry["id"] == id:
			if entry["count"] >= STACK_MAX:
				return false  # 同类满了——牛蹄没那么大
			entry["count"] += 1
			_notify_inventory()
			return true
	if inventory.size() < SLOT_COUNT:
		inventory.append({"id": id, "count": 1})
		_notify_inventory()
		return true
	return false


## 使用指定槽位（i ∈ 0..2）。效果施加失败（如回闪没历史）不消耗。
func use_slot(i: int) -> void:
	if i < 0 or i >= inventory.size():
		if hud != null:
			hud.show_message("那个槽是空的。就像牛的钱包。", 1.5)
		return
	var entry: Dictionary = inventory[i]
	if _apply_effect(entry["id"]):
		if career != null:
			career.add("items_used")
		entry["count"] -= 1
		if entry["count"] <= 0:
			inventory.remove_at(i)
		_notify_inventory()


func count_of(id: String) -> int:
	var n := 0
	for entry in inventory:
		if entry["id"] == id:
			n += entry["count"]
	return n


func _notify_inventory() -> void:
	if bar != null:
		bar.refresh(inventory)


## 全任务奖励：伙伴哨子
func grant_whistle() -> void:
	if _whistle_granted:
		return
	_whistle_granted = true
	if add_item("whistle"):
		if hud != null:
			hud.show_message("任务全部完成的奖励：伙伴哨子。（可惜梦快醒了）", 4.0)
	else:
		_drop_at_player("whistle", "伙伴哨子掉在了地上——牛蹄满了，先腾个位置。")


func shop_menu_open() -> bool:
	return shop != null and shop.menu_open


## ————————————————— 商店（由 CowShop 回调） —————————————————

func shop_price(id: String) -> int:
	var base: int = CowShop.BASE_PRICES.get(id, 3)
	return base + (shop.purchases if shop != null else 0)


func gold_balance() -> int:
	if terrain == null:
		return 0
	return maxf(0, terrain.golden_eaten - gold_spent)


func spend_gold(price: int) -> void:
	gold_spent += price
	if career != null:
		career.add("purchases")  # 生涯：商店成交一笔


# ————————————————— 草堆 —————————————————

func _spawn_piles() -> void:
	for i in PILE_COUNT:
		var pile := ItemPickup.new()
		pile.name = "ItemPile%d" % i
		pile.picked.connect(_on_pile_picked)
		add_child(pile)
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(PILE_MIN_R, PILE_MAX_R)
		var x := cos(ang) * r
		var z := sin(ang) * r
		pile.setup(ItemDefs.random_pile_id(_rng),
			Vector3(x, terrain.height_at(x, z) + 0.2, z))
		_piles.append(pile)


func _on_pile_picked(pile: ItemPickup, item_id: String) -> void:
	if add_item(item_id):
		if hud != null:
			# 吐槽 + 效果说明——不然谁知道瓶里装的是啥
			hud.show_message("%s\n%s" % [ItemDefs.quip_of(item_id),
				str(ItemDefs.INFO.get(item_id, {}).get("desc", ""))], 4.5)
		if sfx != null:
			sfx.play("click")
		pile.set_active(false)
		if not competitive:
			# 自由模式：草堆 45 秒后漂移重生；竞技模式空投用完即散
			_respawn_queue.append({"at": _elapsed + PILE_RESPAWN, "pile": pile})
		else:
			pile.queue_free()
	else:
		if _elapsed >= _full_msg_cd:
			_full_msg_cd = _elapsed + FULL_MSG_COOLDOWN
			if hud != null:
				hud.show_message("牛蹄已满（三个槽）。用掉一个再捡。", 2.5)
		pile.set_active(true)  # 草堆留着，人先腾位置


func _update_respawns() -> void:
	var i := 0
	while i < _respawn_queue.size():
		var e: Dictionary = _respawn_queue[i]
		if _elapsed >= e["at"]:
			var pile: ItemPickup = e["pile"]
			_respawn_queue.remove_at(i)
			_respawn_pile(pile)
		else:
			i += 1


## 重生：换一种道具 + 位置漂移（每次都不在老地方——穿模的世界坐标不稳）
func _respawn_pile(pile: ItemPickup) -> void:
	var p := pile.global_position
	p.x += _rng.randf_range(-PILE_DRIFT, PILE_DRIFT)
	p.z += _rng.randf_range(-PILE_DRIFT, PILE_DRIFT)
	p.x = clampf(p.x, -95.0, 95.0)
	p.z = clampf(p.z, -95.0, 95.0)
	p.y = terrain.height_at(p.x, p.z) + 0.2
	pile.setup(ItemDefs.random_pile_id(_rng), p)


## 在玩家附近掉落一个道具草堆
func _drop_at_player(id: String, msg: String) -> void:
	if hud != null:
		hud.show_message(msg, 3.5)
	var pile := ItemPickup.new()
	pile.name = "DroppedItem"
	pile.picked.connect(_on_pile_picked)
	add_child(pile)
	var p := player.global_position + Vector3(_rng.randf_range(1.0, 2.5), 0.5, _rng.randf_range(1.0, 2.5))
	p.y = terrain.height_at(p.x, p.z) + 0.2
	pile.setup(id, p)


## 奖励掉落计数（命名用）：Godot 同名子节点会被改成 "@Node3D@123"，测试按前缀数不清
var _reward_count := 0


## 在指定位置掉落奖励（黑洞碎片/巨石战利品）。id 为空 = 随机道具。
func drop_reward_near(at: Vector3, id: String) -> void:
	if player == null or terrain == null:
		return
	if id == "":
		id = ItemDefs.random_pile_id(_rng)
	var pile := ItemPickup.new()
	_reward_count += 1
	pile.name = "RewardItem%d" % _reward_count
	pile.picked.connect(_on_pile_picked)
	add_child(pile)
	var p := at + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
	p.y = terrain.height_at(p.x, p.z) + 0.2
	pile.setup(id, p)


# ————————————————— 获取钩子 —————————————————

func _on_charged_prop(_body: Node3D) -> void:
	_charge_hits += 1
	if _charge_hits >= CHARGE_HITS_FOR_POTION:
		_charge_hits = 0
		_drop_at_player("potion", "撞飞了 %d 个东西——树根里掉出来一瓶绿油油的玩意儿。" % CHARGE_HITS_FOR_POTION)


func _on_grass_eaten(gained: int) -> void:
	if gained <= 0:
		return
	if _rng.randf() < BOMB_EAT_CHANCE:
		if add_item("bomb"):
			if hud != null:
				hud.show_message("吃草吃出了一枚……带笑脸的。祝你用得开心。", 3.5)
		else:
			_drop_at_player("bomb", "吃出一枚笨笨炸弹，但牛蹄满了——先放地上。")


func _update_acquisitions() -> void:
	# 25 米高空（飞天状态）：红靴子从天而降
	if not _boots_dropped and player._flying and player.global_position.y >= HIGH_ALT_FOR_BOOTS:
		_boots_dropped = true
		_drop_at_player("boots", "25 米高空掉下来一只红靴子（左右还是反着穿的）。哪来的？")
	# 飞天常客：三次飞天奖励号角
	if not _horn_dropped and player.fly_count >= FLY_COUNT_FOR_HORN:
		_horn_dropped = true
		_drop_at_player("horn", "飞天三次——资深飞天牛，奖励一个破号角。")


## 原地转圈检测（在地面转过 3 整圈 → 掉时光回闪）
func _update_spin(delta: float) -> void:
	var yaw_now: float = player.model.rotation.y
	var dy := wrapf(yaw_now - _last_yaw, -PI, PI)
	_last_yaw = yaw_now
	if not player.is_on_floor():
		_spin_acc = 0.0
		return
	if absf(dy) > 0.005:
		if _elapsed - _last_spin_at > SPIN_GAP:
			_spin_acc = 0.0  # 停太久——重新计
		_spin_acc += absf(dy)
		_last_spin_at = _elapsed
		if _spin_acc >= SPIN_TURNS_FOR_REWIND * TAU and not _rewind_dropped:
			_rewind_dropped = true
			_spin_acc = 0.0
			_drop_at_player("rewind", "你原地转了三圈，转出来一个沙漏。（？？？）")


# ————————————————— 道具效果 —————————————————

## 施加效果。返回 false = 施加失败（不消耗道具）。
## 纯逻辑模式（无 player 注入）视为施加成功，只消耗——方便单测背包。
func _apply_effect(id: String) -> bool:
	if player == null:
		return true
	match id:
		"potion":
			_use_potion()
		"boots":
			_use_boots()
		"horn":
			_use_horn()
		"rewind":
			if not _use_rewind():
				return false
		"bomb":
			_use_bomb()
		"whistle":
			_use_whistle()
		"wolf_tooth":
			_use_wolf_tooth()
		"wolf_skin":
			_use_wolf_skin()
		"wolf_bone":
			_use_wolf_bone()
	return true


func _use_potion() -> void:
	player.start_ghost(GHOST_DURATION)
	if hud != null:
		hud.show_message("你变半透明了。墙开始怀疑自己。", 3.0)
	if sfx != null:
		sfx.play("event")
	_broadcast("喝下了穿模药水，正在挑战墙的权威")


func _use_boots() -> void:
	player.gravity_scale = -1.0
	_boots_left = BOOTS_DURATION
	if camera != null:
		camera.roll = 0.26
	if hud != null:
		hud.show_message("重力反了！天花板……这地图没有天花板。", 3.0)
	if sfx != null:
		sfx.play("fly")
	_broadcast("穿上了反向重力靴，正在挑战牛顿的权威")


func _update_boots(delta: float) -> void:
	if _boots_left <= 0.0:
		return
	_boots_left -= delta
	if _boots_left <= 0.0:
		player.gravity_scale = 1.0
		if camera != null:
			camera.roll = 0.0
		if hud != null:
			hud.show_message("重力回来了。腿软了一下。", 2.5)


func _use_horn() -> void:
	# 爆炸：方圆 20 米的物体统统震飞
	for body in get_tree().get_nodes_in_group("dynamic_props"):
		if body is RigidBody3D:
			var rb := body as RigidBody3D
			var d := rb.global_position.distance_to(player.global_position)
			if d < HORN_BLAST_RADIUS:
				var dir := (rb.global_position - player.global_position).normalized()
				var power := 26.0 * (1.0 - d / HORN_BLAST_RADIUS) + 8.0
				rb.apply_central_impulse(dir * power + Vector3.UP * 9.0)
				rb.apply_torque_impulse(Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20)))
	# 杀伤力：爆炸波及范围内的 NPC 牛和狼挨一记重的（2 格伤害 + 击飞）
	_blast_combatants(HORN_BLAST_RADIUS, 2, "号角")
	# 自己就是烟花
	player._start_fly()
	player.velocity.y = HORN_LAUNCH_VELOCITY
	if hud != null:
		hud.show_message("号角炸了。你就是烟花。", 3.0)
	if sfx != null:
		sfx.play("fly")
		sfx.play("event")
	_broadcast("吹响了弹射号角，一头牛正在升空")


func _update_rewind_buffer(delta: float) -> void:
	_rewind_acc += delta
	if _rewind_acc < REWIND_SAMPLE_DT:
		return
	_rewind_acc = 0.0
	_rewind_samples.append({
		"pos": player.global_position,
		"vel": player.velocity,
	})
	var max_samples := int(REWIND_SECONDS / REWIND_SAMPLE_DT)
	while _rewind_samples.size() > max_samples:
		_rewind_samples.pop_front()


func _use_rewind() -> bool:
	if _rewind_samples.is_empty():
		if hud != null:
			hud.show_message("时间还没开始流动，回闪个啥？", 2.0)
		return false
	var oldest: Dictionary = _rewind_samples[0]
	player.global_position = oldest["pos"]
	player.velocity = oldest["vel"]
	player._flying = false
	player._fly_bounces = 0
	if camera != null:
		camera.call_deferred("_snap_to_target")
	if fx != null:
		fx.play(1.4)
	if hud != null:
		hud.show_message("咔——时间倒带。这几秒就当没发生过。", 3.0)
	if sfx != null:
		sfx.play("event")
	_rewind_samples.clear()
	_broadcast("使用了时光回闪。刚才的事就当没发生")
	return true


func _use_bomb() -> void:
	_bomb_left = BOMB_DURATION
	var online := net != null and net.connected_ok
	if not online:
		Engine.time_scale = BOMB_TIME_SCALE
		_time_scale_held = true
		if hud != null:
			hud.show_message("笨笨炸弹：慢动作 + 物理痉挛。谁都不许快。", 3.0)
	else:
		if hud != null:
			hud.show_message("笨笨炸弹（联机版）：慢动作懒得同步，各位脑补。物理照样痉挛。", 3.5)
	# 杀伤力：爆炸半径内的 NPC 牛和狼挨一记轻的（1 格伤害 + 击退）
	_blast_combatants(BOMB_RADIUS, 1, "笨笨炸弹")
	if sfx != null:
		sfx.play("event")
	_broadcast("扔出了笨笨炸弹，方圆十五米的物理都在抽搐")


## 爆炸杀伤：半径内的可战斗生物（NPC 牛/狼/心上牛）统一吃 combat_take_hit。
## 伤害是本地判定的（本作哲学：物理永不同步），联机时别人只看到播报。
func _blast_combatants(radius: float, power: int, weapon: String) -> void:
	if player == null:
		return
	var hits := 0
	for group in ["npcs", "wolves"]:
		for body in get_tree().get_nodes_in_group(group):
			if body is Combatant and not (body as Combatant).is_dead_combat():
				var c := body as Combatant
				var d := c.global_position.distance_to(player.global_position)
				if d < radius:
					var dir := (c.global_position - player.global_position).normalized()
					if c.combat_take_hit(player, dir, power) > 0:
						hits += 1
	if hits > 0 and hud != null:
		hud.show_message("%s 波及了 %d 个倒霉蛋。它们会回来的（大概）。" % [weapon, hits], 2.5)


func _update_bomb(delta: float) -> void:
	if _bomb_left <= 0.0:
		return
	# time_scale 会缩放 delta——换算回真实时间
	var rdt: float = delta / maxf(Engine.time_scale, 0.05)
	_bomb_left -= rdt
	# 物理痉挛
	for body in get_tree().get_nodes_in_group("dynamic_props"):
		if body is RigidBody3D:
			var rb := body as RigidBody3D
			if rb.global_position.distance_to(player.global_position) < BOMB_RADIUS:
				rb.apply_central_impulse(
					Vector3(randf_range(-30, 30), randf_range(10, 50), randf_range(-30, 30)) * delta)
	if _bomb_left <= 0.0:
		if _time_scale_held:
			Engine.time_scale = 1.0
			_time_scale_held = false
		if hud != null:
			hud.show_message("时间恢复正常流速。大概吧。", 2.0)


## 狼牙：捏碎 1 颗 → 免死一次（被动，被秒杀时发动 + 反震）
func _use_wolf_tooth() -> void:
	player.wolf_save = true
	if hud != null:
		hud.show_message("你捏碎了狼牙。它隐入你的毛里——下次被秒杀时替你挡一次。", 3.5)
	if sfx != null:
		sfx.play("click")
	_broadcast("捏碎了一颗狼牙——它换掉了一次免死")


## 狼皮：3 分钟内狼不主动咬你，只绕圈
func _use_wolf_skin() -> void:
	var n := 0
	for w in get_tree().get_nodes_in_group("wolves"):
		if w is Wolf:
			(w as Wolf).pacified_left = WOLF_SKIN_TIME
			n += 1
	if hud != null:
		if n > 0:
			hud.show_message("你披上狼皮。%d 只狼开始围着你转圈——像心怀鬼胎的粉丝。" % n, 3.5)
		else:
			hud.show_message("你披上狼皮。可惜附近没有狼——这戏白搭了。", 3.5)
	if sfx != null:
		sfx.play("event")
	_broadcast("披上了一张狼皮。狼群（如果有的话）纷纷表示很熟")


## 狼骨粉：狂暴角 60 秒
func _use_wolf_bone() -> void:
	player.activate_rage(60.0)
	if hud != null:
		hud.show_message("骨粉撒下，角变得又黑又大——狂暴角 60 秒！", 3.0)
	if sfx != null:
		sfx.play("horn")
	_broadcast("撒了狼骨粉——一句话：现在它很难惹")


func _use_whistle() -> void:
	if _companion != null:
		_companion.queue_free()
	var c := Companion.new()
	c.cname = Companion.NAME_POOL[_rng.randi() % Companion.NAME_POOL.size()]
	c.follow_target = player
	add_child(c)
	var p := player.global_position + Vector3(2.0, 0.5, 2.0)
	p.y = terrain.height_at(p.x, p.z) + 0.5
	c.global_position = p
	_companion = c
	if hud != null:
		hud.show_message("你吹响了骨哨。%s 加入了队伍（它可能会卡墙，正好帮你看 Bug）。" % c.cname, 3.5)
	if sfx != null:
		sfx.play("ding")
	_broadcast("召唤了伙伴「%s」——请注意它的走位" % c.cname)


# ————————————————— 杂项 —————————————————

## 联机播报（效果本地生效，快乐全房共享）
func _broadcast(text: String) -> void:
	if net != null and net.connected_ok:
		net.send_game_event({"type": "item", "name": net.my_name, "text": text})


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if _ui_open():
		return
	if event.is_action_pressed("item_1"):
		use_slot(0)
	elif event.is_action_pressed("item_2"):
		use_slot(1)
	elif event.is_action_pressed("item_3"):
		use_slot(2)


func _ui_open() -> bool:
	if chat != null and chat.chat_open:
		return true
	if shop_menu_open():
		return true
	var vp := get_viewport()
	return vp != null and vp.gui_get_focus_owner() != null
