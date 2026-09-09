class_name Romance
extends Node
## 恋爱剧情：自由模式草原上会来一头「心上牛」。
## 流程：打招呼（E 对话）→ 一起吃草 ×3 → 散步 45 秒 → 表白（E）→ 情侣（永远跟随）。
## 事故处理：玩家撞它 → 好感清零重新开始；它被狼咬死/被炸死 → 45 秒后换下一头来。
## 荒诞守则：心上牛只存在于本地（物理永不同步），联机时别人只看到播报。

const NAMES := ["哞莉", "奶糖", "雪花", "阿花", "牛淑芬", "布丁", "小铃铛", "毛毛"]
const TALK_RADIUS := 3.5        # E 交互距离
const EAT_TOGETHER_NEED := 3    # 一起吃草次数
const EAT_TOGETHER_RADIUS := 10.0
const WALK_DURATION := 45.0     # 散步约会时长
const RESPAWN_DELAY := 45.0     # 心上牛没了 → 下一头到场时间
const SPAWN_MIN_R := 20.0       # 出生点离玩家的距离
const SPAWN_MAX_R := 35.0

## 阶段：0 未搭话 / 1 认识了 / 2 一起吃草中 / 3 散步中 / 4 可表白 / 5 情侣
var stage := 0
var eat_together := 0
var crush: CrushCow = null

var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank
var net: NetManager

var _walk_left := 0.0
var _respawn_in := 0.0
var _hint_cd := 0.0
var _dialogue: CanvasLayer = null
var _dlg_name: Label = null
var _dlg_text: Label = null
var _dlg_lines: Array[String] = []
var _dlg_on_done: Callable = Callable()


func _ready() -> void:
	player.grass_eaten.connect(_on_player_ate)
	_spawn_crush()
	_build_dialogue()
	if hud != null:
		hud.show_message("草原某处来了一头单身的牛……\n（找到它，按 E 打招呼）", 5.0)


func _process(delta: float) -> void:
	if _hint_cd > 0.0:
		_hint_cd -= delta
	if crush == null:
		if stage < 5:
			_respawn_in -= delta
			if _respawn_in <= 0.0:
				_spawn_crush()
		return

	var near := player.global_position.distance_to(crush.global_position) <= TALK_RADIUS
	# 靠近心上牛时禁用吃草（E 留给对话）
	player.talk_target_active = near

	if _dlg_lines.size() > 0:
		# 对话中：按 E 下一句；走远了直接散场
		if not near:
			_close_dialogue()
		elif Input.is_action_just_pressed("eat"):
			_advance_dialogue()
		return

	if near and Input.is_action_just_pressed("eat"):
		_on_talk()
	elif near and _hint_cd <= 0.0:
		_hint_cd = 4.0
		match stage:
			0: hud.show_message("[E] 打招呼", 1.5)
			1: hud.show_message("[E] 邀请它一起吃草", 1.5)
			2: hud.show_message("在它旁边吃草（%d/%d）——草原式约会" % [eat_together, EAT_TOGETHER_NEED], 2.0)
			3: hud.show_message("散步中……带它逛逛（剩 %.0f 秒）" % maxf(_walk_left, 0.0), 2.0)
			4: hud.show_message("[E] 表白", 1.5)
			5: hud.show_message("它已经是你牛了。看，连宝石都是粉的。", 2.0)

	# 散步计时
	if stage == 3:
		_walk_left -= delta
		if _walk_left <= 0.0:
			_finish_walk()


# ————————————————— 交互 —————————————————

## E 交互入口（按阶段分流）
func _on_talk() -> void:
	if sfx != null:
		sfx.play("click")
	match stage:
		0:
			_say(["你：哞？", "%s：哞。（它歪了歪头）" % crush.crush_name, "你：哞——", "%s：哞哞。（气氛不错）" % crush.crush_name],
				func(): _set_stage(1))
		1:
			_say(["你：一起吃草吗？", "%s：哞！（它眼睛亮了）" % crush.crush_name, "（在它 10 米内吃草就行——草原式约会）" % []],
				func(): _set_stage(2))
		4:
			_say([
				"你：哞……哞哞，哞哞哞。",
				"%s：（它愣住了）" % crush.crush_name,
				"你：（翻译：草原很大，牛生很短，我想和你一起卡在每一堵墙里。）",
				"%s：哞——！（粉宝石闪了一下）" % crush.crush_name,
				"（你们在一起了。物理引擎为证。）",
			], _confess_success)
		5:
			_say(["%s：哞。（它用头蹭了蹭你）" % crush.crush_name, "（恋爱中的牛不需要翻译）"], Callable())


## 表白成功 → 情侣
func _confess_success() -> void:
	_set_stage(5)
	crush.follow_target = player
	_burst_hearts()
	_broadcast_event("表白成功，脱单了")
	if hud != null:
		hud.show_message("你和 %s 在一起了！\n它现在会一直跟着你（包括飞天的时候）。" % crush.crush_name, 5.0)


## 一起吃草 +1（game 的 grass_eaten 信号路由过来）
func _on_player_ate(_gained: int) -> void:
	if stage != 2 or crush == null or not is_instance_valid(crush):
		return
	if player.global_position.distance_to(crush.global_position) <= EAT_TOGETHER_RADIUS:
		eat_together += 1
		if eat_together >= EAT_TOGETHER_NEED:
			_set_stage(3)
			_walk_left = WALK_DURATION
			crush.follow_target = player
			if hud != null:
				hud.show_message("%s 答应和你散步了！带它逛逛草原。（%d 秒）" % [crush.crush_name, int(WALK_DURATION)], 4.0)
			_broadcast_event("开始和约会对象散步")
		else:
			if hud != null:
				hud.show_message("一起吃草 +1（%d/%d）。它吃得很香。" % [eat_together, EAT_TOGETHER_NEED], 2.0)


