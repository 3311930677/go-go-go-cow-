class_name Grassland
extends Node3D
## 程序化草原：低多边形地形（flat shading）、草丛、树、石头。
## 刻意压低分段与纯色材质——"灾难级"画质的刻意呈现。
## 同时提供吃草 API：has_grass_near / consume_grass_near（金草 +50）。
## 隐藏区：被"看起来很结实的墙"围住，只能靠冲撞穿模进入。

const WORLD_SIZE := 200.0   # 世界边长（米）
const SEGMENTS := 100       # 地形分段（每格 2 米——棱角分明的低模）
const GRASS_COUNT := 600    # 随机草丛数量
const TREE_COUNT := 40      # 树数量（其中 4 棵可被冲撞推倒）
const ROCK_COUNT := 8       # 高弹力动态石头数量
const NOISE_SEED := 20260902

const NORMAL_GRASS_VALUE := 10  # 普通草的吃饱度增量
const GOLD_GRASS_VALUE := 50    # 金草的吃饱度增量

## 隐藏区中心（世界坐标 XZ）与尺寸
const SECRET_CENTER := Vector2(-60.0, -60.0)
const SECRET_HALF := 6.0        # 半宽（墙到中心距离）
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 0.6

## 脆弱墙所在碰撞层（bit 3）——玩家冲撞时无视此层即可穿模
const FRAGILE_LAYER := 4

var hud: GameHUD  # 由 game.gd 注入（穿墙/雕像彩蛋文案）
var golden_eaten := 0  # 已吃金草数（Bug 复刻挑战用）

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
## 普通草丛数据：位置 + 存活标记（索引对齐 MultiMesh 实例）
var _grass_positions: Array[Vector3] = []
var _grass_alive: Array[bool] = []
var _grass_multimesh: MultiMesh
## 金草数据（隐藏区内，位置 + 存活 + 独立网格）
var _gold_positions: Array[Vector3] = []
var _gold_alive: Array[bool] = []
var _gold_meshes: Array[MeshInstance3D] = []
## 金牛雕像（持续旋转）
var _statue_model: CowModel
var _wall_hint_cooldown := 0.0
## 静态树位置（云雀"卡在树里"用）
var tree_positions: Array[Vector3] = []
## 池塘（真水：挖坑 + 波动水面 + 可游泳）位置与形状
const POND_POSITION := Vector2(45.0, 40.0)
const POND_DEPTH := 4.0        # 坑深（碗底相对周边地面）
const POND_BOWL_INNER := 4.8   # 满深度半径（碗身从这里开始收口）
const POND_BOWL_OUTER := 7.2   # 碗沿半径（之外恢复原地形）
const POND_FLAT_R := 8.0       # 池塘周边拍平半径（保证碗沿高于水面）
const POND_FLAT_FADE := 6.0    # 拍平区到原地形过渡带宽
const WATER_MESH_R := 6.05     # 水面网格半径（≈岸边线）
## 水面高度（世界 Y，_ready 里算好）
var water_level := 0.0
var _pond_base := 0.0          # 池塘周边拍平后的基准高度


func _ready() -> void:
	_noise.seed = NOISE_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_rng.seed = NOISE_SEED
	# 池塘基准高度 & 水位（地形拍平 + 挖碗都以此为参照）
	_pond_base = _base_height(POND_POSITION.x, POND_POSITION.y)
	water_level = _pond_base - 1.9
	_build_environment()
	_build_terrain()
	_build_grass()
	_build_trees()
	_build_rocks()
	_build_stalagmites()  # P1-B: 发光石笋（长角素材）
	_build_secret_area()
	_build_pond()


func _process(delta: float) -> void:
	# 金牛雕像：永远旋转
	if _statue_model != null:
		_statue_model.rotation.y += 0.7 * delta
	if _wall_hint_cooldown > 0.0:
		_wall_hint_cooldown -= delta


## 原始噪声地形（不含池塘改造——_pond_base 的取值基准）
func _base_height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x * 0.02, z * 0.02) * 2.6
	h += _noise.get_noise_2d(x * 0.09, z * 0.09) * 0.5
	# 出生点周围压平（半径 40 米渐变）
	var flat := clampf(Vector2(x, z).length() / 40.0, 0.0, 1.0)
	return h * flat


