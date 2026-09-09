extends SceneTree
## 视觉自检：非 headless 运行主场景，等待数秒后截图保存，用于人工审查画面效果。
## 运行方式（会短暂弹出游戏窗口）：
##   Godot_v4.6.1-stable_win64.exe --path . --script res://tests/screenshot_test.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		print("[FAIL] 主场景加载失败")
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)

	# 等待渲染稳定（让小牛落地、相机就位）
	for i in 150:
		await process_frame

	var img: Image = root.get_texture().get_image()
	img.save_png("res://tests/shot_round1.png")
	print("[OK] 截图已保存：res://tests/shot_round1.png")
	quit(0)
