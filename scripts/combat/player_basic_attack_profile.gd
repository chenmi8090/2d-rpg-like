class_name PlayerBasicAttackProfile
extends Resource

enum Delivery {
	MELEE,
	PROJECTILE,
}

enum DamageStat {
	PHYSICAL_ATTACK,
	MAGIC_ATTACK,
}

@export var id: StringName
@export var display_name := ""
@export var weapon_type: StringName
@export_enum("轻攻击:0", "重攻击:1") var attack_type := 0
@export var delivery := Delivery.MELEE
@export var damage_stat := DamageStat.PHYSICAL_ATTACK
@export_range(0.01, 10.0, 0.01) var damage_multiplier := 1.0
@export_category("Timing")
@export_range(0.01, 5.0, 0.01) var duration := 0.38
@export_range(0.0, 5.0, 0.01) var hit_start := 0.10
@export_range(0.0, 5.0, 0.01) var hit_end := 0.19
@export_range(0.01, 5.0, 0.01) var repeat_interval := 0.55
@export_range(0.0, 1.0, 0.01) var walk_speed_multiplier := 0.45
@export_category("Melee")
@export var melee_hitbox_offset := Vector2(40.0, -18.0)
@export var melee_hitbox_size := Vector2(46.0, 34.0)
@export_category("Projectile")
@export var projectile_spawn_offset := Vector2(34.0, -28.0)
@export var projectile_size := Vector2(26.0, 14.0)
@export_range(1.0, 2000.0, 1.0) var projectile_speed := 520.0
@export_range(0.01, 5.0, 0.01) var projectile_lifetime := 0.9
@export_range(1.0, 2000.0, 1.0) var projectile_max_distance := 500.0
@export_category("Visual")
@export var visual_key: StringName
@export var color := Color.WHITE
@export_category("Feedback")
@export_range(0.0, 1.0, 0.01) var hit_feedback_time := 0.10
@export_range(0.0, 2.0, 0.01) var hit_feedback_intensity := 1.0


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or damage_multiplier <= 0.0:
		return false
	if attack_type < 0 or attack_type > 1 or hit_end <= hit_start or duration < hit_end or repeat_interval <= 0.0:
		return false
	if delivery == Delivery.MELEE:
		return melee_hitbox_size.x > 0.0 and melee_hitbox_size.y > 0.0
	return projectile_size.x > 0.0 and projectile_size.y > 0.0 and projectile_speed > 0.0 and projectile_lifetime > 0.0 and projectile_max_distance > 0.0