## 地形高度采样（世界坐标）：噪声地形 + 池塘周边拍平 + 挖出碗形水坑
func height_at(x: float, z: float) -> float:
	var h := _base_height(x, z)
	var d := Vector2(x - POND_POSITION.x, z - POND_POSITION.y).length()
	# 池塘周边拍平（半径 POND_FLAT_R 全平，往外 POND_FLAT_FADE 渐变回原地形）
	if d < POND_FLAT_R + POND_FLAT_FADE:
		var t := clampf(1.0 - (d - POND_FLAT_R) / POND_FLAT_FADE, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		h = lerpf(h, _pond_base, t)
		# 碗形水坑：POND_BOWL_INNER 内满深，到 POND_BOWL_OUTER 平滑收口
		if d < POND_BOWL_OUTER:
			var bowl := 1.0
			if d > POND_BOWL_INNER:
				var u := (d - POND_BOWL_INNER) / (POND_BOWL_OUTER - POND_BOWL_INNER)
				bowl = 1.0 - u * u * (3.0 - 2.0 * u)
			h -= POND_DEPTH * bowl
	return h


## 是否在水里（水平距离进水面半径 + 低于水位）
func is_in_water(pos: Vector3) -> bool:
	var d := Vector2(pos.x - POND_POSITION.x, pos.z - POND_POSITION.y).length()
	return d < WATER_MESH_R and pos.y < water_level


## 水下深度（0 = 不在水里/刚好在水面）
func water_depth_at(pos: Vector3) -> float:
	if not is_in_water(pos):
		return 0.0
	return water_level - pos.y


## 是否有可吃的草在半径内（含金草）
func has_grass_near(pos: Vector3, radius: float) -> bool:
	for i in _grass_positions.size():
		if _grass_alive[i] and _grass_positions[i].distance_to(pos) <= radius:
			return true
	for i in _gold_positions.size():
		if _gold_alive[i] and _gold_positions[i].distance_to(pos) <= radius:
			return true
	return false


## 吃掉半径内最近的一丛草（普通/金草统一就近），返回吃饱度增量
func consume_grass_near(pos: Vector3, radius: float) -> int:
	var best_gold := false
	var best_idx := -1
	var best_dist := radius
	for i in _grass_positions.size():
		if not _grass_alive[i]:
			continue
		var d := _grass_positions[i].distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_gold = false
			best_idx = i
	for i in _gold_positions.size():
		if not _gold_alive[i]:
			continue
		var d := _gold_positions[i].distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_gold = true
			best_idx = i
	if best_idx < 0:
		return 0
	if best_gold:
		_gold_alive[best_idx] = false
		_gold_meshes[best_idx].visible = false
		golden_eaten += 1
		return GOLD_GRASS_VALUE
	_grass_alive[best_idx] = false
	var dead := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	_grass_multimesh.set_instance_transform(best_idx, dead)
	return NORMAL_GRASS_VALUE


# ————————————————— 构建部分 —————————————————

## 廉价光影：平淡天光 + 高环境光 + 无阴影的方向光
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.72, 1.0)
	sky_mat.sky_horizon_color = Color(0.78, 0.87, 0.95)
	sky_mat.ground_bottom_color = Color(0.55, 0.7, 0.5)
	sky_mat.ground_horizon_color = Color(0.78, 0.87, 0.95)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1  # 偏亮、发灰——"刺眼"的平淡质感
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR  # 不做色调映射，直出的廉价感
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 32.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false  # 廉价光影：直接不开阴影
	add_child(sun)


## 低模地形：每三角形独立顶点 + 面法线（flat shading）
func _build_terrain() -> void:
	var surf := SurfaceTool.new()
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := WORLD_SIZE * 0.5
	var cell := WORLD_SIZE / SEGMENTS

	var p := PositionMeshBuilder.new()
	for iz in SEGMENTS:
		for ix in SEGMENTS:
			var x0 := ix * cell - half
			var z0 := iz * cell - half
			var x1 := x0 + cell
			var z1 := z0 + cell
			# 两个三角形，六个独立顶点（不共享 → 生成硬边法线）
			# 绕序为逆时针（从 +Y 俯视），法线朝上，避免背面剔除
			p.quad(surf,
				Vector3(x0, height_at(x0, z0), z0),
				Vector3(x1, height_at(x1, z0), z0),
				Vector3(x1, height_at(x1, z1), z1),
				Vector3(x0, height_at(x0, z1), z1))
	surf.generate_normals()
	var mesh := surf.commit()

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.78, 0.22)  # 刺眼的纯绿
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)

	# 静态碰撞：直接用渲染网格生成 trimesh；开启背面碰撞，确保任何绕序下都是实体
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var col := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	add_child(body)


