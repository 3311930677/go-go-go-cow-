class_name Alpaca
extends Node3D
## 毛蛋：一只粉色羊驼（支线 NPC）。它出现在离谱的地方
## （山顶 / "水底" / 半空悬浮），站在原地等待投喂。

var fed := false

var _head: Node3D
var _clock := 0.0


func _ready() -> void:
	_build_model()


func _process(_delta: float) -> void:
	_clock += _delta
	var t := floorf(_clock * 8.0) / 8.0  # 8FPS 定格
	if fed:
		_head.rotation.x = 0.7  # 低头一直吃
	else:
		_head.rotation.x = sin(t * TAU * 0.5) * 0.08  # 呆滞点头


func _build_model() -> void:
	var fluff := _mat(Color(0.98, 0.78, 0.84))  # 粉毛
	var dark := _mat(Color(0.15, 0.12, 0.12))
	var face := _mat(Color(0.95, 0.85, 0.88))

	_box(self, Vector3(1.2, 1.0, 1.6), fluff, Vector3(0, 1.15, 0))  # 蓬松身体

	# 脖子 + 头（可低头）
	_head = Node3D.new()
	_head.position = Vector3(0, 1.5, 0.55)
	add_child(_head)
	_box(_head, Vector3(0.34, 0.85, 0.34), fluff, Vector3(0, 0.42, 0))      # 长脖子
	_box(_head, Vector3(0.42, 0.36, 0.5), face, Vector3(0, 0.95, 0.12))    # 头
	_box(_head, Vector3(0.1, 0.16, 0.06), fluff, Vector3(0.14, 1.2, -0.02))  # 耳朵
	_box(_head, Vector3(0.1, 0.16, 0.06), fluff, Vector3(-0.14, 1.2, -0.02))
	_box(_head, Vector3(0.06, 0.08, 0.06), dark, Vector3(0.14, 1.0, 0.32))   # 眼睛
	_box(_head, Vector3(0.06, 0.08, 0.06), dark, Vector3(-0.14, 1.0, 0.32))

	# 四条细腿
	for lx in [0.4, -0.4]:
		for lz in [0.55, -0.55]:
			_box(self, Vector3(0.18, 0.7, 0.18), face, Vector3(lx, 0.35, lz))


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
