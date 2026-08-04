class_name EnemyMeleeAttackDefinition
extends Resource

@export_range(1, 1000, 1) var damage := 2
@export var hitbox_size := Vector2(48.0, 42.0)
@export var hitbox_offset := Vector2(38.0, -28.0)
@export_range(0.0, 5.0, 0.01) var windup_time := 0.35
@export_range(0.01, 5.0, 0.01) var active_time := 0.12
@export_range(0.0, 5.0, 0.01) var recovery_time := 0.28
@export_range(0.0, 10.0, 0.01) var cooldown_time := 1.2
@export_range(1.0, 500.0, 1.0) var engage_range := 58.0
