class_name Companion
extends CharacterBody3D
## 伙伴哨子召唤物：随机野生生物，一心一意跟着你。
## 它会卡墙（卡住就原地起跳自救），会顺手撞开挡路的小东西——
## 卡墙不是缺陷：正好帮你看清 Bug 位置。

const SPEED := 5.5
const FOLLOW_DIST := 4.5
const JUMP_SELF_RESCUE := 6.5

const NAME_POOL := ["走地鸡", "卡墙羊", "毛蛋二号", "野生哞", "迷路的鹅"]

var follow_target: Node3D
var cname := "走地鸡"

var model: CowModel
var _label: Label3D
var _bump: Area3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.4, 1.2)
	col.shape = shape
	col.position = Vector3(0, 0.7, 0)
	add_child(col)

	model = CowModel.new()
	# 野生生物配色：随机但偏"廉价鲜艳"
	model.body_color = Color.from_hsv(randf(), 0.45, 0.95)
	model.patch_color = Color.from_hsv(randf(), 0.6, 0.35)
	add_child(model)

	_label = Label3D.new()
	_label.text = cname
	_label.position = Vector3(0, 2.4, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.modulate = Color(1, 1, 1, 0.85)
	_label.no_depth_test = true
	add_child(_label)

	# 顺手撞开小东西（被动撞，不是主动攻击——它没那个脑子）
	_bump = Area3D.new()
	var bcol := CollisionShape3D.new()
	var bshape := SphereShape3D.new()
	bshape.radius = 1.5
	bcol.shape = bshape
	_bump.add_child(bcol)
	_bump.body_entered.connect(_on_bump)
	add_child(_bump)


func _physics_process(delta: float) -> void:
	if follow_target == null:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var to: Vector3 = follow_target.global_position - global_position
	to.y = 0.0
	if to.length() > FOLLOW_DIST:
		var dir := to.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		model.rotation.y = atan2(dir.x, dir.z)
		model.gait = 1.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		model.gait = 0.0

	# 卡墙自救：原地起跳（顺便展示 Bug 位置）
	if is_on_wall() and is_on_floor():
		velocity.y = JUMP_SELF_RESCUE

	move_and_slide()


## 撞到动态物体：施加一点不讲道理的力
func _on_bump(body: Node3D) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		var dir := (rb.global_position - global_position).normalized()
		rb.apply_central_impulse(dir * 6.0 + Vector3.UP * 3.0)
