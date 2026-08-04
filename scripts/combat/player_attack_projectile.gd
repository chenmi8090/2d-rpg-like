class_name PlayerAttackProjectile
extends Area2D

var _damage := 1
var _source: Node
var _direction := 1.0
var _speed := 1.0
var _lifetime := 0.1
var _max_distance := 1.0
var _travelled := 0.0
var _active := false
var _color := Color.WHITE
var _visual_size := Vector2(26.0, 14.0)
var _hit_hurtboxes: Array[Hurtbox] = []

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("player_attack_projectile")
	area_entered.connect(_on_area_entered)


func initialize(profile: PlayerBasicAttackProfile, damage: int, source: Node, direction: float) -> void:
	_damage = maxi(damage, 1)
	_source = source
	_direction = signf(direction) if direction != 0.0 else 1.0
	_speed = maxf(profile.projectile_speed, 1.0)
	_lifetime = maxf(profile.projectile_lifetime, 0.01)
	_max_distance = maxf(profile.projectile_max_distance, 1.0)
	_visual_size = profile.projectile_size
	_color = profile.color
	if _collision.shape is RectangleShape2D:
		_collision.shape = _collision.shape.duplicate()
		(_collision.shape as RectangleShape2D).size = Vector2(maxf(_visual_size.x, 1.0), maxf(_visual_size.y, 1.0))
	_active = true
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	var step := _speed * delta
	position.x += _direction * step
	_travelled += step
	_lifetime = maxf(_lifetime - delta, 0.0)
	for area in get_overlapping_areas():
		_try_hit(area)
	if _lifetime == 0.0 or _travelled >= _max_distance:
		deactivate()


func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)


func _try_hit(area: Area2D) -> void:
	if not _active or not area is Hurtbox:
		return
	var hurtbox := area as Hurtbox
	if hurtbox in _hit_hurtboxes:
		return
	_hit_hurtboxes.append(hurtbox)
	hurtbox.receive_hit(_damage, _source, _direction)
	deactivate()


func get_source() -> Node:
	return _source


func get_credit_owner() -> Node:
	if _source is Player:
		return _source
	if _source != null and is_instance_valid(_source) and _source.has_method("get_credit_owner"):
		return _source.get_credit_owner() as Node
	return null


func deactivate() -> void:
	if not _active:
		return
	_active = false
	monitoring = false
	visible = false
	set_physics_process(false)
	queue_free()


func _draw() -> void:
	var half := _visual_size * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half.x, 0.0),
		Vector2(0.0, -half.y),
		Vector2(half.x, 0.0),
		Vector2(0.0, half.y),
	]), _color)
	draw_circle(Vector2.ZERO, minf(half.x, half.y) * 0.35, Color(1.0, 1.0, 1.0, 0.8))
