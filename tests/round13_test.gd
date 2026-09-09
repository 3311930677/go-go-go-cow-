extends SceneTree
## 第 13 轮测试：真水——地形挖坑 / 波动水面 / 浮力游泳 / 环流。
## 运行：Godot --headless --path D:\牛来 --script res://tests/round13_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("[PASS] %s" % name)
	else:
		_fail += 1
		print("[FAIL] %s  %s" % [name, detail])


func _run() -> void:
	print("==== 牛走 · 第 13 轮测试（真水） ====")
	NetConfig.enabled = false
	ModeConfig.mode = "free"
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(2.0).timeout

	var player: PlayerCow = game.player
	var terrain: Grassland = game.terrain
	var pc := Vector3(terrain.POND_POSITION.x, 0.0, terrain.POND_POSITION.y)

	# ———— 1. 地形挖坑 ————
	var center_h := terrain.height_at(pc.x, pc.z)
	var rim_h := terrain.height_at(pc.x + 9.0, pc.z)
	_check(rim_h - center_h > 3.0, "地形：池心比周边低 3 米以上（碗形水坑）",
		"center=%.2f rim=%.2f" % [center_h, rim_h])
	_check(terrain.water_level < terrain._pond_base and terrain.water_level > center_h,
		"水位在坑底与地面之间",
		"level=%.2f base=%.2f bottom=%.2f" % [terrain.water_level, terrain._pond_base, center_h])

	# ———— 2. 水域查询 ————
	_check(terrain.is_in_water(Vector3(pc.x, terrain.water_level - 1.0, pc.z)), "池心水下 → 在水里")
	_check(not terrain.is_in_water(Vector3(pc.x, terrain.water_level + 1.0, pc.z)), "池心水上 → 不在水里")
	_check(not terrain.is_in_water(Vector3(0, -10.0, 0)), "远处陆地 → 不在水里")
	_check(terrain.water_depth_at(Vector3(pc.x, terrain.water_level - 1.0, pc.z)) > 0.9, "水深采样正确",
		str(terrain.water_depth_at(Vector3(pc.x, terrain.water_level - 1.0, pc.z))))

	# ———— 3. 水面网格与材质 ————
	var pond := game.get_node_or_null("Grassland/Pond") as MeshInstance3D
	_check(pond != null, "水面节点存在")
	if pond != null:
		var mat := pond.material_override
		_check(mat is ShaderMaterial, "水面用波动着色器", str(mat))
		_check(pond.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() >= 24 * 12 * 3,
			"水面网格顶点足够密（波浪可见）",
			str(pond.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()))
		_check(absf(pond.global_position.y - terrain.water_level) < 0.01, "水面高度 = water_level")
	var wbody := game.get_node_or_null("Grassland/WaterBody")
	_check(wbody != null, "水体物理节点（浮力+环流）存在")

	# ———— 4. 玩家浮力：扔进池底会浮上来 ————
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(pc.x, center_h + 0.4, pc.z)
	for i in 180:
		await physics_frame
	_check(player.global_position.y > terrain.water_level - 1.0, "玩家在水中浮到水面附近",
		"y=%.2f level=%.2f" % [player.global_position.y, terrain.water_level])

	# ———— 5. 刚体浮力：石头掉水里会浮起来 ————
	var rb := RigidBody3D.new()
	rb.name = "TestFloatRock%d" % randi()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	col.shape = box
	rb.add_child(col)
	rb.add_to_group("dynamic_props")
	game.add_child(rb)
	rb.global_position = Vector3(pc.x + 3.0, center_h + 0.4, pc.z)  # 偏离池心——环流在圆心处推不动东西
	var start_xz := Vector2(rb.global_position.x, rb.global_position.z)
	for i in 150:
		await physics_frame
	_check(rb.global_position.y > terrain.water_level - 1.2, "刚体浮到水面附近",
		"y=%.2f level=%.2f" % [rb.global_position.y, terrain.water_level])

	# ———— 6. 环流：漂浮物被水流推着走 ————
	var drift := Vector2(rb.global_position.x, rb.global_position.z).distance_to(start_xz)
	_check(drift > 0.15, "环流推着漂浮物移动（水在流）", "drift=%.2f" % drift)

	# ———— 7. 草与树不泡水 ————
	var grass_ok := true
	for g in terrain._grass_positions:
		if Vector2(g.x, g.z).distance_to(terrain.POND_POSITION) < terrain.POND_BOWL_OUTER - 0.6:
			grass_ok = false
	_check(grass_ok, "草丛不长进水里")
	var trees_ok := true
	for t in terrain.tree_positions:
		if Vector2(t.x, t.z).distance_to(terrain.POND_POSITION) < terrain.POND_FLAT_R + 1.0:
			trees_ok = false
	_check(trees_ok, "树不泡在水里")

	rb.queue_free()
	game.queue_free()
	await create_timer(1.0).timeout
	_finish()


func _finish() -> void:
	print("==== 结果：%d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
