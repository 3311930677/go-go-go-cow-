class_name Game
extends Node3D
## 游戏主控：模式状态机（梦境 → 闪回 → 现实）。
## 梦境：草原冒险（主场景核心内容）。
## 闪回：任务 2/2 完成后触发——"原来这一切只是小牛吃奶时做的一个梦"。
## 现实：牛棚里的孱弱小牛（反差彩蛋），按 R 重回梦境。

enum Mode { DREAM, FLASHBACK, REALITY }

const SPAWN_POSITION := Vector3(0.0, 6.0, 0.0)
const RESPAWN_Y := -20.0      # 掉出世界的高度阈值（梦境）
const DREAM_FADE_DELAY := 3.0 # 2/2 完成后到闪回的延迟（"梦要醒了……"）
## P1-B 死亡嘲讽文案（死亡演出轮换用）
const DEATH_TAUNTS: Array[String] = [
	"你在梦里死了。但现实里，你还在喝奶。",
	"这头牛死得毫无尊严。梦居然还在继续。",
	"死亡不是终点——梦醒才是。可惜没醒。",
	"你的角刚长出来就殉职了。草，白吃了。",
	"哞——！…… 没事，梦里可以死很多次。",
]

var mode: int = Mode.DREAM
var player: PlayerCow
var camera: CowCamera
var hud: GameHUD
var terrain: Grassland
var chaos: ChaosManager
var quests: QuestManager
var world_map: WorldMap
var flashback: Flashback
var barn: Barn
var sfx: SfxBank
var net: NetManager
var chat: ChatBox
var settings: SettingsMenu
var intro: ModeIntro
var items: ItemManager
var romance: Romance
# —— 生涯与成就（P4） ——
var career: Career
var achv_toast: AchievementToast
var career_panel: CareerPanel
# —— 新模式管理器（按 ModeConfig.mode 启用） ——
var sumo: SumoArena
var meteors: MeteorManager
var bugquest: BugQuest
var race: SkyRace
var battle: BattleRoyale

## 远程玩家渲染（联机）：peer_id → NetPlayer
var _net_players: Dictionary = {}

## 本局飞天摸到的最高点（落地结算进生涯）
var _fly_peak := 0.0


