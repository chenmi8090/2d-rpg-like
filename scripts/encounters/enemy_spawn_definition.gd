class_name EnemySpawnDefinition
extends Resource

@export var enemy_definition: EnemyDefinition
@export var local_position := Vector2.ZERO
@export var facing_direction := -1.0
@export_range(0.0, 300.0, 0.1) var respawn_delay := 4.0
