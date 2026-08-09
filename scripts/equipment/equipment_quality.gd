class_name EquipmentQuality
extends RefCounted

const COMMON := &"common"
const UNCOMMON := &"uncommon"
const RARE := &"rare"
const ALL: Array[StringName] = [COMMON, UNCOMMON, RARE]


static func is_valid(quality: StringName) -> bool:
	return quality in ALL


static func display_name(quality: StringName) -> String:
	match quality:
		UNCOMMON:
			return "优秀"
		RARE:
			return "稀有"
	return "普通"


static func color(quality: StringName) -> Color:
	match quality:
		UNCOMMON:
			return Color("74c365")
		RARE:
			return Color("a882e8")
	return Color("b8c8d2")


static func sort_rank(quality: StringName) -> int:
	match quality:
		RARE:
			return 2
		UNCOMMON:
			return 1
	return 0
