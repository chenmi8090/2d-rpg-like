class_name PlayerSkillProgress
extends RefCounted

var unspent_points := 0
var _ranks: Dictionary = {}


func initialize(starting_points := 0) -> void:
	unspent_points = maxi(starting_points, 0)
	_ranks.clear()


func load_snapshot(snapshot: Dictionary, profession_id: StringName) -> void:
	unspent_points = maxi(int(snapshot.get("unspent_points", 0)), 0)
	_ranks.clear()
	var raw_ranks := snapshot.get("ranks", {}) as Dictionary
	for raw_skill_id in raw_ranks:
		var skill_id := StringName(String(raw_skill_id))
		var definition := DefinitionRegistry.get_skill(skill_id)
		if definition == null or not definition.is_available_to_profession(profession_id):
			continue
		var rank := clampi(int(raw_ranks[raw_skill_id]), 0, definition.get_maximum_rank())
		if rank > 0:
			_ranks[skill_id] = rank
	_refund_invalid_prerequisite_ranks(profession_id)


func to_snapshot() -> Dictionary:
	var ranks: Dictionary = {}
	for skill_id in _ranks:
		var rank := maxi(int(_ranks[skill_id]), 0)
		if rank > 0:
			ranks[String(skill_id)] = rank
	return {
		"unspent_points": unspent_points,
		"ranks": ranks,
	}


func get_rank(skill_id: StringName) -> int:
	return maxi(int(_ranks.get(skill_id, 0)), 0)


func get_ranks_copy() -> Dictionary:
	return _ranks.duplicate()


func add_points(amount: int) -> bool:
	if amount <= 0:
		return false
	unspent_points += amount
	return true


func get_rank_up_status(
	skill_id: StringName,
	profession_id: StringName,
	character_level: int
) -> Dictionary:
	var definition := DefinitionRegistry.get_skill(skill_id)
	if definition == null:
		return _failure("技能定义不存在")
	if not definition.is_available_to_profession(profession_id):
		return _failure("当前职业无法学习该技能")
	if character_level < definition.required_level:
		return _failure("角色等级不足，需要达到 %d 级" % definition.required_level)
	var rank := get_rank(skill_id)
	if rank >= definition.get_maximum_rank():
		return _failure("技能已达到最高等级")
	var prerequisite_status := _get_prerequisite_status(definition)
	if not bool(prerequisite_status.get("ok", false)):
		return prerequisite_status
	if unspent_points <= 0:
		return _failure("技能点不足")
	return {
		"ok": true,
		"message": "可以加点",
		"current_rank": rank,
		"maximum_rank": definition.get_maximum_rank(),
	}


func increase_rank(
	skill_id: StringName,
	profession_id: StringName,
	character_level: int
) -> Dictionary:
	var status := get_rank_up_status(skill_id, profession_id, character_level)
	if not bool(status.get("ok", false)):
		return status
	var next_rank := get_rank(skill_id) + 1
	_ranks[skill_id] = next_rank
	unspent_points -= 1
	return {
		"ok": true,
		"message": "技能提升成功",
		"skill_id": skill_id,
		"rank": next_rank,
		"unspent_points": unspent_points,
	}


func get_rank_down_status(skill_id: StringName, profession_id: StringName) -> Dictionary:
	var definition := DefinitionRegistry.get_skill(skill_id)
	if definition == null:
		return _failure("技能定义不存在")
	if not definition.is_available_to_profession(profession_id):
		return _failure("当前职业无法调整该技能")
	var rank := get_rank(skill_id)
	if rank <= 0:
		return _failure("技能尚未学习")
	var dependent := _find_blocking_dependent(skill_id, rank - 1, profession_id)
	if dependent != null:
		return _failure(
			"“%s”需要“%s”保持 %d 级，当前不能继续降低" % [
				dependent.display_name,
				definition.display_name,
				dependent.prerequisite_rank,
			]
		)
	return {
		"ok": true,
		"message": "可以减点",
		"current_rank": rank,
	}


func decrease_rank(skill_id: StringName, profession_id: StringName) -> Dictionary:
	var status := get_rank_down_status(skill_id, profession_id)
	if not bool(status.get("ok", false)):
		return status
	var next_rank := get_rank(skill_id) - 1
	if next_rank <= 0:
		_ranks.erase(skill_id)
	else:
		_ranks[skill_id] = next_rank
	unspent_points += 1
	return {
		"ok": true,
		"message": "技能降低成功，返还 1 点技能点",
		"skill_id": skill_id,
		"rank": next_rank,
		"unspent_points": unspent_points,
	}


func _get_prerequisite_status(definition: SkillDefinition) -> Dictionary:
	if not definition.has_prerequisite():
		return {"ok": true, "message": ""}
	var prerequisite := DefinitionRegistry.get_skill(definition.prerequisite_skill_id)
	if prerequisite == null:
		return _failure("技能前置配置无效")
	var current_rank := get_rank(prerequisite.id)
	if current_rank < definition.prerequisite_rank:
		return _failure(
			"需要“%s”达到 %d 级" % [
				prerequisite.display_name,
				definition.prerequisite_rank,
			]
		)
	return {"ok": true, "message": ""}


func _find_blocking_dependent(
	skill_id: StringName,
	resulting_rank: int,
	profession_id: StringName
) -> SkillDefinition:
	var profession := DefinitionRegistry.get_profession(profession_id)
	if profession == null:
		return null
	for dependent_id in profession.skill_ids:
		var dependent := DefinitionRegistry.get_skill(dependent_id)
		if (
			dependent != null
			and dependent.prerequisite_skill_id == skill_id
			and get_rank(dependent.id) > 0
			and resulting_rank < dependent.prerequisite_rank
		):
			return dependent
	return null


func _refund_invalid_prerequisite_ranks(profession_id: StringName) -> void:
	var profession := DefinitionRegistry.get_profession(profession_id)
	if profession == null:
		return
	var changed := true
	while changed:
		changed = false
		for skill_id in profession.skill_ids:
			var rank := get_rank(skill_id)
			if rank <= 0:
				continue
			var definition := DefinitionRegistry.get_skill(skill_id)
			if definition == null or not definition.has_prerequisite():
				continue
			if not bool(_get_prerequisite_status(definition).get("ok", false)):
				_ranks.erase(skill_id)
				unspent_points += rank
				changed = true


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
