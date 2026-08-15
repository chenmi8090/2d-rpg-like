class_name EncounterManager
extends Node2D

signal alive_count_changed(alive: int, capacity: int)
signal enemy_respawned(enemy: GroundedEnemyController, group_index: int, spawn_index: int)
signal experience_reward_accepted(amount: int, enemy: GroundedEnemyController, credited_player: Player, group_index: int, spawn_index: int)

@export var encounter_definition: EncounterDefinition
@export var enemy_scene: PackedScene
@export var target_path: NodePath
@export var enemies_container_path: NodePath
@export_range(0.0, 300.0, 0.1) var respawn_interval := 8.0

var _target: Node2D
var _enemies_container: Node2D
var _owned_enemies: Array[GroundedEnemyController] = []
var _enemy_to_group: Dictionary = {}
var _enemy_to_spawn_index: Dictionary = {}
var _alive_enemies: Dictionary = {}
var _respawn_remaining: Dictionary = {}
var _group_alive_counts: Array[int] = []
var _encounter_generation := 0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node2D
	_enemies_container = get_node_or_null(enemies_container_path) as Node2D
	if _enemies_container == null:
		_enemies_container = self
	if encounter_definition != null:
		_build_encounter.call_deferred()


func _process(delta: float) -> void:
	if _respawn_remaining.is_empty():
		return
	for enemy in _respawn_remaining.keys():
		if enemy == null or not is_instance_valid(enemy) or not _owns_enemy(enemy):
			_respawn_remaining.erase(enemy)
			continue
		var remaining := maxf(float(_respawn_remaining[enemy]) - delta, 0.0)
		if remaining == 0.0:
			_respawn_remaining.erase(enemy)
			_respawn_enemy.call_deferred(enemy, _encounter_generation)
		else:
			_respawn_remaining[enemy] = remaining


func load_encounter(definition: EncounterDefinition, clear_existing := true) -> void:
	if clear_existing:
		clear_encounter()
	encounter_definition = definition
	_build_encounter()


func clear_encounter() -> void:
	_encounter_generation += 1
	var old_enemies := _owned_enemies.duplicate()
	_owned_enemies.clear()
	_enemy_to_group.clear()
	_enemy_to_spawn_index.clear()
	_alive_enemies.clear()
	_respawn_remaining.clear()
	_group_alive_counts.clear()

	for enemy in old_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.defeated.is_connected(_on_enemy_defeated):
			enemy.defeated.disconnect(_on_enemy_defeated)
		enemy.set_physics_process(false)
		enemy.set_process(false)
		enemy.visible = false
		if enemy.get_parent() != null:
			enemy.get_parent().remove_child(enemy)
		enemy.queue_free()
	alive_count_changed.emit(0, 0)


func _build_encounter() -> void:
	if encounter_definition == null:
		alive_count_changed.emit(0, 0)
		return
	if enemy_scene == null:
		push_warning("EncounterManager requires an enemy scene.")
		alive_count_changed.emit(0, 0)
		return

	_group_alive_counts.resize(encounter_definition.groups.size())
	_group_alive_counts.fill(0)
	for group_index in encounter_definition.groups.size():
		var group := encounter_definition.groups[group_index]
		if group == null:
			continue
		for spawn_index in group.spawns.size():
			_spawn_enemy(group.spawns[spawn_index], group_index, spawn_index)
	alive_count_changed.emit(get_alive_count(), _owned_enemies.size())


func _spawn_enemy(spawn: EnemySpawnDefinition, group_index: int, spawn_index: int) -> void:
	if spawn == null or spawn.enemy_definition == null:
		return
	var enemy := enemy_scene.instantiate() as GroundedEnemyController
	if enemy == null:
		push_warning("Encounter enemy scene must instantiate GroundedEnemyController.")
		return

	enemy.name = "Enemy_%d_%d" % [group_index, spawn_index]
	enemy.definition = spawn.enemy_definition
	enemy.start_facing_direction = spawn.facing_direction
	enemy.position = spawn.local_position
	enemy.target_path = NodePath()
	enemy.set_target(_target)
	enemy.defeated.connect(_on_enemy_defeated)

	_owned_enemies.append(enemy)
	_enemy_to_group[enemy] = group_index
	_enemy_to_spawn_index[enemy] = spawn_index
	_alive_enemies[enemy] = true
	_group_alive_counts[group_index] += 1
	_enemies_container.add_child(enemy)


