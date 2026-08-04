class_name EquipmentTextFormatter
extends RefCounted


static func format_equipment_detail(definition: EquipmentDefinition) -> String:
	if definition == null:
		return ""
	var lines: Array[String] = [
		definition.display_name,
		"部位：%s" % EquipmentSlot.display_name(definition.slot),
	]
	if definition.is_weapon():
		lines.append("类型：%s" % weapon_type_display_name(definition.weapon_type))
	lines.append("")
	lines.append("属性加成")
	var aggregated := aggregate_modifiers(definition.modifiers)
	if aggregated.is_empty():
		lines.append("无属性加成")
		return "\n".join(lines)
	for stat_key in stat_display_order():
		if aggregated.has(stat_key):
			var totals := aggregated[stat_key] as Vector2
			lines.append(format_modifier_line(stat_key, totals.x, totals.y))
	return "\n".join(lines)


static func format_backpack_comparison(definition: EquipmentDefinition, preview: Dictionary) -> String:
	var lines: Array[String] = [format_equipment_detail(definition)]
	var current := preview.get("current") as EquipmentDefinition
	lines.append("")
	lines.append("当前装备：%s" % (current.display_name if current != null else "未装备"))
	if not bool(preview.get("valid", false)):
		lines.append("无法装备：当前职业无法使用该武器")
	lines.append("")
	lines.append("最终属性变化")
	var before: Dictionary = preview.get("before", {})
	var after: Dictionary = preview.get("after", {})
	var delta: Dictionary = preview.get("delta", {})
	var changes := 0
	for stat_key in stat_display_order():
		var change := float(delta.get(stat_key, 0.0))
		if is_zero_approx(change):
			continue
		changes += 1
		var before_value := float(before.get(stat_key, 0.0))
		var after_value := float(after.get(stat_key, 0.0))
		if stat_key == PlayerStats.CRITICAL_CHANCE or stat_key == PlayerStats.CRITICAL_DAMAGE:
			lines.append("%s：%s → %s（%s 个百分点）" % [stat_display_name(stat_key), format_percent(before_value), format_percent(after_value), format_signed_number(change * 100.0)])
		else:
			lines.append("%s：%s → %s（%s）" % [stat_display_name(stat_key), format_stat(before_value), format_stat(after_value), format_signed_number(change)])
	if changes == 0:
		lines.append("无属性变化")
	return "\n".join(lines)


static func aggregate_modifiers(modifiers: Array[StatModifier]) -> Dictionary:
	var totals: Dictionary = {}
	for modifier in modifiers:
		if modifier == null:
			continue
		var current := totals.get(modifier.stat_key, Vector2.ZERO) as Vector2
		current.x += modifier.flat_bonus
		current.y += modifier.percent_bonus
		totals[modifier.stat_key] = current
	return totals


static func format_modifier_line(stat_key: StringName, flat_bonus: float, percent_bonus: float) -> String:
	var parts: Array[String] = []
	if not is_zero_approx(flat_bonus):
		if stat_key == PlayerStats.CRITICAL_CHANCE or stat_key == PlayerStats.CRITICAL_DAMAGE:
			parts.append("%s 个百分点" % format_signed_number(flat_bonus * 100.0))
		else:
			parts.append(format_signed_number(flat_bonus))
	if not is_zero_approx(percent_bonus):
		parts.append("百分比 %s%%" % format_signed_number(percent_bonus * 100.0))
	return "%s：%s" % [stat_display_name(stat_key), "；".join(parts) if not parts.is_empty() else "0"]


static func stat_display_order() -> Array[StringName]:
	return [PlayerStats.STRENGTH, PlayerStats.SPIRIT, PlayerStats.VITALITY, PlayerStats.TECHNIQUE, PlayerStats.MAX_HEALTH, PlayerStats.PHYSICAL_ATTACK, PlayerStats.MAGIC_ATTACK, PlayerStats.PHYSICAL_DEFENSE, PlayerStats.CRITICAL_CHANCE, PlayerStats.CRITICAL_DAMAGE]


static func stat_display_name(stat_key: StringName) -> String:
	match stat_key:
		PlayerStats.STRENGTH: return "力量"
		PlayerStats.SPIRIT: return "精神"
		PlayerStats.VITALITY: return "体魄"
		PlayerStats.TECHNIQUE: return "技巧"
		PlayerStats.MAX_HEALTH: return "最大生命"
		PlayerStats.PHYSICAL_ATTACK: return "物理攻击"
		PlayerStats.MAGIC_ATTACK: return "魔法攻击"
		PlayerStats.PHYSICAL_DEFENSE: return "物理防御"
		PlayerStats.CRITICAL_CHANCE: return "暴击率"
		PlayerStats.CRITICAL_DAMAGE: return "暴击伤害"
	return "未知属性"


static func weapon_type_display_name(weapon_type: StringName) -> String:
	match weapon_type:
		WeaponType.SWORD: return "剑"
		WeaponType.STAFF: return "法杖"
		WeaponType.BOW: return "弓"
		WeaponType.DAGGER: return "匕首"
	return "未知"


static func format_signed_number(value: float) -> String:
	return "%s%s" % ["+" if value >= 0.0 else "-", format_stat(absf(value))]


static func format_stat(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value


static func format_percent(value: float) -> String:
	return "%s%%" % format_stat(value * 100.0)
