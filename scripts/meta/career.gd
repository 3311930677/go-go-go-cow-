class_name Career
extends Node
## 生涯统计 + 成就 + 存档（user://career.json）。
## 荒诞守则：所有数字都值得吹嘘，哪怕它们毫无意义。
## headless（测试/服务器）下不落盘——测试刷出来的成就不污染玩家的真实生涯。

signal unlocked(key: String, ach: Dictionary)

const SAVE_PATH := "user://career.json"

## 统计字段（全部持久化）
const STATS := [
	"grass_eaten", "golden_eaten", "fly_count", "fly_peak", "charge_hits",
	"bosses_defeated", "blackholes_smashed", "purchases", "items_used", "falls",
	"chat_sent", "screenshots", "wins", "modes_count", "survival_best",
	"play_seconds", "quests_done",
]

## 成就表：全部是「统计字段 + 阈值」——评估逻辑只有一种，想写错都难。
const ACHIEVEMENTS := [
	{"key": "first_grass", "name": "开胃小菜", "desc": "吃下第一丛草", "stat": "grass_eaten", "need": 1},
	{"key": "graze_100", "name": "草食动物", "desc": "累计吃 100 丛草", "stat": "grass_eaten", "need": 100},
	{"key": "graze_500", "name": "老饕", "desc": "累计吃 500 丛草", "stat": "grass_eaten", "need": 500},
	{"key": "first_gold", "name": "点草成金", "desc": "吃到第一株金草", "stat": "golden_eaten", "need": 1},
	{"key": "gold_50", "name": "财大气粗", "desc": "累计吃 50 株金草", "stat": "golden_eaten", "need": 50},
	{"key": "first_fly", "name": "牛会飞", "desc": "第一次飞天（这一定是特性）", "stat": "fly_count", "need": 1},
	{"key": "sky_50m", "name": "平流层", "desc": "单次飞天摸到 50 米高空", "stat": "fly_peak", "need": 50},
	{"key": "charge_50", "name": "撞王", "desc": "累计撞飞 50 个东西", "stat": "charge_hits", "need": 50},
	{"key": "boss_1", "name": "以卵击石（卵赢了）", "desc": "击败一块巨石 BOSS", "stat": "bosses_defeated", "need": 1},
	{"key": "hole_1", "name": "世界的漏洞", "desc": "撞碎一个混沌黑洞", "stat": "blackholes_smashed", "need": 1},
	{"key": "shop_1", "name": "购物狂", "desc": "在牛哥商店成交第一笔", "stat": "purchases", "need": 1},
	{"key": "items_30", "name": "药罐子", "desc": "累计使用 30 个道具", "stat": "items_used", "need": 30},
	{"key": "fall_10", "name": "坠入爱河", "desc": "掉出世界 10 次（这是特性）", "stat": "falls", "need": 10},
	{"key": "chat_50", "name": "社交牛人", "desc": "发送 50 条聊天", "stat": "chat_sent", "need": 50},
	{"key": "modes_6", "name": "多面手", "desc": "玩过全部 6 种模式", "stat": "modes_count", "need": 6},
	{"key": "win_1", "name": "冠军相", "desc": "任意竞技模式夺冠一次", "stat": "wins", "need": 1},
	{"key": "shot_10", "name": "摄影师", "desc": "截 10 张图（发出去让更多人后悔）", "stat": "screenshots", "need": 10},
	{"key": "survive_120", "name": "活着就好", "desc": "天降正义单局存活 2 分钟", "stat": "survival_best", "need": 120},
	{"key": "dreamer", "name": "梦醒时分", "desc": "自由模式完成全部任务", "stat": "quests_done", "need": 1},
]

var stats := {}
var unlocked_map := {}  # key → true（与信号 unlocked 同名会撞车，改叫 map）
var modes_played := {}
var save_path := SAVE_PATH
## headless 不写盘（测试/服务器不污染真实生涯）；单测里要验证存档就手动开
var persist := DisplayServer.get_name() != "headless"

var _play_save_acc := 0.0


func _ready() -> void:
	for s in STATS:
		if not stats.has(s):
			stats[s] = 0
	load_from(save_path)


# ————————————————— 统计入口（游戏各处调用） —————————————————

## 累加一项统计（触发评估 + 落盘）
func add(stat: String, value := 1.0) -> void:
	if not stats.has(stat):
		push_warning("Career.add：未知统计字段 %s" % stat)
		return
	stats[stat] = stats[stat] + value
	_evaluate(stat)
	save_to()


