class_name CrushCow
extends Combatant
## 心上牛：恋爱剧情的另一半。
## 行为：在老家附近优雅地漫步 / 约会时跟着玩家走。
## 会被狼咬死（Romance 会安排下一头来）、被玩家撞会掉好感。
## 头顶一颗漂浮的粉宝石——草原爱情信物（其实是渲染廉价）。

signal crush_hurt(by: Node3D)      # 被撞（没死）——Romance 判定是不是玩家干的
signal crush_died(by: Node3D)      # 死亡——Romance 安排下一头

const WANDER_SPEED := 2.2
const FOLLOW_SPEED := 5.5
const FOLLOW_DIST := 2.6
const WANDER_RADIUS := 8.0
const WANDER_PAUSE := 2.5

var crush_name := "哞莉"
var follow_target: Node3D = null   # 非 null = 跟着它走（约会/情侣）
var home := Vector3.ZERO

var model: CowModel
var _gem: MeshInstance3D
var _wander_to := Vector3.ZERO
var _pause_left := 0.0


func _ready() -> void:
	add_to_group("npcs")  # 狼群索敌池——约会对象被狼叼走是本作特色剧情

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.6, 2.0)
	col.shape = shape
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	model = CowModel.new()
	# 恋爱配色：奶油粉身 + 白斑——草原上最显眼的一头
	model.body_color = Color(0.98, 0.78, 0.82)
	model.patch_color = Color(0.99, 0.96, 0.94)
	add_child(model)

	# 头顶漂浮粉宝石（上下浮动——心跳的感觉，也是廉价动画）
	_gem = MeshInstance3D.new()
	var gem := PrismMesh.new()
	gem.size = Vector3(0.3, 0.4, 0.3)
	_gem.mesh = gem
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.65)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.55)
	mat.emission_energy_multiplier = 1.2
	_gem.material_override = mat
	_gem.position = Vector3(0, 2.9, 0)
	add_child(_gem)
	var tw := create_tween().set_loops()
	tw.tween_property(_gem, "position:y", 3.15, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_gem, "position:y", 2.9, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	combat_defeated.connect(func(by, _dir): crush_died.emit(by))
	_refresh_pips()


func on_knocked() -> void:
	# 被撞但没死：上报给 Romance（玩家撞约会对象 → 好感清零）
	crush_hurt.emit(null)


func _physics_process(delta: float) -> void:
	if is_dead_combat():
		return
	if knock_left > 0.0:
		_knock_step(delta)
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if follow_target != null and is_instance_valid(follow_target):
		_step_follow(delta)
	else:
		_step_wander(delta)
	move_and_slide()


## 跟随（约会/情侣）：距离拉太开就瞬移过来——"它抄了近道，这一定是特性"
func _step_follow(delta: float) -> void:
	var to_t := follow_target.global_position - global_position
	to_t.y = 0.0
	if to_t.length() > 45.0:
		var near := follow_target.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		global_position = Vector3(near.x, near.y + 1.5, near.z)
		velocity = Vector3.ZERO
		return
	if to_t.length() > FOLLOW_DIST:
		var dir := to_t.normalized()
		velocity.x = dir.x * FOLLOW_SPEED
		velocity.z = dir.z * FOLLOW_SPEED
		model.rotation.y = atan2(dir.x, dir.z)
		model.gait = 0.8
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0
		# 到位后深情对视
		var face := follow_target.global_position - global_position
		model.rotation.y = atan2(face.x, face.z)


## 漫步：在家附近挑个点慢慢走，走到了歇一会
func _step_wander(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0
		return
	var to_t := _wander_to - global_position
	to_t.y = 0.0
	if to_t.length() < 0.8:
		_pause_left = WANDER_PAUSE + randf() * 2.0
		_pick_wander_point()
		return
	var dir := to_t.normalized()
	velocity.x = dir.x * WANDER_SPEED
	velocity.z = dir.z * WANDER_SPEED
	model.rotation.y = atan2(dir.x, dir.z)
	model.gait = 0.4


func _pick_wander_point() -> void:
	var ang := randf() * TAU
	var r := randf() * WANDER_RADIUS
	_wander_to = home + Vector3(cos(ang) * r, 0, sin(ang) * r)