## 草丛：MultiMesh 三棱锥。出生点外圈固定放 8 丛（保证开场可吃草）
func _build_grass() -> void:
	_grass_multimesh = MultiMesh.new()
	_grass_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_grass_multimesh.mesh = _tuft_mesh()

	var total := GRASS_COUNT + 8
	_grass_multimesh.instance_count = total

	var idx := 0
	# 出生点草环（半径 2.6 米）
	for i in 8:
		var ang := TAU * i / 8.0
		_place_grass(idx, Vector3(cos(ang) * 2.6, 0.0, sin(ang) * 2.6))
		idx += 1
	# 随机散布（避开隐藏区内部——那里的草另有安排；也避开水面——草不会长在水里）
	while idx < total:
		var x := _rng.randf_range(-90.0, 90.0)
		var z := _rng.randf_range(-90.0, 90.0)
		if Vector2(x, z).distance_to(SECRET_CENTER) < SECRET_HALF + 2.0:
			continue
		if Vector2(x, z).distance_to(POND_POSITION) < POND_BOWL_OUTER - 0.5:
			continue
		_place_grass(idx, Vector3(x, 0.0, z))
		idx += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassField"
	mmi.multimesh = _grass_multimesh
	add_child(mmi)


## 草丛网格：三棱锥（低到极致）
func _tuft_mesh() -> PrismMesh:
	var tuft := PrismMesh.new()
	tuft.size = Vector3(0.5, 0.55, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.85, 0.18)
	mat.roughness = 1.0
	tuft.material = mat
	return tuft


func _place_grass(idx: int, pos_xz: Vector3) -> void:
	var pos := Vector3(pos_xz.x, height_at(pos_xz.x, pos_xz.z) + 0.22, pos_xz.z)
	_grass_positions.append(pos)
	_grass_alive.append(true)
	var basis := Basis().rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
	_grass_multimesh.set_instance_transform(idx, Transform3D(basis, pos))


## 低模树：圆柱干 + 双层锥冠。前 4 棵为可推倒的动态树（冲撞目标）
func _build_trees() -> void:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.32, 0.2)
	trunk_mat.roughness = 1.0
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.16, 0.55, 0.16)
	leaf_mat.roughness = 1.0

	for i in TREE_COUNT:
		# 避开出生点半径 18 米、隐藏区与水坑（树不泡水）
		var x := 0.0
		var z := 0.0
		while true:
			x = _rng.randf_range(-92.0, 92.0)
			z = _rng.randf_range(-92.0, 92.0)
			if Vector2(x, z).length() > 18.0 and Vector2(x, z).distance_to(SECRET_CENTER) > SECRET_HALF + 4.0 \
				and Vector2(x, z).distance_to(POND_POSITION) > POND_FLAT_R + 2.0:
				break
		var y := height_at(x, z)
		var s := _rng.randf_range(0.8, 1.6)
		var dynamic := i < 4  # 前 4 棵可被撞倒

		var tree: PhysicsBody3D
		if dynamic:
			tree = RigidBody3D.new()
			(tree as RigidBody3D).mass = 12.0
			var phys := PhysicsMaterial.new()
			phys.friction = 0.7
			phys.bounce = 0.15
			(tree as RigidBody3D).physics_material_override = phys
			tree.add_to_group("dynamic_props")
		else:
			tree = StaticBody3D.new()
			tree_positions.append(Vector3(x, y, z))
			# P1-A 穿模升级：静态树挂"脆弱环境物"组——玩家冲撞/幽灵时穿得过（碰撞豁免），平时依旧实体
			tree.add_to_group("fragile_env")
		tree.position = Vector3(x, y, z)
		tree.rotation.y = _rng.randf_range(0.0, TAU)

		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.45 * s
		cyl.height = 3.0 * s
		col.shape = cyl
		col.position = Vector3(0, 1.5 * s, 0)
		tree.add_child(col)

		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.22 * s
		trunk_mesh.bottom_radius = 0.32 * s
		trunk_mesh.height = 2.4 * s
		trunk_mesh.radial_segments = 6  # 六棱柱树干
		trunk.mesh = trunk_mesh
		trunk.material_override = trunk_mat
		trunk.position = Vector3(0, 1.2 * s, 0)
		tree.add_child(trunk)

		# 两层锥形树冠
		for layer in 2:
			var cone := MeshInstance3D.new()
			var cone_mesh := CylinderMesh.new()
			cone_mesh.top_radius = 0.02
			cone_mesh.bottom_radius = (1.5 - 0.5 * layer) * s
			cone_mesh.height = 1.7 * s
			cone_mesh.radial_segments = 6
			cone.mesh = cone_mesh
			cone.material_override = leaf_mat
			cone.position = Vector3(0, (2.0 + 0.9 * layer) * s, 0)
			tree.add_child(cone)

		add_child(tree)



