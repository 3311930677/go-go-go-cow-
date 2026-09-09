class_name NetManager
extends Node
## 双模式网络节点（客户端 / 专用服务器共用同一脚本，保证 RPC 节点路径一致：
## 两端均为 /root/Main/NetManager）。
##
## 协议（基于 MultiplayerAPI RPC，走 WebSocket/TCP——简幻欢网关只转发 TCP）：
##   client → server : submit_join(room_id, mode)     连入后一次（进房间）
##   client → server : submit_state(pos, ry, act)     15Hz（仅本房间生效）
##   server → client : deliver_snap(players_dict)     15Hz（仅本房间成员）
##   server → client : deliver_event(msg)             定时可靠（本房间广播）
##   server → client : deliver_chat / deliver_game_event / deliver_mode
##
## 多房间：同一服务器按房间号分组——同房间互见，聊天/事件/模式互不串扰。
## 房间规则：进房第一头牛决定模式；房间空了自动销毁。
##
## 设计哲学：物理永不同步——每个人看到的物理崩坏都不一样，这是特性。

signal connected
signal connection_failed_sig
signal event_received(msg: String)
signal chat_received(pname: String, text: String)
signal game_event_received(data: Dictionary)
signal mode_received(mode_key: String)

## 服务器模式开关（server.tscn 中置 true；客户端由 game.gd 动态创建默认 false）
@export var server_mode := false
@export var server_port := 24565
@export var max_players := 16  # 每个房间的牛数上限

const NAME_POOL := [
	"哞王", "抽象大师", "穿模侠", "飞天小牛", "草原BUG",
	"牛顿反对者", "梦游者", "卡墙牛", "金草猎人", "物理学家",
]
const SEND_HZ := 15.0
const SNAP_HZ := 15.0

## 客户端：本房间快照（peer_id → {pos, ry, act, name, t}）。
## 服务器端不再使用（改用 rooms 按房管理）。
var players: Dictionary = {}
var my_name := ""
var connected_ok := false
var last_event_msg := ""

## 当前所在房间号（客户端连入后由服务器确认；服务器端单进程管理所有房间）
var my_room := ""

## 服务器：room_id → {"players": {pid → 状态}, "mode": String}
var rooms := {}
## 服务器：pid → room_id
var peer_room := {}

var _player: PlayerCow  # 客户端：本地玩家引用（状态采样）
var _send_acc := 0.0
var _snap_acc := 0.0
var _event_acc := 0.0
var _event_interval := 25.0  # 服务器事件间隔（测试可用命令行覆盖）
var _event_pool: Array[String] = [
	"【联机】牛群迁徙开始了！每个人看到的牛群都不一样。这是特性。",
	"【联机】重力异常！在你的屏幕里，别人可能正飘在空中。",
	"【联机】物理引擎下班了。所有人对'下班'的理解各不相同。",
	"【联机】服务端提醒你：这一切都只是梦。服务端也是。",
]
var _join_submitted := false  # 客户端：本次连接是否已发送进房请求


func _ready() -> void:
	var mp := get_tree().get_multiplayer()
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected_to_server)
	mp.connection_failed.connect(func(): connected_ok = false; connection_failed_sig.emit())

	# 牛名：自定义优先（标题画面填写），否则随机荒诞名
	var custom_name := NetConfig.player_name.strip_edges()
	if custom_name != "":
		my_name = custom_name.substr(0, 12)
	else:
		my_name = NAME_POOL[randi() % NAME_POOL.size()] + str(randi() % 90 + 10)

	if server_mode:
		# 命令行参数：--port=xxx --event-interval=xx --max-players=n
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--port="):
				server_port = int(arg.get_slice("=", 1))
			elif arg.begins_with("--event-interval="):
				_event_interval = float(arg.get_slice("=", 1))
			elif arg.begins_with("--max-players="):
				max_players = int(arg.get_slice("=", 1))
		var peer := WebSocketMultiplayerPeer.new()
		var err := peer.create_server(server_port)
		if err != OK:
			push_error("服务器启动失败（端口 %d）：%d" % [server_port, err])
			get_tree().quit(1)
			return
		mp.multiplayer_peer = peer
		print("[服务器] 已启动（WebSocket/TCP 多房间），端口 %d，等待小牛们连入……" % server_port)
	else:
		var peer := WebSocketMultiplayerPeer.new()
		var host := NetConfig.server_ip
		if host.begins_with("ws://") or host.begins_with("wss://"):
			host = host.substr(host.find("://") + 3)  # 容错：用户手滑带了协议头
		var err := peer.create_client("ws://%s:%d" % [host, NetConfig.server_port])
		if err != OK:
			push_error("客户端网络初始化失败：%d" % err)
			return
		mp.multiplayer_peer = peer


