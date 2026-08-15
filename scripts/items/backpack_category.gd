class_name BackpackCategory
extends RefCounted

const EQUIPMENT := &"equipment"
const CONSUMABLE := &"consumable"
const OTHER := &"other"
const QUEST := &"quest"

const ALL: Array[StringName] = [EQUIPMENT, CONSUMABLE, OTHER, QUEST]
const STACKABLE: Array[StringName] = [CONSUMABLE, OTHER, QUEST]


static func is_valid(category: StringName) -> bool:
	return category in ALL


static func is_stackable(category: StringName) -> bool:
	return category in STACKABLE


static func display_name(category: StringName) -> String:
	match category:
		EQUIPMENT:
			return "装备"
		CONSUMABLE:
			return "消耗"
		OTHER:
			return "其他"
		QUEST:
			return "任务"
	return "未知"
