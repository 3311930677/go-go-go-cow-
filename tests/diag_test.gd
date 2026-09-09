extends SceneTree
## 视觉诊断：截图前打印玩家/相机状态与视线射线检测结果，用于定位画面问题。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)

	for i in 150:
		await process_frame

	var player := main.get_node("PlayerCow") as Node3D
	var cam_rig := main.get_node("CowCamera") as Node3D
	var cam3d := cam_rig.get_child(0) as Camera3D

	print("player pos: ", player.global_position)
	print("camera rig pos: ", cam_rig.global_position)
	print("camera3d pos: ", cam3d.global_position)
	print("camera forward(-Z): ", -cam3d.global_transform.basis.z)

	# 视线射线：从相机中心打出，看命中什么
	var from := cam3d.global_position
	var to := from + (-cam3d.global_transform.basis.z) * 120.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		print("ray hit: <无命中——视野正对天空！>")
	else:
		print("ray hit: ", hit.get("collider"), " at ", hit.get("position"))

	# 玩家是否在相机视野内（投影到相机屏幕空间）
	var vp_pos := cam3d.unproject_position(player.global_position + Vector3(0, 0.8, 0))
	print("玩家在屏幕上的投影坐标: ", vp_pos)

	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/shot_diag.png")
	print("[OK] 诊断截图已保存")
	quit(0)