## 散步完成 → 可表白
func _finish_walk() -> void:
	_set_stage(4)
	crush.follow_target = null  # 停下脚步，等你开口
	if hud != null:
		hud.show_message("散步结束了。它看着你——时机到了。\n（按 E 表白）", 4.0)


## 玩家撞了心上牛：好感清零，从头再来
func _on_crush_hurt(_by: Node3D) -> void:
	if crush == null:
		return
	if stage >= 5:
		# 情侣之间撞一下属于打情骂俏
		if hud != null:
			hud.show_message("你撞了你的牛。它说这叫情趣。", 2.5)
		return
	var was_stage := stage
	_set_stage(0)
	eat_together = 0
	crush.follow_target = null
	if hud != null and was_stage > 0:
		hud.show_message("你撞了你的约会对象。好感清零。\n（草原恋爱第一条：别用角谈恋爱）", 4.0)


## 心上牛没了（狼/号角/炸弹……）：安排下一头
func _on_crush_died(by: Node3D) -> void:
	var who := "狼" if by is Wolf else "你" if by == player else "某种力量"
	if hud != null:
		hud.show_message("%s 被%s送走了。\n草原上很快会来下一头单身的牛……" % [crush.crush_name if crush else "它", who], 4.5)
	crush = null
	_respawn_in = RESPAWN_DELAY
	var lost := stage
	_set_stage_raw(0)
	eat_together = 0
	if lost >= 5:
		_broadcast_event("恋爱结束（对象没了）")


func _set_stage(s: int) -> void:
	_set_stage_raw(s)
	if s == 1:
		_broadcast_event("和 %s 搭上了话" % _crush_name())


func _set_stage_raw(s: int) -> void:
	stage = s


# ————————————————— 心上牛管理 —————————————————

func _spawn_crush() -> void:
	var ang := randf() * TAU
	var r := randf_range(SPAWN_MIN_R, SPAWN_MAX_R)
	var px: float = player.global_position.x + cos(ang) * r
	var pz: float = player.global_position.z + sin(ang) * r
	var cow := CrushCow.new()
	cow.crush_name = NAMES[randi() % NAMES.size()]
	get_parent().add_child(cow)
	cow.global_position = Vector3(px, terrain.height_at(px, pz) + 1.2, pz)
	cow.home = cow.global_position
	cow.crush_hurt.connect(_on_crush_hurt)
	cow.crush_died.connect(_on_crush_died)
	crush = cow
	player.talk_target_active = false
	if hud != null:
		hud.show_message("草原某处又来了一头单身的牛……（%s）" % cow.crush_name, 4.0)


func _crush_name() -> String:
	return crush.crush_name if crush != null and is_instance_valid(crush) else "???"


# ————————————————— 对话框 UI —————————————————

## 底部对话框：名字 + 台词 + 「E 继续」。走远自动散场。
func _say(lines: Array, on_done: Callable) -> void:
	_dlg_lines.clear()
	for l in lines:
		_dlg_lines.append(str(l))
	_dlg_on_done = on_done
	_dialogue.visible = true
	_show_line()


func _show_line() -> void:
	_dlg_name.text = _crush_name()
	_dlg_text.text = _dlg_lines[0]
	if sfx != null:
		sfx.play("ding")


func _advance_dialogue() -> void:
	_dlg_lines.pop_front()
	if _dlg_lines.is_empty():
		_close_dialogue()
	else:
		_show_line()


func _close_dialogue() -> void:
	var done := _dlg_on_done
	_dlg_on_done = Callable()
	_dlg_lines.clear()
	_dialogue.visible = false
	if done.is_valid():
		done.call()


func _build_dialogue() -> void:
	_dialogue = CanvasLayer.new()
	_dialogue.layer = 20
	_dialogue.visible = false
	add_child(_dialogue)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue.add_child(root)

	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -130
	box.offset_bottom = -40
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.1, 0.92)
	style.border_color = Color(1.0, 0.55, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	box.add_theme_stylebox_override("panel", style)
	root.add_child(box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)

	_dlg_name = Label.new()
	_dlg_name.add_theme_font_size_override("font_size", 17)
	_dlg_name.add_theme_color_override("font_color", Color(1.0, 0.6, 0.75))
	col.add_child(_dlg_name)

	_dlg_text = Label.new()
	_dlg_text.add_theme_font_size_override("font_size", 16)
	_dlg_text.add_theme_color_override("font_color", Color(0.98, 0.95, 0.9))
	_dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_dlg_text)

	var hint := Label.new()
	hint.text = "（按 E 继续 · 走开即散场）"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.65, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hint)


## 表白成功：粉宝石位置撒一圈小爱心（旋转的小方块，廉价但真诚）
func _burst_hearts() -> void:
	if crush == null:
		return
	var origin: Vector3 = crush.global_position + Vector3(0, 2.2, 0)
	for i in 10:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.18, 0.18)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.4, 0.6)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.5)
		mi.material_override = mat
		get_parent().add_child(mi)
		mi.global_position = origin
		var tw := mi.create_tween().set_parallel(true)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1))
		tw.tween_property(mi, "global_position", origin + dir * 2.5, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(mi, "rotation:y", randf_range(-TAU, TAU), 1.2)
		tw.chain().tween_callback(mi.queue_free)


## 联机播报：同房间的人看到你的恋爱进度（只播报，不同步——物理如此，爱情也一样）
func _broadcast_event(what: String) -> void:
	if net != null and net.connected_ok:
		net.send_game_event({"type": "romance", "name": net.my_name, "crush": _crush_name(), "text": what})
