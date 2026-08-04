class_name EquipmentPickup
extends CharacterBody2D

@export var gravity := 1650.0
@export var collect_radius := 24.0
@export var attract_acceleration := 2400.0
@export var max_attract_speed := 620.0
@export var floor_friction := 900.0
@export var pop_delay := 0.18

var definition: EquipmentDefinition
var amount := 1
var _active := true
var _age := 0.0
var _player: Player


func initialize(pickup_definition: EquipmentDefinition, pickup_amount: int, launch_velocity: Vector2) -> void:
	definition = pickup_definition
	amount = maxi(pickup_amount, 1)
	velocity = launch_velocity
	queue_redraw()


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _age >= pop_delay and _player != null and _player.can_collect_pickups():
		var to_player := _player.global_position + Vector2(0.0, -24.0) - global_position
		var distance := to_player.length()
		if distance <= collect_radius:
			_collect()
			return
		if distance > 0.0:
			velocity = velocity.move_toward(to_player.normalized() * max_attract_speed, attract_acceleration * delta)
			move_and_slide()
			return
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, floor_friction * delta)
	move_and_slide()


func _collect() -> void:
	if not _active or definition == null or _player == null:
		return
	deactivate()
	_player.collect_equipment(definition, amount)
	queue_free()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	velocity = Vector2.ZERO
	collision_mask = 0
	visible = false
	set_physics_process(false)


func _draw() -> void:
	var color := Color("6eb8d6")
	draw_rect(Rect2(-9, -9, 18, 18), color, true)
	draw_rect(Rect2(-9, -9, 18, 18), color.darkened(0.45), false, 2.0)
	draw_circle(Vector2(-3, -3), 2.5, Color(1.0, 1.0, 1.0, 0.85))