## P1-B: 散布 12 根发光石笋（吃 5 根长角）——避开出生点、隐藏区与树干
func _build_stalagmites() -> void:
	for i in 12:
		var x := 0.0
		var z := 0.0
		var tries := 0
		while tries < 200:
			x = _rng.randf_range(-86.0, 86.0)
			z = _rng.randf_range(-86.0, 86.0)
			tries += 1
			if Vector2(x, z).length() <= 18.0:
				continue
			if Vector2(x, z).distance_to(SECRET_CENTER) <= SECRET_HALF + 4.0:
				continue
			var clear := true
			for tp in tree_positions:
				if Vector2(tp.x - x, tp.z - z).length() < 2.5:
					clear = false
					break
			if not clear:
				continue
			break
		var spi := Stalagmite.new()
		spi.position = Vector3(x, height_at(x, z) - 0.12, z)
		add_child(spi)


## 找离 at 最近的存活草丛（玩家死亡复活点——复活在草边显得很"牛生"）
func nearest_grass(at: Vector3) -> Vector3:
	var best := Vector3(0.0, height_at(0.0, 0.0) + 0.5, 0.0)
	var bd := INF
	for i in _grass_positions.size():
		if not _grass_alive[i]:
			continue
		var p := _grass_positions[i]
		var d := Vector2(p.x - at.x, p.z - at.z).length_squared()
		if d < bd:
			bd = d
			best = p
	return best
## 石头：静态大石 + 高弹力动态小石（冲撞/崩坏事件的目标）
func _build_rocks() -> void:
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.55, 0.55, 0.58)
	rock_mat.roughness = 1.0
	# 静态大石：6 块
	for i in 6:
		var x := _rng.randf_range(-85.0, 85.0)
		var z := _rng.randf_range(-85.0, 85.0)
		if Vector2(x, z).length() < 16.0:
			continue
		var s := _rng.randf_range(1.0, 2.4)
		# P1-A 穿模升级：静态大石同样可被冲撞穿过
		var rock := StaticBody3D.new()
		rock.add_to_group("fragile_env")
		rock.position = Vector3(x, height_at(x, z) + s * 0.35, z)
		var col := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = s * 0.8
		col.shape = sph
		rock.add_child(col)
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = s * 0.8
		mesh.height = s * 1.3
		mesh.radial_segments = 6  # 极低分段——棱角"球"
		mesh.rings = 3
		mi.mesh = mesh
		mi.material_override = rock_mat
		rock.add_child(mi)
		add_child(rock)
	# 动态小石：弹力离谱（冲撞可击飞、事件可乱飞）
	for i in ROCK_COUNT:
		var x := _rng.randf_range(-16.0, 16.0)
		var z := _rng.randf_range(6.0, 20.0)
		var rock := RigidBody3D.new()
		rock.position = Vector3(x, height_at(x, z) + 1.2, z)
		var col := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.45
		col.shape = sph
		rock.add_child(col)
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.45
		mesh.height = 0.8
		mesh.radial_segments = 5
		mesh.rings = 2
		mi.mesh = mesh
		mi.material_override = rock_mat
		rock.add_child(mi)
		var phys_mat := PhysicsMaterial.new()
		phys_mat.bounce = 0.82  # 离谱弹力——物理崩坏
		rock.physics_material_override = phys_mat
		rock.add_to_group("dynamic_props")
		add_child(rock)

