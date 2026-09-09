class_name WaterBody
extends Node
## 水体物理：浮力 + 缓慢环流。
## - dynamic_props（树/石/道具掉落物）掉进水里会浮起来，并被水流推着慢慢转圈
## - 玩家/CharacterBody3D 的游泳在各自脚本里处理（问 terrain.is_in_water）
## 荒诞守则：浮力只改本地——联机时别人看到的树可能沉在水底，这是特性。

const BUOY_FORCE := 14.0        # 每米浸没深度的浮力加速度（超过 1.2 米按 1.2 算）
const BUOY_DEPTH_CAP := 1.2
const WATER_DRAG := 1.6         # 水中线性阻尼（速度每秒衰减比例）
const CURRENT_STRENGTH := 1.1   # 环流切向推力（米/秒²）——"水在流"的物理版

var terrain: Grassland


func _physics_process(delta: float) -> void:
	if terrain == null:
		return
	for node in get_tree().get_nodes_in_group("dynamic_props"):
		var rb := node as RigidBody3D
		if rb == null or not rb.is_inside_tree():
			continue
		var pos := rb.global_position
		var d_xz := Vector2(pos.x - terrain.POND_POSITION.x, pos.z - terrain.POND_POSITION.y).length()
		# 吃水带：水面以上 0.35 米内也算"在水里"（半浸没的物体漂在带内）
		if d_xz > terrain.WATER_MESH_R or pos.y > terrain.water_level + 0.35:
			continue
		# 水是活的——泡在水里的东西不许睡（休眠刚体不吃力，水流就停了）
		if rb.sleeping:
			rb.sleeping = false
		# 浮力：越深浮越狠（有上限）——抵消重力再往上顶，把物体推回水面
		var submerged := clampf(terrain.water_level - pos.y, 0.0, BUOY_DEPTH_CAP)
		var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		rb.apply_central_force(Vector3.UP * rb.mass * (g + BUOY_FORCE * submerged))
		# 水阻：慢下来才浮得稳
		rb.linear_velocity = rb.linear_velocity.lerp(Vector3.ZERO, clampf(WATER_DRAG * delta, 0.0, 0.9))
		# 环流：绕池心逆时针切向推——漂浮物会被水流带着转圈
		var to_center := Vector3(terrain.POND_POSITION.x - pos.x, 0.0,
			terrain.POND_POSITION.y - pos.z)
		var tangent := Vector3(-to_center.z, 0.0, to_center.x)
		if tangent.length() > 0.01:
			rb.apply_central_force(tangent.normalized() * rb.mass * CURRENT_STRENGTH)
