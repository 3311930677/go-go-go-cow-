extends SceneTree
## 探针：标题画面各按钮/标签的实际渲染矩形
## 运行：Godot --headless --path D:\牛来 --script res://tests/probe_title.gd

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var scene: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.5).timeout
	var vp_size := root.get_visible_rect().size
	print("视口大小: %s" % str(vp_size))
	_walk(scene, 0)
	quit(0)


func _walk(node: Node, depth: int) -> void:
	if node is Control:
		var c := node as Control
		var txt := ""
		if c is Button or c is Label or c is LineEdit:
			txt = str(c.text) if "text" in c else ""
		print("%s%s [%s] pos=%s size=%s text=%s" % [
			"  ".repeat(depth), c.name, c.get_class(),
			str(c.global_position.round()), str(c.size.round()), txt])
	for child in node.get_children():
		_walk(child, depth + 1)
