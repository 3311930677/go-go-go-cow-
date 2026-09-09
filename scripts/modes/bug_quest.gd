class_name BugQuest
extends Node
## Bug 复刻挑战：系统出题，玩家复刻指定 Bug。
## "BUG 就是特性"的究极形态——把 Bug 做成关卡。

var game: Game
var player: PlayerCow
var terrain: Grassland
var hud: GameHUD
var sfx: SfxBank

var idx := 0
var done := false
var _base_fly := 0
var _base_gold := 0
var challenges: Array = []


func _ready() -> void:
	challenges = [
		{"title": "起飞！", "desc": "原地连跳三次，见证传说里的起飞", "check": _check_first_fly},
		{"title": "更高！", "desc": "飞到 25 米高空（出生点海拔约 0 米）", "check": _check_height},
		{"title": "撞上天！", "desc": "把一块石头或树撞上天（离地 5 米以上）", "check": _check_prop_up},
		{"title": "密室！", "desc": "那面看起来很结实的墙后面有点东西——想办法进去", "check": _check_secret},
		{"title": "金色的草！", "desc": "吃 3 丛金草（墙后面有 5 丛，每丛 +50）", "check": _check_gold},
		{"title": "停不下来！", "desc": "再触发 2 次起飞（加上之前那次，共 3 次）", "check": _check_more_fly},
	]
	_capture_base()
	_update_task()


func _physics_process(_delta: float) -> void:
	if done:
		return
	var c: Dictionary = challenges[idx]
	if (c["check"] as Callable).call():
		if sfx != null:
			sfx.play("ding")
		hud.show_message("挑战完成：%s\n（并没有奖励）" % c["title"], 3.0)
		idx += 1
		if idx >= challenges.size():
			done = true
			_update_task()
			hud.show_message("全部完成！你是真正的抽象大师。", 5.0)
		else:
			_update_task()


func _unhandled_input(event: InputEvent) -> void:
	if done and event.is_action_pressed("restart"):
		idx = 0
		done = false
		_capture_base()
		_update_task()


func _capture_base() -> void:
	_base_fly = player.fly_count
	_base_gold = terrain.golden_eaten


# ———— 各挑战的判定 ————

func _check_first_fly() -> bool:
	return player.fly_count > _base_fly


func _check_height() -> bool:
	return player.global_position.y >= 25.0


func _check_prop_up() -> bool:
	for node in get_tree().get_nodes_in_group("dynamic_props"):
		if is_instance_valid(node) and (node as Node3D).global_position.y > 5.0:
			return true
	return false


func _check_secret() -> bool:
	return Vector2(player.global_position.x, player.global_position.z).distance_to(Grassland.SECRET_CENTER) < Grassland.SECRET_HALF


func _check_gold() -> bool:
	return terrain.golden_eaten - _base_gold >= 3


func _check_more_fly() -> bool:
	return player.fly_count - _base_fly >= 3


func _update_task() -> void:
	if done:
		hud.set_task("【特性复刻】全部完成！\n你是真正的抽象大师。按 R 再来一遍。")
	else:
		var c: Dictionary = challenges[idx]
		hud.set_task("【特性复刻】挑战 %d/%d：%s\n%s" % [idx + 1, challenges.size(), c["title"], c["desc"]])
