class_name EquipmentPickup
extends CharacterBody2D

@export var gravity := 1650.0
@export var collect_radius := 24.0
@export var attract_acceleration := 2400.0
@export var max_attract_speed := 620.0
@export var floor_friction := 900.0
@export var pop_delay := 0.18
@export_range(1.0, 300.0, 1.0) var lifetime := 30.0
@export_range(0.0, 10.0, 0.1) var fade_duration := 3.0

var instance: EquipmentInstance
var _active := true
var _age := 0.0
var _player: Player


func initialize(pickup_instance: EquipmentInstance, launch_velocity: Vector2) -> void:
	instance = pickup_instance
	velocity = launch_velocity
	queue_redraw()


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= lifetime:
		deactivate()
		queue_free()
		return
	if fade_duration > 0.0 and _age > lifetime - fade_duration:
		modulate.a = clampf((lifetime - _age) / fade_duration, 0.0, 1.0)
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
	if not _active or instance == null or _player == null:
		return
	if not _player.collect_equipment(instance):
		return
	deactivate()
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
	var quality := instance.quality if instance != null else EquipmentQuality.COMMON
	var color := EquipmentQuality.color(quality)
	var points := PackedVector2Array([
		Vector2(0.0, -11.0),
		Vector2(11.0, 0.0),
		Vector2(0.0, 11.0),
		Vector2(-11.0, 0.0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), color.darkened(0.5), 2.0)
	var marks := EquipmentQuality.sort_rank(quality) + 1
	for index in marks:
		draw_circle(Vector2((float(index) - float(marks - 1) * 0.5) * 5.0, 0.0), 1.8, Color.WHITE)
