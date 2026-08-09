class_name EquipmentDropRule
extends Resource

@export var equipment: EquipmentDefinition
@export_range(0.0, 1.0, 0.01) var chance := 1.0
@export_range(0.0, 100.0, 0.1) var common_weight := 100.0
@export_range(0.0, 100.0, 0.1) var uncommon_weight := 0.0
@export_range(0.0, 100.0, 0.1) var rare_weight := 0.0


func has_valid_quality_weights() -> bool:
	return common_weight + uncommon_weight + rare_weight > 0.0
