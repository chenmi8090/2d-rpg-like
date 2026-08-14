class_name SkillCategory
extends RefCounted

const NORMAL_OFFENSIVE := &"normal_offensive"
const OFFENSIVE_ULTIMATE := &"offensive_ultimate"
const BASIC_STAT_PASSIVE := &"basic_stat_passive"

const ALL: Array[StringName] = [
	NORMAL_OFFENSIVE,
	OFFENSIVE_ULTIMATE,
	BASIC_STAT_PASSIVE,
]


static func is_valid(category: StringName) -> bool:
	return category in ALL


static func maximum_rank(category: StringName) -> int:
	match category:
		NORMAL_OFFENSIVE:
			return 5
		OFFENSIVE_ULTIMATE:
			return 3
		BASIC_STAT_PASSIVE:
			return 10
	return 0


static func display_name(category: StringName) -> String:
	match category:
		NORMAL_OFFENSIVE:
			return "普通攻击技能"
		OFFENSIVE_ULTIMATE:
			return "攻击类大招"
		BASIC_STAT_PASSIVE:
			return "基础属性被动"
	return "未知技能类别"