## 只增不减（最高纪录类：飞天峰值 / 最长存活）
func set_max(stat: String, value: float) -> void:
	if not stats.has(stat):
		push_warning("Career.set_max：未知统计字段 %s" % stat)
		return
	if value > stats[stat]:
		stats[stat] = value
		_evaluate(stat)
		save_to()


## 玩过一种模式（去重计数）
func note_mode(mode_key: String) -> void:
	if mode_key == "":
		return
	modes_played[mode_key] = true
	stats["modes_count"] = modes_played.size()
	_evaluate("modes_count")
	save_to()


## 竞技模式夺冠（相扑 KO 满 / 竞速完赛 / 大逃杀吃鸡）
func note_win() -> void:
	add("wins")


## 一次飞天落地结算（peak = 本次摸到的最高点）
func note_fly(peak: float) -> void:
	add("fly_count")
	set_max("fly_peak", peak)


## 游戏时长（每帧调用；攒 20 秒才写一次盘——不至于每帧 I/O）
func tick(delta: float) -> void:
	stats["play_seconds"] = stats["play_seconds"] + delta
	_play_save_acc += delta
	if _play_save_acc >= 20.0:
		_play_save_acc = 0.0
		save_to()


## 手动解锁（预留给特殊成就）
func unlock(key: String) -> void:
	for ach in ACHIEVEMENTS:
		if ach["key"] == key:
			_do_unlock(ach)
			return
	push_warning("Career.unlock：未知成就 %s" % key)


func is_unlocked(key: String) -> bool:
	return unlocked_map.has(key)


func unlocked_count() -> int:
	return unlocked_map.size()


# ————————————————— 查询（面板用） —————————————————

## 成就列表（带解锁状态与进度），顺序与定义一致
func achievement_list() -> Array:
	var out: Array = []
	for ach in ACHIEVEMENTS:
		var e: Dictionary = ach.duplicate()
		e["unlocked"] = unlocked_map.has(ach["key"])
		var cur: float = stats.get(ach["stat"], 0)
		e["progress"] = "%d/%d" % [int(minf(cur, ach["need"])), ach["need"]]
		out.append(e)
	return out


## 面板顶部的统计行
func summary_lines() -> Array:
	return [
		"吃草 %d 丛" % int(stats["grass_eaten"]),
		"金草 %d 株" % int(stats["golden_eaten"]),
		"飞天 %d 次" % int(stats["fly_count"]),
		"最高飞天 %.0f 米" % float(stats["fly_peak"]),
		"撞飞 %d 个" % int(stats["charge_hits"]),
		"巨石 BOSS %d 块" % int(stats["bosses_defeated"]),
		"黑洞 %d 个" % int(stats["blackholes_smashed"]),
		"商店成交 %d 笔" % int(stats["purchases"]),
		"道具用掉 %d 个" % int(stats["items_used"]),
		"掉出世界 %d 次" % int(stats["falls"]),
		"聊天 %d 条" % int(stats["chat_sent"]),
		"截图 %d 张" % int(stats["screenshots"]),
		"夺冠 %d 次" % int(stats["wins"]),
		"最长存活 %.0f 秒" % float(stats["survival_best"]),
		"做梦 %.1f 小时" % (float(stats["play_seconds"]) / 3600.0),
	]


# ————————————————— 内部 —————————————————

## 某项统计变动后，检查依赖它的所有成就
func _evaluate(stat: String) -> void:
	for ach in ACHIEVEMENTS:
		if ach["stat"] == stat and stats[stat] >= ach["need"]:
			_do_unlock(ach)


func _do_unlock(ach: Dictionary) -> void:
	if unlocked_map.has(ach["key"]):
		return
	unlocked_map[ach["key"]] = true
	save_to()
	unlocked.emit(ach["key"], ach)


# ————————————————— 存档 —————————————————

func save_to() -> void:
	if not persist:
		return
	var data := {
		"stats": stats,
		"unlocked": unlocked_map,
		"modes_played": modes_played,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


## 读档（无档/坏档 → 静默从零开始）
func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return false
	var data: Dictionary = parsed
	var st: Dictionary = data.get("stats", {})
	for s in STATS:
		if st.has(s):
			stats[s] = st[s]
	var ul: Dictionary = data.get("unlocked", {})
	for k in ul:
		unlocked_map[k] = true
	var mp: Dictionary = data.get("modes_played", {})
	for k in mp:
		if str(k) != "":
			modes_played[str(k)] = true
	stats["modes_count"] = modes_played.size()
	return true


## 全部清零（给测试用；真实玩家请珍惜自己的梦）
func reset_all() -> void:
	stats = {}
	for s in STATS:
		stats[s] = 0
	unlocked_map = {}
	modes_played = {}
	save_to()
