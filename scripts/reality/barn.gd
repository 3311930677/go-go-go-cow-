class_name Barn
extends Node3D
## 现实模式的牛棚：木板墙、稻草地、奶盆、几捆稻草。
## 建在 y=200 的悬空平台上——与梦境世界物理隔离。
## 暖褐色"棚内"环境光——昏暗廉价。

var weak_cow: WeakCow
var milk_pos: Vector3


func _ready() -> void:
	# —— 棚内环境（梦境环境随 grassland 隐藏后由这里接管） ——
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.12, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.7, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var wood := _mat(Color(0.42, 0.3, 0.18))
	var wood_dark := _mat(Color(0.32, 0.22, 0.13))
	var straw := _mat(Color(0.78, 0.68, 0.35))
	var straw_dark := _mat(Color(0.68, 0.58, 0.28))

	# —— 稻草地台（20x20） ——
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(20.0, 0.5, 20.0)
	fcol.shape = fbox
	fcol.position = Vector3(0, -0.25, 0)
	floor_body.add_child(fcol)
	_box(self, Vector3(20.0, 0.5, 20.0), straw, Vector3(0, -0.25, 0))

	# —— 木板墙（北墙留门） ——
	var wall_h := 3.2
	var wall_t := 0.4
	# 南墙（z=-10）
	_wall(Vector3(0, wall_h * 0.5, -10.0), Vector3(20.0, wall_h, wall_t), wood)
	# 东墙 / 西墙
	_wall(Vector3(10.0, wall_h * 0.5, 0.0), Vector3(wall_t, wall_h, 20.0), wood)
	_wall(Vector3(-10.0, wall_h * 0.5, 0.0), Vector3(wall_t, wall_h, 20.0), wood)
	# 北墙（z=+10，中间留 3 米门洞）
	_wall(Vector3(-6.5, wall_h * 0.5, 10.0), Vector3(7.0, wall_h, wall_t), wood_dark)
	_wall(Vector3(6.5, wall_h * 0.5, 10.0), Vector3(7.0, wall_h, wall_t), wood_dark)

	# —— 稻草捆（3 捆，随机摆） ——
	for pos in [Vector3(-6.0, 0.45, -6.0), Vector3(7.0, 0.45, -4.0), Vector3(-5.0, 0.45, 6.5)]:
		var b := _box(self, Vector3(1.4, 0.9, 0.9), straw_dark, pos)
		b.rotation.y = randf_range(0.0, TAU)

	# —— 奶盆（红色圆柱 + 白色奶面） ——
	var bucket := Node3D.new()
	bucket.position = Vector3(0.0, 0.0, 5.0)
	add_child(bucket)
	var bucket_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.45
	cyl.height = 0.5
	cyl.radial_segments = 10
	bucket_mesh.mesh = cyl
	bucket_mesh.material_override = _mat(Color(0.75, 0.2, 0.15))
	bucket_mesh.position = Vector3(0, 0.25, 0)
	bucket.add_child(bucket_mesh)
	var milk := MeshInstance3D.new()
	var milk_cyl := CylinderMesh.new()
	milk_cyl.top_radius = 0.5
	milk_cyl.bottom_radius = 0.5
	milk_cyl.height = 0.06
	milk_cyl.radial_segments = 10
	milk.mesh = milk_cyl
	milk.material_override = _mat(Color(0.97, 0.96, 0.92))
	milk.position = Vector3(0, 0.5, 0)
	bucket.add_child(milk)
	milk_pos = bucket.position

	# —— 孱弱小牛 ——
	weak_cow = WeakCow.new()
	weak_cow.milk_pos = milk_pos
	add_child(weak_cow)
	weak_cow.global_position = Vector3(0.0, 200.5, -2.0)


func _wall(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	_box(self, size, mat, pos)


func _box(parent: Node3D, size: Vector3, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m
