class_name PlayerProgressionDefinition
extends Resource

@export_category("Progression")
@export_range(1, 200, 1) var maximum_level := 100
@export_range(1, 200, 1) var starting_level := 1
@export_range(0, 1000000, 1) var starting_experience := 0
@export_range(0, 999, 1) var starting_skill_points := 0
@export_range(0, 99, 1) var skill_points_per_level := 1

@export_category("Starting Attributes")
@export_range(0, 999, 1) var starting_strength := 3
@export_range(0, 999, 1) var starting_spirit := 3
@export_range(0, 999, 1) var starting_vitality := 3
@export_range(0, 999, 1) var starting_technique := 3

@export_category("Growth Per Level")
@export_range(0, 99, 1) var strength_per_level := 1
@export_range(0, 99, 1) var spirit_per_level := 1
@export_range(0, 99, 1) var vitality_per_level := 1
@export_range(0, 99, 1) var technique_per_level := 1

@export_category("Attack Multipliers")
@export_range(0.01, 10.0, 0.01) var light_attack_multiplier := 0.5
@export_range(0.01, 10.0, 0.01) var heavy_attack_multiplier := 1.0


func experience_to_next_level(level: int) -> int:
	if level >= maximum_level:
		return 0
	var level_offset := maxi(level - 1, 0)
	return 20 + 10 * level_offset + 5 * level_offset * level_offset