func setup_client(player: PlayerCow) -> void:
	_player = player


## 客户端连上服务器：申请进房（房间号来自标题画面；服务器裁决后回发模式）
func _on_connected_to_server() -> void:
	connected_ok = true
	my_room = _sanitize_room(NetConfig.room_id)
	connected.emit()
	if not _join_submitted:
		_join_submitted = true
		submit_join.rpc_id(1, my_room, ModeConfig.mode)


func _process(delta: float) -> void:
	if server_mode:
		# —— 服务器：逐房间聚合快照广播 + 定时事件 ——
		_snap_acc += delta
		if _snap_acc >= 1.0 / SNAP_HZ:
			_snap_acc = 0.0
			for rid in rooms.keys():
				var room: Dictionary = rooms[rid]
				_prune_stale(room)
				if room["players"].is_empty():
					rooms.erase(rid)  # 空房自动销毁
					continue
				for pid in room["players"]:
					deliver_snap.rpc_id(pid, room["players"].duplicate(true))
		_event_acc += delta
		if _event_acc >= _event_interval:
			_event_acc = 0.0
			var msg: String = _event_pool[randi() % _event_pool.size()]
			last_event_msg = msg
			deliver_event.rpc(msg)
	else:
		# —— 客户端：采样本地玩家并发送 ——
		if connected_ok and _player != null:
			_send_acc += delta
			if _send_acc >= 1.0 / SEND_HZ:
				_send_acc = 0.0
				var act := "idle"
				if _player._flying:
					act = "fly"
				elif _player._charge_timer > 0.0:
					act = "charge"
				elif _player._eat_timer > 0.0:
					act = "eat"
				elif Vector2(_player.velocity.x, _player.velocity.z).length() > 0.5:
					act = "run"
				submit_state.rpc_id(1, _player.global_position, _player.model.rotation.y, act, my_name)


# ————————————————— RPC —————————————————

## 客户端 → 服务器：申请进房（仅服务器执行）。
## 房间不存在则创建；进房第一头牛决定房间模式；房间满员则拒绝。
@rpc("any_peer", "reliable")
func submit_join(room_id: String, mode_key: String) -> void:
	if not server_mode:
		return
	var pid := _sender_pid()
	room_id = _sanitize_room(room_id)
	if not ModeConfig.is_valid(mode_key):
		mode_key = "free"
	# 房间满员：拒绝（回发事件让客户端知道）
	if rooms.has(room_id) and rooms[room_id]["players"].size() >= max_players:
		deliver_game_event.rpc_id(pid, {"type": "room_full", "room": room_id})
		print("[服务器] 小牛 %d 进房被拒（房间 %s 满员）" % [pid, room_id])
		return
	# 换房：先从旧房移除
	_leave_room(pid)
	if not rooms.has(room_id):
		rooms[room_id] = {"players": {}, "mode": mode_key}
		print("[服务器] 房间 %s 创建（模式 %s）" % [room_id, mode_key])
	var room: Dictionary = rooms[room_id]
	peer_room[pid] = room_id
	room["players"][pid] = {"pos": Vector3(0, 5, 0), "ry": 0.0, "act": "idle", "name": my_name_of(pid), "t": 0.0}
	print("[服务器] 小牛 %d 进房 %s（房内 %d 头）" % [pid, room_id, room["players"].size()])
	deliver_mode.rpc_id(pid, room["mode"])
	deliver_chat.rpc_id(pid, "房间通知", "你进了房间「%s」，房内 %d 头牛。" % [room_id, room["players"].size()])


## 客户端 → 服务器：上报自身状态（仅服务器执行，写入发送者所在房间）
@rpc("any_peer", "unreliable")
func submit_state(pos: Vector3, ry: float, act: String, pname: String) -> void:
	if not server_mode:
		return  # 客户端收到一律忽略（防伪造）
	var pid := _sender_pid()
	if not peer_room.has(pid):
		return  # 没进房的上报直接丢弃
	var room: Dictionary = rooms[peer_room[pid]]
	room["players"][pid] = {"pos": pos, "ry": ry, "act": act, "name": pname, "t": 0.0}


## 服务器 → 客户端：下发本房间快照（仅客户端执行）
@rpc("authority", "unreliable")
func deliver_snap(snap: Dictionary) -> void:
	if server_mode:
		return
	players = snap