func _ready() -> void:
	# —— 音效库（程序化合成） ——
	sfx = SfxBank.new()
	sfx.name = "SfxBank"
	add_child(sfx)
	# —— 草原世界（梦境） ——
	terrain = Grassland.new()
	terrain.name = "Grassland"
	add_child(terrain)

	# —— 玩家小牛（梦境主角） ——
	player = PlayerCow.new()
	player.name = "PlayerCow"
	add_child(player)
	player.global_position = SPAWN_POSITION
	player.terrain = terrain

	# —— 第三人称相机 ——
	camera = CowCamera.new()
	camera.name = "CowCamera"
	camera.follow_target = player
	add_child(camera)
	player.camera = camera

	# —— HUD ——
	hud = GameHUD.new()
	hud.name = "GameHUD"
	add_child(hud)
	player.hud = hud
	player.sfx = sfx
	terrain.hud = hud  # 穿墙/雕像彩蛋文案通道

	# —— 生涯与成就（P4）：统计 + 解锁弹窗 + 查看面板 ——
	career = Career.new()
	career.name = "Career"
	add_child(career)  # _ready 里自动从 user://career.json 读档
	career.note_mode(ModeConfig.mode)
	career.unlocked.connect(_on_achievement_unlocked)
	achv_toast = AchievementToast.new()
	achv_toast.name = "AchievementToast"
	achv_toast.sfx = sfx
	add_child(achv_toast)
	career_panel = CareerPanel.new()
	career_panel.name = "CareerPanel"
	career_panel.career = career
	add_child(career_panel)
	career_panel.closed.connect(_on_settings_closed)
	# 玩家行为 → 生涯统计
	player.grass_eaten.connect(func(gained: int):
		career.add("grass_eaten")
		if gained >= 50:  # 金草一口 +50
			career.add("golden_eaten"))
	player.charged_prop.connect(func(_b: Node3D): career.add("charge_hits"))
	player.player_died.connect(_on_player_died)  # P1-B 死亡 → 复活调度

	# —— 物理崩坏事件调度器（自由模式 & Bug 复刻） ——
	if ModeConfig.mode == "free" or ModeConfig.mode == "quest":
		chaos = ChaosManager.new()
		chaos.name = "ChaosManager"
		chaos.player = player
		chaos.terrain = terrain
		chaos.hud = hud
		chaos.sfx = sfx
		add_child(chaos)
		chaos.blackhole_smashed.connect(func(_at: Vector3): career.add("blackholes_smashed"))

	# —— 任务系统（仅自由模式——其他模式各有各的荒诞） ——
	if ModeConfig.mode == "free":
		quests = QuestManager.new()
		quests.name = "QuestManager"
		quests.player = player
		quests.terrain = terrain
		quests.hud = hud
		quests.sfx = sfx
		add_child(quests)
		quests.quests_all_done.connect(_on_quests_all_done)

	# —— 恋爱剧情（仅自由模式）：草原上来一头心上牛，打招呼→一起吃草→散步→表白 ——
	if ModeConfig.mode == "free":
		romance = Romance.new()
		romance.name = "Romance"
		romance.player = player
		romance.terrain = terrain
		romance.hud = hud
		romance.sfx = sfx
		add_child(romance)

	# —— 道具系统（全模式）：自由/复刻 = 草堆+商店+获取钩子；
	# 相扑/躲陨石/竞速/大逃杀 = 竞技模式（开局送 1 个 + 空投补给）——
	items = ItemManager.new()
	items.name = "ItemManager"
	items.player = player
	items.terrain = terrain
	items.hud = hud
	items.sfx = sfx
	items.camera = camera
	items.chat = chat
	items.career = career  # 生涯：道具使用/购物统计
	items.competitive = not (ModeConfig.mode == "free" or ModeConfig.mode == "quest")
	add_child(items)
	if not items.competitive:
		items.shop.menu_closed.connect(_on_settings_closed)  # 商店关门同样收回鼠标

	# 混沌调度器需要任务进度（事件变频/后期事件）和道具（黑洞奖励）——现在才齐
	if ModeConfig.mode == "free" and chaos != null:
		chaos.quests = quests
		chaos.items = items
	# 毛蛋飞天 → 巨石 BOSS：战利品与联机播报
	if ModeConfig.mode == "free":
		quests.boss_started.connect(_on_boss_started)

	# —— 全屏地图 ——
	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	add_child(world_map)
	world_map.player = player
	world_map.terrain = terrain
	world_map.quests = quests
	world_map.chaos = chaos  # 黑洞标记（free/quest 有调度器；其他模式 null 不画）
	if not items.competitive:
		world_map.shop_pos = ItemManager.SHOP_POS  # 地图上标出牛哥商店（不然谁找得到）

	# —— 闪回过场（待命） ——
	flashback = Flashback.new()
	flashback.name = "Flashback"
	add_child(flashback)
	flashback.done.connect(_on_flashback_done)

	# —— 设置菜单（ESC 呼出） + 应用已保存设置 ——
	var saved := SettingsMenu.load_settings()
	SettingsMenu.apply_volume(saved.volume)
	SettingsMenu.apply_quality(saved.quality)
	settings = SettingsMenu.new()
	settings.name = "SettingsMenu"
	add_child(settings)
	settings.closed.connect(_on_settings_closed)
	settings.career_requested.connect(_open_career_panel)  # 设置里也能看生涯

	# —— 联机聊天框（联机时才有意义） ——
	chat = ChatBox.new()
	chat.name = "ChatBox"
	add_child(chat)

	# —— 模式简介卡（进模式先看规则，按任意键开始） ——
	intro = ModeIntro.new()
	intro.name = "ModeIntro"
	add_child(intro)
	intro.show_intro(ModeConfig.mode)

	# —— 模式管理器（按 ModeConfig.mode 启用） + 各模式操作提示 ——
	match ModeConfig.mode:
		"sumo":
			sumo = SumoArena.new()
			sumo.name = "SumoArena"
			sumo.game = self
			sumo.player = player
			sumo.hud = hud
			sumo.sfx = sfx
			add_child(sumo)
			player.global_position = SumoArena.SPAWN
			camera.call_deferred("_snap_to_target")
		"survival":
			meteors = MeteorManager.new()
			meteors.name = "MeteorManager"
			meteors.game = self
			meteors.player = player
			meteors.hud = hud
			meteors.sfx = sfx
			add_child(meteors)
		"quest":
			bugquest = BugQuest.new()
			bugquest.name = "BugQuest"
			bugquest.game = self
			bugquest.player = player
			bugquest.terrain = terrain
			bugquest.hud = hud
			bugquest.sfx = sfx
			add_child(bugquest)
		"race":
			race = SkyRace.new()
			race.name = "SkyRace"
			race.game = self
			race.player = player
			race.hud = hud
			race.sfx = sfx
			add_child(race)
		"battle":
			battle = BattleRoyale.new()
			battle.name = "BattleRoyale"
			battle.game = self
			battle.player = player
			battle.terrain = terrain
			battle.hud = hud
			battle.sfx = sfx
			add_child(battle)
			world_map.battle = battle
	var help_texts := {
		"free": "WASD 移动    空格 跳跃（连跳3次飞天）    左键 冲撞（威力不讲道理）    按住E 吃草    1/2/3 道具（悬停道具栏看说明）    M 地图    T 聊天    ESC 设置",
		"sumo": "左键 冲撞：把别的牛撞下台    空格 跳跃    1/2/3 道具（空投补给）    T 聊天    ESC 设置",
		"survival": "WASD 逃命    空格 跳跃    1/2/3 道具（空投补给）    T 聊天    ESC 设置（被砸中会飞出去）",
		"quest": "按任务栏说明重现传说    1/2/3 道具（悬停道具栏看说明）    M 地图    T 聊天    ESC 设置",
		"race": "连跳三次起飞    按顺序穿过金环    1/2/3 道具（空投补给）    R 重开    T 聊天    ESC 设置",
		"battle": "待在绿圈里！圈外会掉帧    WASD 移动    空格 跳跃    1/2/3 道具（空投补给）    M 地图    R 重开    T 聊天    ESC 设置",
	}
	hud.help_label.text = help_texts.get(ModeConfig.mode, help_texts["free"])

	# headless 测试环境下不捕获鼠标
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# —— 联机模式（从标题画面"联机草原"进入时启用） ——
	# 聊天信号无论联机离线都要接：离线时本地显示并注明只有自己可见
	chat.chat_submitted.connect(_on_chat_submitted)
	if NetConfig.enabled:
		net = NetManager.new()
		net.name = "NetManager"
		add_child(net)
		net.setup_client(player)
		net.event_received.connect(func(msg): hud.show_message(msg, 4.0))
		net.chat_received.connect(_on_chat_received)
		net.game_event_received.connect(_on_game_event)
		net.mode_received.connect(_on_net_mode_received)
		hud.show_message("正在连接 %s:%d …" % [NetConfig.server_ip, NetConfig.server_port], 3.0)
		# 连上后提示所在房间——同房间号的人才能互相看到
		net.connected.connect(func():
			hud.show_message("已连接！你在房间「%s」——把房间号告诉朋友，一起进同一家草原" % net.my_room, 4.0))
		# 连不上要明说——不然玩家以为自己在联机，按 T 却只当离线处理
		net.connection_failed_sig.connect(func():
			hud.show_message("连接失败：服务器不在线，或地址/端口不对。\n（简幻欢实例需要在运行中）", 5.0))
		# 道具播报走游戏事件通道（效果本地生效，快乐全房共享）
		if items != null:
			items.net = net
		if chaos != null:
			chaos.net = net  # 混沌事件/黑洞播报
		if romance != null:
			romance.net = net  # 恋爱进度播报（不同步，只播报——物理如此，爱情也一样）


