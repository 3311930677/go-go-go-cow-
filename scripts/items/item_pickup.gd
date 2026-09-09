class_name ItemPickup
extends Node3D
## 道具掉落物：每件道具一个"手工感"小模型（药水瓶/靴子/号角/沙漏/炸弹/哨子），
## 悬浮旋转发光——远看像信标，近看是个半成品。空投模式可从天而降。

signal picked(pile: ItemPickup, item_id: String)

var item_id := "potion"
var active := true

var _model: Node3D
var _light: OmniLight3D
var _area: Area3D
var _t := 0.0

# 空投下落（竞技模式补给）
var _fall_speed := 0.0
var _floor_y := 0.0


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.name = "GlowLight"
	_light.omni_range = 4.5
	_light.light_energy = 1.2
	_light.position = Vector3(0, 0.8, 0)
	add_child(_light)

	_area = Area3D.new()
	_area.name = "PickArea"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.8
	col.shape = shape
	_area.add_child(col)
	_area.body_entered.connect(_on_body)
	add_child(_area)

	_build_model()


func _process(delta: float) -> void:
	_t += delta
	if not active:
		return
	# 悬浮 + 旋转——廉价的全息感
	if _model != null:
		_model.position.y = 0.6 + sin(_t * 2.5) * 0.15
		_model.rotation.y += 1.2 * delta
	if _light != null:
		_light.light_energy = 1.0 + sin(_t * 3.0) * 0.35
	# 空投下落：缓缓飘落，落地即停
	if _fall_speed > 0.0:
		position.y -= _fall_speed * delta
		if position.y <= _floor_y:
			position.y = _floor_y
			_fall_speed = 0.0


## 空投模式：从高处缓缓降落（像一片不太可靠的羽毛）
func start_airdrop(floor_y: float) -> void:
	_floor_y = floor_y
	_fall_speed = 5.5


## 设置道具与出生位置（漂移由调用方算好）
func setup(id: String, pos: Vector3) -> void:
	item_id = id
	global_position = pos
	_refresh(id)
	set_active(true)


## 换一种道具（重生时用）
func set_item(id: String) -> void:
	item_id = id
	_refresh(id)


func set_active(on: bool) -> void:
	active = on
	visible = on
	if _area != null:
		_area.monitoring = on
		_area.monitorable = on


func _refresh(id: String) -> void:
	item_id = id
	if _model == null:
		return  # _ready 未跑（未入树）——入树后会补建
	if _model.get_parent() == self:
		remove_child(_model)
		_model.queue_free()
	_build_model()


# ————————————————— 手工感小模型工厂 —————————————————

func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var mat := _glow_mat(ItemDefs.color_of(item_id))
	var dark := _glow_mat(ItemDefs.color_of(item_id).darkened(0.45))

	match item_id:
		"potion":    _mk_potion(_model, mat, dark)
		"boots":     _mk_boots(_model, mat, dark)
		"horn":      _mk_horn(_model, mat, dark)
		"rewind":    _mk_hourglass(_model, mat, dark)
		"bomb":      _mk_bomb(_model, mat, dark)
		"whistle":   _mk_whistle(_model, mat, dark)
		"wolf_tooth": _mk_tooth(_model, mat, dark)
		"wolf_skin":  _mk_wolf_skin(_model, mat, dark)
		"wolf_bone":  _mk_wolf_bone(_model, mat, dark)
		_:           _mk_potion(_model, mat, dark)  # 兜底：当成药水

	if _light != null:
		_light.light_color = ItemDefs.color_of(item_id)


## 穿模药水：圆瓶身 + 细瓶颈 + 瓶塞（歪的）
func _mk_potion(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.26
	sphere.height = 0.44
	body.mesh = sphere
	body.material_override = mat
	root.add_child(body)

	var neck := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.11
	cyl.height = 0.22
	neck.mesh = cyl
	neck.position = Vector3(0, 0.3, 0)
	neck.material_override = mat
	root.add_child(neck)

	var cork := MeshInstance3D.new()
	var ccyl := CylinderMesh.new()
	ccyl.top_radius = 0.11
	ccyl.bottom_radius = 0.11
	ccyl.height = 0.08
	cork.mesh = ccyl
	cork.position = Vector3(0.03, 0.44, 0)  # 塞子微微歪——手工灌装
	cork.rotation.z = 0.15
	cork.material_override = dark
	root.add_child(cork)


## 反向重力靴：鞋身 + 微翘的鞋头（左右反穿谁也看不出来）
func _mk_boots(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var sole := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.22, 0.5)
	sole.mesh = box
	sole.position = Vector3(0, -0.1, 0)
	sole.material_override = dark
	root.add_child(sole)

	var shaft := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.3, 0.4, 0.28)
	shaft.mesh = sbox
	shaft.position = Vector3(0, 0.16, -0.08)
	shaft.material_override = mat
	root.add_child(shaft)

	var toe := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.32, 0.12, 0.18)
	toe.mesh = tbox
	toe.position = Vector3(0, 0.04, 0.26)
	toe.rotation.x = -0.25  # 翘头
	toe.material_override = mat
	root.add_child(toe)