## 服务器 → 客户端：荒诞事件广播（所有房间都收到——服务器级氛围组）
@rpc("authority", "reliable")
func deliver_event(msg: String) -> void:
	if server_mode:
		return
	last_event_msg = msg
	event_received.emit(msg)


## 客户端 → 服务器：发送聊天（仅客户端调用；空文本直接忽略）
func send_chat(text: String) -> void:
	if not server_mode and connected_ok and text.strip_edges() != "":
		submit_chat.rpc_id(1, text.strip_edges())


## 客户端 → 服务器：聊天上行（仅服务器执行，转发给发送者同房间的牛）
@rpc("any_peer", "reliable")
func submit_chat(text: String) -> void:
	if not server_mode:
		return
	var pid := _sender_pid()
	if not peer_room.has(pid):
		return
	var room: Dictionary = rooms[peer_room[pid]]
	var pname: String = "神秘小牛"
	if room["players"].has(pid):
		pname = room["players"][pid].get("name", "神秘小牛")
	if pname == "…":
		pname = "神秘小牛"
	for member in room["players"]:
		deliver_chat.rpc_id(member, pname, text)


## 服务器 → 客户端：聊天下发（仅客户端执行）
@rpc("authority", "reliable")
func deliver_chat(pname: String, text: String) -> void:
	if server_mode:
		return
	chat_received.emit(pname, text)


## 客户端 → 服务器：发送游戏事件（KO 播报/死亡/完赛等；仅客户端调用）
func send_game_event(data: Dictionary) -> void:
	if not server_mode and connected_ok:
		submit_game_event.rpc_id(1, data)


## 客户端 → 服务器：游戏事件上行（仅服务器执行，转发给同房间）
@rpc("any_peer", "reliable")
func submit_game_event(data: Dictionary) -> void:
	if not server_mode:
		return
	var pid := _sender_pid()
	if not peer_room.has(pid):
		return
	var room: Dictionary = rooms[peer_room[pid]]
	for member in room["players"]:
		deliver_game_event.rpc_id(member, data)


## 服务器 → 客户端：游戏事件广播（仅客户端执行）
@rpc("authority", "reliable")
func deliver_game_event(data: Dictionary) -> void:
	if server_mode:
		return
	game_event_received.emit(data)


## 服务器 → 客户端：下发房间当前模式（仅客户端执行）
@rpc("authority", "reliable")
func deliver_mode(mode_key: String) -> void:
	if server_mode:
		return
	mode_received.emit(mode_key)


# ————————————————— 内部 —————————————————

func _sender_pid() -> int:
	var pid := get_tree().get_multiplayer().get_remote_sender_id()
	return pid if pid != 0 else 1


## 房间号合法化：去空白、截 8 字；空则默认 "1"
func _sanitize_room(room_id: String) -> String:
	var rid := room_id.strip_edges().substr(0, 8)
	return rid if rid != "" else "1"


## 服务器：把 pid 移出所在房间（空房销毁）
func _leave_room(pid: int) -> void:
	if not peer_room.has(pid):
		return
	var rid: String = peer_room[pid]
	peer_room.erase(pid)
	if rooms.has(rid):
		rooms[rid]["players"].erase(pid)
		if rooms[rid]["players"].is_empty():
			rooms.erase(rid)


## 服务器：pid 的显示名（从其房间状态里取；还没有就 "…"）
func my_name_of(pid: int) -> String:
	if peer_room.has(pid) and rooms.has(peer_room[pid]):
		var st: Dictionary = rooms[peer_room[pid]]["players"].get(pid, {})
		return st.get("name", "…")
	return "…"


func _prune_stale(room: Dictionary) -> void:
	# 5 秒没上报的玩家踢出快照（大概率已断线）
	for pid in room["players"].keys():
		room["players"][pid]["t"] += 1.0 / SNAP_HZ
		if room["players"][pid]["t"] > 5.0:
			room["players"].erase(pid)
			peer_room.erase(pid)


func _on_peer_connected(pid: int) -> void:
	if server_mode:
		print("[服务器] 小牛 %d 已连接（等待进房……）" % pid)


func _on_peer_disconnected(pid: int) -> void:
	if server_mode:
		var rid: String = peer_room.get(pid, "")
		_leave_room(pid)
		print("[服务器] 小牛 %d 离场%s" % [pid, ("（房间 " + rid + "）") if rid != "" else ""])