func _process(_delta: float) -> void:
	# 生涯：游戏时长累计（攒 20 秒写一次盘）
	career.tick(_delta)
	# 生涯：飞天峰值（在飞就记最高点，落地结算一次）
	if player._flying:
		_fly_peak = maxf(_fly_peak, player.global_position.y)
	elif _fly_peak > 0.0:
		career.note_fly(_fly_peak)
		_fly_peak = 0.0
	# 掉出世界 → 重生（这是特性，不是 Bug）——相扑/大逃杀模式除外（掉下去本身就是玩法）
	if mode == Mode.DREAM and ModeConfig.mode != "sumo" and ModeConfig.mode != "battle" \
			and player.global_position.y < RESPAWN_Y:
		career.add("falls")
		player.global_position = SPAWN_POSITION
		player.velocity = Vector3.ZERO
		camera.call_deferred("_snap_to_target")
		hud.show_message("你掉出了世界。这当然是特性。", 2.5)
	# 联机：同步远程玩家渲染
	if net != null and net.connected_ok:
		_sync_net_players()


## 快照 → 远程牛的增删与状态更新（自己的 ID 过滤掉）
func _sync_net_players() -> void:
	var my_id := get_tree().get_multiplayer().get_unique_id()
	# 增/更新
	for pid in net.players:
		if pid == my_id:
			continue
		var st: Dictionary = net.players[pid]
		if not _net_players.has(pid):
			var np := NetPlayer.new()
			np.peer_id = pid
			np.player_name = st.get("name", "神秘小牛")
			add_child(np)
			np.global_position = st["pos"]
			_net_players[pid] = np
		var np: NetPlayer = _net_players[pid]
		np.update_state(st["pos"], st["ry"], st["act"])
		# 名字可能从占位符"…"更新为真实名字
		var pname: String = st.get("name", "神秘小牛")
		if pname != "…" and np.player_name != pname:
			np.player_name = pname
			np.update_name()
	# 删
	for pid in _net_players.keys():
		if not net.players.has(pid):
			_net_players[pid].queue_free()
			_net_players.erase(pid)


