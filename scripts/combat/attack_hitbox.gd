class_name AttackHitbox
extends Area2D

signal hit_confirmed(hurtbox: Hurtbox, damage: int, source: Node, hit_direction: float)

var _active := false
var _damage := 1
var _source: Node
var _hit_direction := 1.0
var _hit_hurtboxes: Array[Hurtbox] = []

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	_collision.disabled = true


func activate(damage: int, source: Node, hit_direction: float) -> void:
	_damage = damage
	_source = source
	_hit_direction = signf(hit_direction)
	_hit_hurtboxes.clear()
	_active = true
	_collision.set_deferred("disabled", false)


func deactivate() -> void:
	_active = false
	_collision.set_deferred("disabled", true)


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	for area in get_overlapping_areas():
		_try_hit(area)


func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)


func _try_hit(area: Area2D) -> void:
	if not _active or not area is Hurtbox:
		return

	var hurtbox := area as Hurtbox
	if hurtbox in _hit_hurtboxes:
		return

	_hit_hurtboxes.append(hurtbox)
	if hurtbox.receive_hit(_damage, _source, _hit_direction):
		hit_confirmed.emit(hurtbox, _damage, _source, _hit_direction)
