class_name WeaponType
extends RefCounted

const SWORD := &"sword"
const STAFF := &"staff"
const BOW := &"bow"
const DAGGER := &"dagger"

const ALL: Array[StringName] = [
	SWORD,
	STAFF,
	BOW,
	DAGGER,
]


static func is_valid(weapon_type: StringName) -> bool:
	return weapon_type in ALL