func _unhandled_input(event: InputEvent) -> void:
	# 生涯面板开着——输入先归它（ESC 关面板，别把设置/聊天顶出来）
	if career_panel != null and career_panel.visible:
		return
	# F12 截图：一键生成传播素材（自带水印）
	if event.is_action_pressed("screenshot") and mode != Mode.FLASHBACK:
		_take_screenshot()
	# T：打开聊天（聊天框自身处理 Esc/Enter）。离线也能开——发送时会注明只有自己可见
	elif event.is_action_pressed("chat") and mode != Mode.FLASHBACK and not chat.chat_open \
			and not (items != null and items.shop_menu_open()):
		if not settings.visible:
			chat.open()
			if DisplayServer.get_name() != "headless":
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# ESC：呼出设置菜单（闪回期间不可打断；商店营业时先关商店）
	elif event.is_action_pressed("toggle_mouse") and mode != Mode.FLASHBACK \
			and not (items != null and items.shop_menu_open()):
		if not settings.visible:
			settings.open_menu(true)
			if DisplayServer.get_name() != "headless":
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 现实模式结局后：R 重回梦境
	elif mode == Mode.REALITY and barn != null and barn.weak_cow != null \
			and barn.weak_cow.ending and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


## 设置关闭 → 回到游戏（重新捕获鼠标）
func _on_settings_closed() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 设置菜单里点「生涯与成就」→ 关设置、开生涯面板
func _open_career_panel() -> void:
	settings.close_menu()
	career_panel.open_panel()