func _on_enemy_defeated(enemy: GroundedEnemyController, source: Node) -> void:
	if not _owns_enemy(enemy) or not _alive_enemies.has(enemy) or _respawn_remaining.has(enemy):
		return
	_alive_enemies.erase(enemy)

	var group_index := int(_enemy_to_group.get(enemy, -1))
	var spawn_index := int(_enemy_to_spawn_index.get(enemy, -1))
	if group_index >= 0 and group_index < _group_alive_counts.size():
		_group_alive_counts[group_index] = maxi(_group_alive_counts[group_index] - 1, 0)

	var credited_player := _resolve_credit_player(source)
	var reward := enemy.definition.experience_reward if enemy.definition != null else 0
	if credited_player != null and reward > 0:
		experience_reward_accepted.emit(reward, enemy, credited_player, group_index, spawn_index)

	enemy.visible = false
	_respawn_remaining[enemy] = maxf(respawn_interval, 0.0)
	alive_count_changed.emit(get_alive_count(), _owned_enemies.size())


func _resolve_credit_player(source: Node) -> Player:
	if source == null or not is_instance_valid(source):
		return null
	if source is Player:
		return source as Player
	if source.has_method("get_credit_owner"):
		var credit_owner: Node = source.get_credit_owner()
		if credit_owner is Player:
			return credit_owner as Player
	return null


func _respawn_enemy(enemy: GroundedEnemyController, generation: int) -> void:
	if (
		generation != _encounter_generation
		or enemy == null
		or not is_instance_valid(enemy)
		or not _owns_enemy(enemy)
		or _alive_enemies.has(enemy)
	):
		return
	var group_index := int(_enemy_to_group.get(enemy, -1))
	if group_index < 0 or group_index >= _group_alive_counts.size():
		return

	enemy.visible = true
	enemy.reset()
	_alive_enemies[enemy] = true
	_group_alive_counts[group_index] += 1
	alive_count_changed.emit(get_alive_count(), _owned_enemies.size())
	enemy_respawned.emit(enemy, group_index, int(_enemy_to_spawn_index.get(enemy, -1)))


func reset_encounter() -> void:
	_respawn_remaining.clear()
	_alive_enemies.clear()
	_group_alive_counts.resize(encounter_definition.groups.size() if encounter_definition != null else 0)
	_group_alive_counts.fill(0)

	for enemy in _owned_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var group_index := int(_enemy_to_group.get(enemy, -1))
		if group_index >= 0 and group_index < _group_alive_counts.size():
			_group_alive_counts[group_index] += 1
		enemy.visible = true
		_alive_enemies[enemy] = true
		enemy.reset()
	alive_count_changed.emit(get_alive_count(), _owned_enemies.size())


func owns_enemy(enemy: GroundedEnemyController) -> bool:
	return _owns_enemy(enemy)


func _owns_enemy(enemy: GroundedEnemyController) -> bool:
	return enemy != null and is_instance_valid(enemy) and _enemy_to_group.has(enemy)


func get_owned_enemies() -> Array[GroundedEnemyController]:
	return _owned_enemies.duplicate()


func get_alive_count() -> int:
	return _alive_enemies.size()


func get_capacity() -> int:
	return _owned_enemies.size()


func get_group_alive_count(group_index: int) -> int:
	if group_index < 0 or group_index >= _group_alive_counts.size():
		return 0
	return _group_alive_counts[group_index]


func get_respawn_remaining(enemy: GroundedEnemyController) -> float:
	return float(_respawn_remaining.get(enemy, 0.0))
