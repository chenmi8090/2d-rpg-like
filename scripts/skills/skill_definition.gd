class_name SkillDefinition
extends Resource

enum Kind {
	ACTIVE,
	PASSIVE,
}

enum Delivery {
	MELEE,
	PROJECTILE,
}

enum DamageStat {
	PHYSICAL_ATTACK,
	MAGIC_ATTACK,
}

@export_category("Identity")
@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var kind := Kind.ACTIVE
@export var category: StringName = SkillCategory.NORMAL_OFFENSIVE
@export var profession_ids: Array[StringName] = []
@export_range(1, 200, 1) var required_level := 1
@export var required_weapon_types: Array[StringName] = []

@export_category("Active Rules")
@export var allow_ground := true
@export var allow_air := false
@export_range(0.0, 10.0, 0.01) var startup_time := 0.15
@export_range(0.0, 10.0, 0.01) var active_time := 0.10
@export_range(0.0, 10.0, 0.01) var recovery_time := 0.25
@export_range(0.0, 120.0, 0.05) var cooldown := 1.0
@export var delivery := Delivery.MELEE
@export var damage_stat := DamageStat.PHYSICAL_ATTACK
@export_range(0.0, 20.0, 0.01) var base_damage_multiplier := 0.5
@export_range(0.0, 20.0, 0.01) var damage_multiplier_per_rank := 0.1
@export var melee_hitbox_size := Vector2(80.0, 56.0)
@export var melee_hitbox_offset := Vector2(44.0, -8.0)
@export var projectile_spawn_offset := Vector2(30.0, -16.0)
@export_range(1.0, 3000.0, 1.0) var projectile_speed := 600.0
@export_range(1.0, 5000.0, 1.0) var projectile_maximum_distance := 700.0
@export_range(0.05, 10.0, 0.05) var projectile_lifetime := 1.5
@export var projectile_size := Vector2(26.0, 14.0)
@export var projectile_color := Color.WHITE
@export_range(0.0, 1.0, 0.01) var hit_feedback_time := 0.08
@export_range(0.0, 3.0, 0.05) var hit_feedback_intensity := 0.8
@export var force_knockback := false
@export_range(0.0, 1000.0, 1.0) var minimum_knockback_speed := 0.0

@export_category("Passive Effect")
@export var passive_stat_key: StringName
@export var passive_flat_bonus_per_rank := 0.0
@export var passive_percent_bonus_per_rank := 0.0


func is_active() -> bool:
	return kind == Kind.ACTIVE


func is_passive() -> bool:
	return kind == Kind.PASSIVE


func get_maximum_rank() -> int:
	return SkillCategory.maximum_rank(category)


func is_available_to_profession(profession_id: StringName) -> bool:
	return profession_id in profession_ids


func damage_multiplier_at_rank(rank: int) -> float:
	var valid_rank := clampi(rank, 0, get_maximum_rank())
	if valid_rank <= 0:
		return 0.0
	return base_damage_multiplier + damage_multiplier_per_rank * float(valid_rank - 1)


func passive_modifier_at_rank(rank: int) -> StatModifier:
	if not is_passive() or rank <= 0 or passive_stat_key == &"":
		return null
	var valid_rank := clampi(rank, 0, get_maximum_rank())
	var modifier := StatModifier.new()
	modifier.stat_key = passive_stat_key
	modifier.flat_bonus = passive_flat_bonus_per_rank * valid_rank
	modifier.percent_bonus = passive_percent_bonus_per_rank * valid_rank
	return modifier


func effect_text_at_rank(rank: int) -> String:
	var valid_rank := clampi(rank, 1, maxi(get_maximum_rank(), 1))
	if is_passive():
		var flat_bonus := passive_flat_bonus_per_rank * valid_rank
		var percent_bonus := passive_percent_bonus_per_rank * valid_rank * 100.0
		if not is_zero_approx(percent_bonus):
			return "%s +%.1f%%" % [String(passive_stat_key), percent_bonus]
		return "%s +%.1f" % [String(passive_stat_key), flat_bonus]
	return "伤害倍率 %.2f" % damage_multiplier_at_rank(valid_rank)


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or not SkillCategory.is_valid(category):
		return false
	if profession_ids.is_empty() or required_level < 1 or get_maximum_rank() <= 0:
		return false
	for profession_id in profession_ids:
		if profession_id == &"":
			return false
	if is_passive():
		return (
			category == SkillCategory.BASIC_STAT_PASSIVE
			and _is_supported_passive_stat(passive_stat_key)
			and (
				not is_zero_approx(passive_flat_bonus_per_rank)
				or not is_zero_approx(passive_percent_bonus_per_rank)
			)
		)
	if kind != Kind.ACTIVE or category == SkillCategory.BASIC_STAT_PASSIVE:
		return false
	if not allow_ground and not allow_air:
		return false
	if delivery < Delivery.MELEE or delivery > Delivery.PROJECTILE:
		return false
	if damage_stat < DamageStat.PHYSICAL_ATTACK or damage_stat > DamageStat.MAGIC_ATTACK:
		return false
	if startup_time < 0.0 or active_time <= 0.0 or recovery_time < 0.0 or cooldown < 0.0:
		return false
	if base_damage_multiplier < 0.0 or damage_multiplier_per_rank < 0.0:
		return false
	if force_knockback and minimum_knockback_speed <= 0.0:
		return false
	if delivery == Delivery.MELEE:
		return melee_hitbox_size.x > 0.0 and melee_hitbox_size.y > 0.0
	return (
		projectile_speed > 0.0
		and projectile_maximum_distance > 0.0
		and projectile_lifetime > 0.0
		and projectile_size.x > 0.0
		and projectile_size.y > 0.0
	)


func _is_supported_passive_stat(stat_key: StringName) -> bool:
	return stat_key in [
		PlayerStats.STRENGTH,
		PlayerStats.SPIRIT,
		PlayerStats.VITALITY,
		PlayerStats.TECHNIQUE,
		PlayerStats.MAX_HEALTH,
		PlayerStats.PHYSICAL_ATTACK,
		PlayerStats.MAGIC_ATTACK,
		PlayerStats.PHYSICAL_DEFENSE,
		PlayerStats.CRITICAL_CHANCE,
		PlayerStats.CRITICAL_DAMAGE,
	]
