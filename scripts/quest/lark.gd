class_name Lark
extends Node3D
## 迷路的云雀（主线 NPC）：出生时卡在离谱的位置（半埋地下/树冠里/天上），
## 玩家冲撞它附近把它"撞出来"，然后它跟着玩家回巢。
## 动画全部 8FPS 定格——与主角一致的僵硬质感。

enum State { STUCK, FOLLOW, NESTED }

var state: int = State.STUCK
var stuck_variant := 0  # 0 半埋地下 / 1 卡在树里 / 2 悬浮天上
var player: PlayerCow

var _root: Node3D
var _wings: Array[Node3D] = []
var _clock := 0.0
var _nest_pos: Vector3
var _prev_pos := Vector3.ZERO


func _ready() -> void:
	_build_model()
	_prev_pos = global_position


## 被冲撞"撞出"→ 开始跟着玩家
func unstick() -> void:
	state = State.FOLLOW
	_root.rotation.x = 0.0


## 护送到巢 → 飞去巢里蹲着
func go_to_nest(nest_pos: Vector3) -> void:
	state = State.NESTED
	_nest_pos = nest_pos + Vector3(0, 0.35, 0)


func _process(delta: float) -> void:
	_clock += delta
	# 8FPS 定格量化
	var phase := floorf(_clock * 8.0)
	var t := phase / 8.0

	match state:
		State.STUCK:
			if stuck_variant == 2:
				# 卡在天上：原地扑腾 + 上下漂浮
				_flap(t)
				_root.position.y = sin(t * TAU) * 0.3
			else:
				# 埋土/卡树：翅膀收拢，原地抽搐（8FPS 跳变，挣扎感）
				for w in _wings:
					w.rotation.z = 0.08
				_root.position = Vector3((1.0 if int(phase) % 2 == 0 else -1.0) * 0.05, 0.0, 0.0)
				if stuck_variant == 0:
					_root.rotation.x = -0.45  # 头朝上露出土面
		State.FOLLOW:
			_flap(t)
			var target := player.global_position + Vector3(0, 2.4 + sin(t * TAU) * 0.25, 0)
			global_position = global_position.lerp(target, 1.0 - exp(-3.5 * delta))
			var moved := global_position - _prev_pos
			if moved.length() > 0.01:
				rotation.y = atan2(moved.x, moved.z)
			_root.position = Vector3.ZERO
			_root.rotation.x = 0.0
		State.NESTED:
			for w in _wings:
				w.rotation.z = 0.08
			global_position = global_position.lerp(_nest_pos, 1.0 - exp(-4.0 * delta))
			_root.position.y = maxf(0.0, sin(t * TAU * 0.5)) * 0.12  # 偶尔小跳
	_prev_pos = global_position


func _flap(t: float) -> void:
	var a := sin(t * TAU * 2.0) * 0.9
	_wings[0].rotation.z = a
	_wings[1].rotation.z = -a


# ————————————————— 建模 —————————————————

func _build_model() -> void:
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)

	var brown := _mat(Color(0.55, 0.42, 0.3))
	var dark := _mat(Color(0.2, 0.16, 0.12))
	var orange := _mat(Color(0.95, 0.6, 0.15))
	var white := _mat(Color(0.92, 0.9, 0.85))

	_box(_root, Vector3(0.42, 0.36, 0.6), brown, Vector3(0, 0, 0))          # 身体
	_box(_root, Vector3(0.3, 0.28, 0.3), brown, Vector3(0, 0.2, 0.32))      # 头
	_box(_root, Vector3(0.36, 0.1, 0.34), white, Vector3(0, -0.02, -0.05))  # 肚皮
	# 喙：+Z 方向的四棱锥
	var beak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.06
	cone.height = 0.22
	cone.radial_segments = 4
	beak.mesh = cone
	beak.material_override = orange
	beak.position = Vector3(0, 0.18, 0.52)
	beak.rotation.x = PI / 2.0
	_root.add_child(beak)
	# 眼睛
	_box(_root, Vector3(0.05, 0.06, 0.05), dark, Vector3(0.12, 0.26, 0.4))
	_box(_root, Vector3(0.05, 0.06, 0.05), dark, Vector3(-0.12, 0.26, 0.4))
	# 尾巴
	_box(_root, Vector3(0.2, 0.05, 0.28), dark, Vector3(0, 0.04, -0.4))
	# 翅膀（枢轴在翼根，便于拍打）
	for side in [1.0, -1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.22, 0.08, 0)
		_root.add_child(pivot)
		_box(pivot, Vector3(0.5, 0.05, 0.36), brown, Vector3(side * 0.25, 0, 0))
		_wings.append(pivot)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _box(parent: Node3D, size: Vector3, mat: StandardMaterial3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