## 隐藏区：四面"看起来很结实的墙"围住，只能冲撞穿模进入。
## 内有旋转的金牛雕像（无作用）与 5 丛金草（+50）。
func _build_secret_area() -> void:
	var cx := SECRET_CENTER.x
	var cz := SECRET_CENTER.y
	var cy := height_at(cx, cz)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.25, 0.25, 0.28)  # 深灰——看起来非常结实
	wall_mat.roughness = 1.0

	# 四面墙：北/南/东/西（宽度覆盖四角）
	var walls := [
		[Vector3(cx, cy + WALL_HEIGHT * 0.5, cz - SECRET_HALF), Vector3(SECRET_HALF * 2 + 1.0, WALL_HEIGHT, WALL_THICKNESS)],
		[Vector3(cx, cy + WALL_HEIGHT * 0.5, cz + SECRET_HALF), Vector3(SECRET_HALF * 2 + 1.0, WALL_HEIGHT, WALL_THICKNESS)],
		[Vector3(cx + SECRET_HALF, cy + WALL_HEIGHT * 0.5, cz), Vector3(WALL_THICKNESS, WALL_HEIGHT, SECRET_HALF * 2 + 1.0)],
		[Vector3(cx - SECRET_HALF, cy + WALL_HEIGHT * 0.5, cz), Vector3(WALL_THICKNESS, WALL_HEIGHT, SECRET_HALF * 2 + 1.0)],
	]
	for w in walls:
		var wall := StaticBody3D.new()
		wall.collision_layer = FRAGILE_LAYER  # 独占脆弱层：平时撞得动，冲撞时穿得过
		wall.collision_mask = 0
		wall.position = w[0]
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		col.shape = box
		wall.add_child(col)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = w[1]
		mi.mesh = mesh
		mi.material_override = wall_mat
		wall.add_child(mi)
		# 穿墙瞬间的彩蛋提示（带冷却，防止反复进出刷屏）
		var hint := Area3D.new()
		var hint_col := CollisionShape3D.new()
		var hint_box := BoxShape3D.new()
		hint_box.size = w[1] + Vector3(0.4, 0.4, 0.4)
		hint_col.shape = hint_box
		hint.add_child(hint_col)
		hint.body_entered.connect(_on_wall_hint)
		wall.add_child(hint)
		add_child(wall)

	# —— 金牛雕像：底座 + 缩小版金色的牛，永远旋转 ——
	var statue := Node3D.new()
	statue.position = Vector3(cx, cy, cz)
	var pedestal_mat := StandardMaterial3D.new()
	pedestal_mat.albedo_color = Color(0.5, 0.5, 0.52)
	pedestal_mat.roughness = 1.0
	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := BoxMesh.new()
	pedestal_mesh.size = Vector3(1.4, 0.7, 1.4)
	pedestal.mesh = pedestal_mesh
	pedestal.material_override = pedestal_mat
	pedestal.position = Vector3(0, 0.35, 0)
	statue.add_child(pedestal)

	_statue_model = CowModel.new()
	_statue_model.body_color = Color(1.0, 0.83, 0.25)      # 金身
	_statue_model.patch_color = Color(0.8, 0.6, 0.1)       # 暗金斑
	_statue_model.position = Vector3(0, 0.7, 0)
	_statue_model.scale = Vector3(0.75, 0.75, 0.75)
	statue.add_child(_statue_model)  # add_child 触发 _build，使用金色配色
	add_child(statue)

	# 雕像提示区
	var statue_hint := Area3D.new()
	statue_hint.position = Vector3(cx, cy + 1.5, cz)
	var s_col := CollisionShape3D.new()
	var s_sphere := SphereShape3D.new()
	s_sphere.radius = 6.0
	s_col.shape = s_sphere
	statue_hint.add_child(s_col)
	statue_hint.body_entered.connect(_on_statue_hint)
	add_child(statue_hint)

	# —— 金草：5 丛围雕像一圈（半径 1.5，确保站中心就能吃到） ——
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(1.0, 0.85, 0.2)
	gold_mat.roughness = 0.6
	gold_mat.emission_enabled = true  # 廉价的自发光——"刺眼"的金
	gold_mat.emission = Color(1.0, 0.75, 0.1)
	gold_mat.emission_energy_multiplier = 0.6
	for i in 5:
		var ang := TAU * i / 5.0
		var gx := cx + cos(ang) * 1.5
		var gz := cz + sin(ang) * 1.5
		_place_gold_tuft(gx, gz, gold_mat)
	# 再随机撒 8 丛（世界各处——商店的进货来源。地图上显示为金点）
	for i in 8:
		var px := 0.0
		var pz := 0.0
		for _try in 12:
			px = _rng.randf_range(-88.0, 88.0)
			pz = _rng.randf_range(-88.0, 88.0)
			# 避开出生点（开场别白捡）和雕像圈（那边已有专属）
			if Vector2(px, pz).length() > 30.0 and Vector2(px - cx, pz - cz).length() > 10.0:
				break
		_place_gold_tuft(px, pz, gold_mat)