## 弹射号角：横放锥筒 + 号口
func _mk_horn(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var cone := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.05
	cyl.height = 0.55
	cone.mesh = cyl
	cone.rotation.x = PI * 0.5  # 横放：号口朝 +Z
	cone.position = Vector3(0, 0.05, 0)
	cone.material_override = mat
	root.add_child(cone)

	var bell := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.24
	bcyl.bottom_radius = 0.22
	bcyl.height = 0.1
	bell.mesh = bcyl
	bell.rotation.x = PI * 0.5
	bell.position = Vector3(0, 0.05, 0.3)
	bell.material_override = dark
	root.add_child(bell)


## 时光回闪：两个锥体对顶的沙漏（沙子在网上倒流）
func _mk_hourglass(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var top := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.02
	tc.bottom_radius = 0.2
	tc.height = 0.26
	top.mesh = tc
	top.position = Vector3(0, 0.16, 0)
	top.material_override = mat
	root.add_child(top)

	var bot := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.2
	bc.bottom_radius = 0.02
	bc.height = 0.26
	bot.mesh = bc
	bot.position = Vector3(0, -0.14, 0)
	bot.material_override = mat
	root.add_child(bot)

	# 上下盖片
	for gy in [0.31, -0.29]:
		var cap := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.26, 0.04, 0.26)
		cap.mesh = cbox
		cap.position = Vector3(0, gy, 0)
		cap.material_override = dark
		root.add_child(cap)


## 笨笨炸弹：圆球 + 一根不太可靠的引线
func _mk_bomb(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	ball.mesh = sphere
	ball.material_override = mat
	root.add_child(ball)

	var fuse := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.02
	fc.bottom_radius = 0.02
	fc.height = 0.18
	fuse.mesh = fc
	fuse.position = Vector3(0.05, 0.3, 0)
	fuse.rotation.z = -0.3
	fuse.material_override = dark
	root.add_child(fuse)


## 伙伴哨子：横管 + 吹口小球
func _mk_whistle(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var tube := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.5
	tube.mesh = cyl
	tube.rotation.z = PI * 0.5  # 横放
	tube.position = Vector3(0, 0, 0)
	tube.material_override = mat
	root.add_child(tube)

	var mouth := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 0.11
	ms.height = 0.2
	mouth.mesh = ms
	mouth.position = Vector3(-0.26, 0.03, 0)
	mouth.material_override = dark
	root.add_child(mouth)


## 狼牙：尖白锥 + 底托
func _mk_tooth(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var spike := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.13
	cone.height = 0.42
	spike.mesh = cone
	spike.rotation.x = -PI * 0.5  # 尖朝上
	spike.position = Vector3(0, 0.12, 0)
	spike.material_override = mat
	root.add_child(spike)
	var base := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.18, 0.06, 0.18)
	base.mesh = bbox
	base.position = Vector3(0, -0.1, 0)
	base.material_override = dark
	root.add_child(base)


## 狼皮：一块毛茸茸（其实就是粗糙）的灰色扁板
func _mk_wolf_skin(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var slab := MeshInstance3D.new()
	var smesh := BoxMesh.new()
	smesh.size = Vector3(0.5, 0.08, 0.65)
	slab.mesh = smesh
	slab.material_override = mat
	root.add_child(slab)
	var fold := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(0.3, 0.06, 0.2)
	fold.mesh = fbox
	fold.position = Vector3(0.08, 0.05, -0.12)
	fold.rotation.y = 0.5
	fold.material_override = dark
	root.add_child(fold)


## 狼骨粉：一根小骨头（粉是噱头，骨头是道具）
func _mk_wolf_bone(root: Node3D, mat: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 0.4
	shaft.mesh = cyl
	shaft.rotation.z = PI * 0.5  # 横放
	shaft.material_override = mat
	root.add_child(shaft)
	for sx in [-0.14, 0.14]:
		var cap := MeshInstance3D.new()
		var csphere := SphereMesh.new()
		csphere.radius = 0.1
		csphere.height = 0.2
		cap.mesh = csphere
		cap.position = Vector3(sx, 0, 0)
		cap.material_override = dark
		root.add_child(cap)


func _glow_mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 1.6
	mat.roughness = 1.0
	return mat


func _on_body(body: Node3D) -> void:
	if not active:
		return
	if body is PlayerCow:
		active = false  # 先关，防止一帧内重复触发
		picked.emit(self, item_id)
