class_name EquipmentSlot
extends RefCounted

const WEAPON := &"weapon"
const HEAD := &"head"
const BODY := &"body"
const LEGS := &"legs"
const GLOVES := &"gloves"
const SHOES := &"shoes"
const RING := &"ring"

const ALL: Array[StringName] = [
	WEAPON,
	HEAD,
	BODY,
	LEGS,
	GLOVES,
	SHOES,
	RING,
]


static func is_valid(slot: StringName) -> bool:
	return slot in ALL


static func display_name(slot: StringName) -> String:
	match slot:
		WEAPON:
			return "武器"
		HEAD:
			return "头部"
		BODY:
			return "上衣"
		LEGS:
			return "下装"
		GLOVES:
			return "手套"
		SHOES:
			return "鞋子"
		RING:
			return "戒指"
	return "未知"