## 成就解锁：本地弹奖状 + 聊天播报 + 联机让全房一起看
func _on_achievement_unlocked(_key: String, ach: Dictionary) -> void:
	var title := str(ach.get("name", "???"))
	var desc := str(ach.get("desc", ""))
	achv_toast.notify(title, desc)
	if chat != null:
		chat.push_system("解锁成就「%s」——%s" % [title, desc])
	if net != null and net.connected_ok:
		net.send_game_event({"type": "achv", "name": net.my_name, "title": title})


## 收到远端聊天 → 显示到左下角列表
func _on_chat_received(pname: String, text: String) -> void:
	chat.push_message(pname, text)
	if sfx != null:
		sfx.play("ding")


## 本地发送聊天 → 上行给服务器（服务器广播给所有人，含自己）。
## 离线时本地显示并注明：只有你自己能看到。
func _on_chat_submitted(text: String) -> void:
	career.add("chat_sent")
	if net != null and net.connected_ok:
		net.send_chat(text)
	else:
		var pname := net.my_name if net != null else "你"
		chat.push_message(pname, text)
		chat.push_system("（离线：这条消息只有你自己能看到。联机后大家才能一起聊）")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 服务器下发房间模式：与本地不同则自动切过去（先进房的第一头牛定模式）
func _on_net_mode_received(mode_key: String) -> void:
	if not ModeConfig.is_valid(mode_key) or mode_key == ModeConfig.mode:
		return
	hud.show_message("房间模式：%s —— 帮你切好了" % ModeConfig.MODE_INFO[mode_key]["btn"], 3.0)
	ModeConfig.mode = mode_key
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## 全局游戏事件（KO 播报/死亡/完赛）→ 左下角系统播报流，所有人可见
func _on_game_event(data: Dictionary) -> void:
	match data.get("type", ""):
		"ko":
			chat.push_system("【相扑】%s 把 %s 撞出了世界" % [str(data.get("attacker", "?")), str(data.get("victim", "?"))])
		"meteor":
			chat.push_system("【天降正义】%s 被砸成了肉饼（存活 %.1f 秒）" % [str(data.get("name", "?")), float(data.get("time", 0.0))])
		"race":
			chat.push_system("【竞速】%s 完赛！用时 %.1f 秒" % [str(data.get("name", "?")), float(data.get("time", 0.0))])
		"zone_elim":
			chat.push_system("【大逃杀】%s 掉进未加载区域，闪退了（第 %d 名）" % [str(data.get("name", "?")), int(data.get("rank", 0))])
		"zone_win":
			chat.push_system("【大逃杀】%s 是最后加载的牛——胜利！" % str(data.get("name", "?")))
		"item":
			chat.push_system("【道具】%s %s" % [str(data.get("name", "?")), str(data.get("text", ""))])
		"boss":
			chat.push_system("【巨石】%s %s" % [str(data.get("name", "?")), str(data.get("text", ""))])
		"chaos":
			chat.push_system("【混沌】%s %s" % [str(data.get("name", "?")), str(data.get("text", ""))])
		"wolf":
			chat.push_system("【狼群】%s %s" % [str(data.get("name", "?")), str(data.get("text", ""))])
		"achv":
			chat.push_system("【成就】%s 解锁了「%s」——就这？" % [str(data.get("name", "?")), str(data.get("title", "?"))])
		"room_full":
			chat.push_system("房间「%s」满员了（上限 %d 头）——回主菜单换个房间号吧" % [str(data.get("room", "?")), 16])
		"romance":
			chat.push_system("【恋爱】%s 和 %s %s" % [str(data.get("name", "?")), str(data.get("crush", "?")), str(data.get("text", ""))])
		_:
			chat.push_system(str(data))


## F12 截图：保存到 user://screenshots（HUD 右下角常驻水印随画面一并入图）
func _take_screenshot() -> void:
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	var ts := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace(" ", "_")
	var path := "%s/moo_%s.png" % [dir, ts]
	img.save_png(path)
	sfx.play("click")
	career.add("screenshots")
	# 显示真实保存路径（Windows 下 user:// 在 %APPDATA%/Godot/app_userdata/大梦哞哞/）
	hud.show_message("截图已保存（发出去让更多人后悔）：\n%s" % ProjectSettings.globalize_path(path), 5.0)



