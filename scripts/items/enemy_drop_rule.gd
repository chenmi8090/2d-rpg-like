class_name EnemyDropRule
extends Resource

@export var collectible: CollectibleDefinition
@export_range(0.0, 1.0, 0.01) var chance := 1.0
@export_range(0, 99, 1) var min_amount := 1
@export_range(0, 99, 1) var max_amount := 1
