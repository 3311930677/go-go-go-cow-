class_name Stalagmite
extends Area3D
## 发光石笋：金草同款自发光棱锥。碰到的瞬间判定——走上去就吃（廉价交互）。
## 吃 5 个 → PlayerCow 长初级角（P1-B 局内成长点）。

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 2.2
	col.shape = shape
	col.position = Vector3(0, 1.1, 0)
	add_child(col)

	# 视觉：两段叠加的自发光棱锥（像一颗拔高的石笋)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.8)
	mat.emission_energy_multiplier = 1.6
	mat.roughness = 0.4
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.34
	mesh.height = 1.4
	mesh.radial_segments = 7
	cone.mesh = mesh
	cone.material_override = mat
	cone.position = Vector3(0, 0.7, 0)
	add_child(cone)
	var cap := MeshInstance3D.new()
	var m2 := CylinderMesh.new()
	m2.top_radius = 0.0
	m2.bottom_radius = 0.22
	m2.height = 0.8
	m2.radial_segments = 7
	cap.mesh = m2
	cap.material_override = mat
	cap.position = Vector3(0, 1.7, 0)
	add_child(cap)

	# 呼吸式发光
	var tw := create_tween().set_loops()
	tw.tween_property(mat, "emission_energy_multiplier", 2.3, 1.1)
	tw.tween_property(mat, "emission_energy_multiplier", 1.4, 1.1)


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerCow and (body as PlayerCow).gain_horn_shard():
		# 吃完垮掉的演出：缩回地里
		monitoring = false
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ZERO, 0.25)
		tw.tween_callback(queue_free)