class_name Hurtbox
extends Area2D

signal damaged(amount: int, source: Node, hit_direction: float)

@export var enabled := true


func receive_hit(amount: int, source: Node, hit_direction: float) -> bool:
	if not enabled:
		return false

	var actor := owner
	if actor != null and actor.has_method("receive_hit"):
		var result: Variant = actor.receive_hit(amount, source, hit_direction)
		if result is bool and not result:
			return false
	damaged.emit(amount, source, hit_direction)
	return true
