class_name EncounterManager
extends Node2D

signal alive_count_changed(alive: int, capacity: int)
signal enemy_respawned(enemy: GroundedEnemyController, group_index: int, spawn_index: int)
signal experience_reward_accepted(amount: int, enemy: GroundedEnemyController, credited_player: Player, group_index: int, spawn_index: int)

@export var encounter_definition: EncounterDefinition
@export var enemy_scene: PackedScene
@export var target_path: NodePath
@export var enemies_container_path: NodePath

var _target: Node2D
var _enemies_container: Node2D
var _owned_enemies: Array[GroundedEnemyController] = []
var _enemy_to_group: Dictionary = {}
var _enemy_to_spawn_index: Dictionary = {}
var _enemy_to_spawn: Dictionary = {}
var _alive_enemies: Dictionary = {}
var _respawn_remaining: Dictionary = {}
var _group_alive_counts: Array[int] = []
var _built := false


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node2D
	_enemies_container = get_node_or_null(enemies_container_path) as Node2D
	if _enemies_container == null:
		_enemies_container = self
	_build_encounter.call_deferred()


func _process(delta: float) -> void:
	if _respawn_remaining.is_empty():
		return
	for enemy in _respawn_remaining.keys():
		if enemy == null or not is_instance_valid(enemy):
			_respawn_remaining.erase(enemy)
			continue
		var remaining := maxf(float(_respawn_remaining[enemy]) - delta, 0.0)
		if remaining == 0.0:
			_respawn_remaining.erase(enemy)
			_respawn_enemy.call_deferred(enemy)
		else:
			_respawn_remaining[enemy] = remaining


func _build_encounter() -> void:
	if _built:
		return
	_built = true
	if encounter_definition == null or enemy_scene == null:
		push_warning("EncounterManager requires an EncounterDefinition and enemy scene.")
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
	_enemy_to_spawn[enemy] = spawn
	_alive_enemies[enemy] = true
	_group_alive_counts[group_index] += 1
	_enemies_container.add_child(enemy)


func _on_enemy_defeated(enemy: GroundedEnemyController, source: Node) -> void:
	if not _alive_enemies.has(enemy) or _respawn_remaining.has(enemy):
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
	var spawn := _enemy_to_spawn.get(enemy) as EnemySpawnDefinition
	_respawn_remaining[enemy] = maxf(spawn.respawn_delay, 0.0) if spawn != null else 0.0
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


func _respawn_enemy(enemy: GroundedEnemyController) -> void:
	if enemy == null or not is_instance_valid(enemy) or _alive_enemies.has(enemy):
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
