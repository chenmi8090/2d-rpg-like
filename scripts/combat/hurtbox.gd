class_name Hurtbox
extends Area2D

signal damaged(amount: int, source: Node, hit_direction: float)

@export var enabled := true


func receive_hit(amount: int, source: Node, hit_direction: float) -> void:
	if not enabled:
		return

	damaged.emit(amount, source, hit_direction)
	var actor := owner
	if actor != null and actor.has_method("receive_hit"):
		actor.receive_hit(amount, source, hit_direction)