## 玩家死亡（P1-B）：白闪 + 震屏 + 黑幕 + 嘲讽 → 复活
func _on_player_died() -> void:
	career.add("dream_deaths")
	if ModeConfig.mode == "free" or ModeConfig.mode == "quest":
		_dream_death_respawn()
	elif ModeConfig.mode == "battle" and battle != null and battle.has_method("player_killed"):
		battle.player_killed()  # 大逃杀：血量归零 = 出局（P2 接线）
	else:
		player.reset_for_respawn(player.global_position)  # 兜底：原地复活


func _dream_death_respawn() -> void:
	if hud != null:
		hud.flash_white()
	if camera != null:
		camera.shake(0.25, 0.6)
	if hud != null:
		hud.blackout(1.0)
	var taunt := DEATH_TAUNTS[randi() % DEATH_TAUNTS.size()]
	await get_tree().create_timer(1.4).timeout
	if not is_instance_valid(player):
		return
	# 死亡惩罚：吃饱度减半（"梦里也无力"但可控）
	player.fullness = int(player.fullness / 2)
	if hud != null:
		hud.set_fullness(player.fullness)
	var pos := SPAWN_POSITION
	if terrain != null:
		pos = terrain.nearest_grass(player.global_position)
	player.reset_for_respawn(pos)
	hud.show_message(taunt, 4.0)

## 巨石 BOSS 登场：接上战利品掉落与联机播报
func _on_boss_started(boss: Node3D) -> void:
	if boss == null:
		return
	boss.net = net
	boss.boss_defeated.connect(func(at: Vector3):
		career.add("bosses_defeated")
		if items != null:
			# 战利品：号角 + 随机道具（巨石的口袋里啥都有）
			items.drop_reward_near(at, "horn")
			items.drop_reward_near(at + Vector3(2.0, 0, 0), ""))


## 任务 2/2 完成 → 数秒后进入闪回
func _on_quests_all_done() -> void:
	career.add("quests_done")
	if items != null:
		items.grant_whistle()  # 全任务奖励：伙伴哨子（可惜梦快醒了）
	hud.show_message("梦要醒了……", DREAM_FADE_DELAY)
	await get_tree().create_timer(DREAM_FADE_DELAY).timeout
	if mode != Mode.DREAM:
		return  # 防御（例如已被重载）
	mode = Mode.FLASHBACK
	chaos.enabled = false
	quests.enabled = false
	world_map.input_enabled = false
	if world_map._open:
		world_map.toggle()
	flashback.play()


## 闪回播完 → 现实模式
func _on_flashback_done() -> void:
	mode = Mode.REALITY
	# 隐藏整个梦境（含其环境光——牛棚自带暖光接管）
	terrain.visible = false
	player.visible = false
	player.set_physics_process(false)
	# 建牛棚（y=200 悬空平台，物理隔离）
	barn = Barn.new()
	barn.name = "Barn"
	barn.position = Vector3(0.0, 200.0, 0.0)
	add_child(barn)
	barn.weak_cow.hud = hud
	barn.weak_cow.sfx = sfx
	# 相机切换到孱弱小牛，拉近一点（棚里挤）
	camera.follow_target = barn.weak_cow
	camera.dist = 4.5
	camera.pitch = 0.5
	camera._snap_to_target()
	# 地图追踪现实小牛（但地图在现实不可开）
	world_map.player = barn.weak_cow
	hud.set_task("【现实】你是一头孱弱的小牛。（这不是梦。）\n走到奶盆旁按 E 喝奶。 WASD 缓慢挪动。")
	hud.show_message("（你醒了。梦里你上天入地无所不能。这里你连站都站不稳。）", 5.0)