func _place_gold_tuft(gx: float, gz: float, gold_mat: StandardMaterial3D) -> void:
	var pos := Vector3(gx, height_at(gx, gz) + 0.22, gz)
	var mi := MeshInstance3D.new()
	var tuft := PrismMesh.new()
	tuft.size = Vector3(0.5, 0.6, 0.4)
	mi.mesh = tuft
	mi.material_override = gold_mat
	mi.position = pos
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	add_child(mi)
	_gold_positions.append(pos)
	_gold_alive.append(true)
	_gold_meshes.append(mi)


## 存活金草的世界坐标（地图标记用）
func gold_positions_alive() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in _gold_positions.size():
		if _gold_alive[i]:
			out.append(_gold_positions[i])
	return out


## 穿墙彩蛋文案
func _on_wall_hint(body: Node3D) -> void:
	if body is PlayerCow and hud != null and _wall_hint_cooldown <= 0.0:
		hud.show_message("你穿过了看起来很结实的墙。这当然是特性。", 3.0)
		_wall_hint_cooldown = 4.0


## 雕像彩蛋文案
func _on_statue_hint(body: Node3D) -> void:
	if body is PlayerCow and hud != null:
		hud.show_message("神秘的金牛雕像。它没有任何作用。", 3.0)


# ————————————————— 内部工具 —————————————————

## 池塘：真水——低模圆盘网格 + 顶点波动着色器（半透明、随时间起伏、贴着色流动）
func _build_pond() -> void:
	# —— 水面网格：同心环圆盘（硬三角 → 波浪起来是分面低模感） ——
	var surf := SurfaceTool.new()
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var segs := 24
	var p := PositionMeshBuilder.new()
	for i in rings:
		var r0 := WATER_MESH_R * float(i) / rings
		var r1 := WATER_MESH_R * float(i + 1) / rings
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			# 顶点围绕本地原点（节点自身定位到池心）
			var v00 := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var v01 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var v10 := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
			var v11 := Vector3(cos(a1) * r1, 0, sin(a1) * r1)
			if i == 0:
				p.quad(surf, v00, v01, v11, v10)  # 最内环退化成扇形（v00=v01=圆心）
			else:
				p.quad(surf, v00, v01, v11, v10)
	surf.generate_normals()
	var mesh := surf.commit()

	var pond := MeshInstance3D.new()
	pond.name = "Pond"
	pond.mesh = mesh
	pond.material_override = _water_material()
	pond.position = Vector3(POND_POSITION.x, water_level, POND_POSITION.y)
	add_child(pond)

	# —— 水体物理：浮力 + 环流（把漂浮物慢慢推着转圈——水在流） ——
	var body := WaterBody.new()
	body.name = "WaterBody"
	body.terrain = self
	add_child(body)


## 水面着色器：两层顶点波（相位错开 → 有"流过去"的感觉）+ 菲涅尔半透明
func _water_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

uniform vec3 shallow_color : source_color = vec3(0.30, 0.62, 0.88);
uniform vec3 deep_color : source_color = vec3(0.12, 0.32, 0.72);
uniform float wave_height = 0.07;

void vertex() {
	VERTEX.y += sin(TIME * 1.7 + VERTEX.x * 1.4) * wave_height
	          + cos(TIME * 2.3 + VERTEX.z * 1.8) * wave_height * 0.6;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(deep_color, shallow_color, fres);
	ROUGHNESS = 0.15;
	ALPHA = mix(0.62, 0.92, fres);
}
"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


## 辅助：向 SurfaceTool 写入一个由四个角点构成的双三角形面（顶点不共享）
## 角点顺序：a=左上(近) b=右上(近) c=右下(远) d=左下(远)，三角 a-c-b 与 a-d-c（法线朝上）
class PositionMeshBuilder:
	func quad(surf: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		surf.add_vertex(a)
		surf.add_vertex(c)
		surf.add_vertex(b)
		surf.add_vertex(a)
		surf.add_vertex(d)
		surf.add_vertex(c)
