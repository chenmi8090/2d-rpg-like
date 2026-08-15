class_name Player
extends CharacterBody2D

signal respawned(reason: RespawnReason)
signal health_changed(current: int, maximum: int)
signal material_changed(total: int)
signal progression_changed(level: int, current_experience: int, required_experience: int, maximum_level_reached: bool)
signal level_up(level: int, levels_gained: int)
signal stats_changed
signal equipment_changed
signal equipment_inventory_changed
signal skills_changed
signal equipment_equip_failed(message: String)
signal attack_started(attack_type: int, profile_id: StringName)
signal attack_phase_changed(attack_type: int, phase: int)
signal attack_hit_confirmed(attack_type: int, profile_id: StringName)
signal attack_ended(attack_type: int, profile_id: StringName, cancelled: bool)

enum RespawnReason {
	DEATH,
	MANUAL_RESET,
}

enum AttackType {
	LIGHT,
	HEAVY,
	SKILL,
}

enum AttackPhase {
	NONE,
	STARTUP,
	ACTIVE,
	RECOVERY,
}

enum State {
	IDLE,
	WALK,
	SPRINT,
	JUMP,
	FALL,
	CROUCH,
	ATTACK,
	HIT,
	DEAD,
}

enum HitReaction {
	NORMAL,
	HEAVY,
}

const ONE_WAY_LAYER := 3
const DROP_THROUGH_TIME := 0.2
const DROP_THROUGH_SPEED := 100.0
const CROUCH_CLEARANCE_MASK := 1
const STARDUST_FRAGMENT_ID := &"stardust_fragment"
const EQUIPMENT_MODIFIER_SOURCE := &"equipment"
const PASSIVE_SKILL_MODIFIER_SOURCE := &"passive_skills"
const DEFAULT_SKILL_QUICKBAR_SIZE := 2
const PLAYER_ATTACK_PROJECTILE_SCENE := preload("res://scenes/combat/player_attack_projectile.tscn")

@export var move_speed := 280.0
@export var sprint_speed := 430.0
@export var double_tap_window := 0.24
@export var ground_acceleration := 2600.0
@export var ground_deceleration := 3200.0
@export var ground_reversal_acceleration := 4200.0
@export var air_acceleration := 1100.0
@export var air_deceleration := 550.0
@export var gravity := 1650.0
@export var jump_velocity := -590.0
@export var jump_cutoff_multiplier := 0.45
@export var coyote_time := 0.10
@export var jump_buffer_time := 0.12
@export var apex_velocity_threshold := 75.0
@export var apex_gravity_multiplier := 0.72
@export var fall_gravity_multiplier := 1.35
@export var maximum_fall_speed := 1250.0
@export_category("Progression")
@export var progression_definition: PlayerProgressionDefinition
@export var profession_definition: ProfessionDefinition
@export_category("Health")
@export var hit_stun_time := 0.25
@export var invulnerability_time := 0.8
@export var damage_knockback_speed := 240.0
@export var heavy_hit_stun_time := 0.42
@export_range(0.0, 1.0, 0.01) var heavy_hit_damage_ratio := 0.25
@export_range(0.0, 1.0, 0.01) var heavy_airborne_damage_ratio := 0.15
@export_range(0.0, 1.0, 0.01) var heavy_sprint_damage_ratio := 0.15
@export_range(0.0, 5.0, 0.01) var heavy_reaction_protection_time := 1.2
@export_range(0.0, 1000.0, 1.0) var heavy_hit_knockback_cap := 300.0
@export_range(0.0, 1.0, 0.01) var true_sprint_hit_speed_ratio := 0.85
@export var death_respawn_delay := 0.8
@export var spawn_input_suppression_time := 0.12

var current_state := State.IDLE
var _facing_direction := 1.0
var _last_left_press_time := -double_tap_window
var _last_right_press_time := -double_tap_window
var _sprint_direction := 0.0
var _elapsed_time := 0.0
var _drop_through_timer := 0.0
var _attack_elapsed := 0.0
var _attack_direction := 1.0
var _attack_hitbox_active := false
var _current_attack_type := AttackType.LIGHT
var _current_attack_phase := AttackPhase.NONE
var _last_auto_attack_type := AttackType.HEAVY
var _current_attack_critical := false
var _current_attack_profile: PlayerBasicAttackProfile
var _current_attack_damage := 1
var _current_attack_projectile_spawned := false
var _current_attack_hit_confirmed := false
var _current_skill_definition: SkillDefinition
var _current_skill_rank := 0
var _skill_cooldowns: Dictionary = {}
var _air_attack_consumed := false
var _attack_started_on_floor := false
var _next_light_attack_time := 0.0
var _next_heavy_attack_time := 0.0
var _health := 10
var _hit_stun_timer := 0.0
var _invulnerability_timer := 0.0
var _heavy_reaction_protection_timer := 0.0
var _last_hit_reaction := HitReaction.NORMAL
var _last_mitigated_hit_damage := 0
var _last_hit_damage_ratio := 0.0
var _pre_hit_state := State.IDLE
var _pre_hit_velocity := Vector2.ZERO
var _pre_hit_on_floor := true
var _death_respawn_timer := 0.0
var _spawn_position := Vector2.ZERO
var _stardust_fragments := 0
var _stats := PlayerStats.new()
var _skill_progress := PlayerSkillProgress.new()
var _skill_quickbar: Array[StringName] = []
var _equipped_items: Dictionary = {}
var _equipment_inventory: Array[EquipmentInstance] = []
var _next_equipment_instance_serial := 1
var _input_suppression_timer := 0.0
var _gameplay_input_blocked := false
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _jump_consumed := false

@onready var _standing_collision: CollisionShape2D = $StandingCollision
@onready var _crouching_collision: CollisionShape2D = $CrouchingCollision
@onready var _visual: Node2D = $Visual
@onready var _hurtbox: Hurtbox = $PlayerHurtbox
@onready var _hurtbox_collision: CollisionShape2D = $PlayerHurtbox/CollisionShape2D
@onready var _attack_hitbox: AttackHitbox = $AttackHitbox
@onready var _attack_collision: CollisionShape2D = $AttackHitbox/CollisionShape2D


func _ready() -> void:
	if _attack_collision.shape != null:
		_attack_collision.shape = _attack_collision.shape.duplicate()
	_attack_hitbox.hit_confirmed.connect(_on_attack_hit_confirmed)
	_stats.initialize(progression_definition)
	_skill_progress.initialize(
		progression_definition.starting_skill_points
		if progression_definition != null else 0
	)
	_skill_quickbar = _default_skill_quickbar()
	_apply_starting_equipment()
	_stats.rng.randomize()
	_spawn_position = global_position
	_health = get_max_health()
	_set_crouched(false)
	_visual.set_facing_direction(_facing_direction)
	player_ready.call_deferred()


func player_ready() -> void:
	health_changed.emit(_health, get_max_health())
	material_changed.emit(_stardust_fragments)
	_emit_progression_changed()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	var game_session := get_node_or_null("/root/GameSession")
	if game_session == null:
		return
	for action in game_session.GAMEPLAY_INPUT_ACTIONS:
		Input.action_release(action)
	Input.flush_buffered_events()
	suppress_gameplay_input()


func _exit_tree() -> void:
	_cancel_attack()
	_clear_owned_projectiles()
	_air_attack_consumed = false


func _physics_process(delta: float) -> void:
	_elapsed_time += delta
	_input_suppression_timer = maxf(_input_suppression_timer - delta, 0.0)
	_update_invulnerability(delta)
	_update_heavy_reaction_protection(delta)
	if _action_just_pressed(&"reset"):
		respawn(RespawnReason.MANUAL_RESET)
		return
	if current_state == State.DEAD:
		_update_dead(delta)
		return
	if current_state == State.HIT:
		_update_hit(delta)
		return

	var was_on_floor := is_on_floor()
	var attack_started_on_floor_before_move := current_state == State.ATTACK and _attack_started_on_floor
	_update_drop_through(delta)
	_update_jump_timers(delta, was_on_floor)
	_update_sprint_input()
	_handle_skill_input()
	_handle_attack_input()
	attack_started_on_floor_before_move = current_state == State.ATTACK and _attack_started_on_floor
	_update_attack(delta)
	if current_state != State.ATTACK:
		_handle_ground_actions(was_on_floor)
	_apply_horizontal_movement(delta, was_on_floor)
	_apply_vertical_movement(delta, was_on_floor)
	move_and_slide()
	_handle_floor_transition(was_on_floor, attack_started_on_floor_before_move)
	_resolve_state()


func receive_hit(amount: int, _source: Node, hit_direction: float, metadata: Dictionary = {}) -> bool:
	if current_state == State.DEAD or _invulnerability_timer > 0.0:
		return false
	_capture_pre_hit_snapshot()
	var final_amount := _stats.mitigate_physical_damage(amount)
	var reaction := _classify_hit_reaction(final_amount, hit_direction, metadata)
	_record_hit_observability(reaction, final_amount)
	_health = maxi(_health - final_amount, 0)
	health_changed.emit(_health, get_max_health())
	if _health <= 0:
		_enter_dead()
		return true
	_invulnerability_timer = invulnerability_time
	if reaction == HitReaction.NORMAL:
		_visual.show_hurt_feedback(hit_stun_time, 1.0)
		return true
	_cancel_attack()
	_air_attack_consumed = not is_on_floor()
	_clear_transient_movement_state(false, true)
	_apply_hit_reaction(reaction, hit_direction, metadata)
	_set_state(State.HIT)
	return true


func is_hurt_feedback_active() -> bool:
	return _visual.has_method("is_hurt_feedback_active") and bool(_visual.call("is_hurt_feedback_active"))


func get_hurt_feedback_remaining() -> float:
	return float(_visual.call("get_hurt_feedback_remaining")) if _visual.has_method("get_hurt_feedback_remaining") else 0.0


func get_hurt_feedback_intensity() -> float:
	return float(_visual.call("get_hurt_feedback_intensity")) if _visual.has_method("get_hurt_feedback_intensity") else 0.0


func get_last_hit_reaction() -> HitReaction:
	return _last_hit_reaction


func get_last_mitigated_hit_damage() -> int:
	return _last_mitigated_hit_damage


func get_last_hit_damage_ratio() -> float:
	return _last_hit_damage_ratio


func get_invulnerability_remaining() -> float:
	return _invulnerability_timer


func get_heavy_reaction_protection_remaining() -> float:
	return _heavy_reaction_protection_timer


func is_heavy_reaction_protected() -> bool:
	return _heavy_reaction_protection_timer > 0.0


func get_hit_stun_remaining() -> float:
	return _hit_stun_timer


func _capture_pre_hit_snapshot() -> void:
	_pre_hit_state = current_state
	_pre_hit_velocity = velocity
	_pre_hit_on_floor = is_on_floor()


func _classify_hit_reaction(mitigated_amount: int, hit_direction: float, metadata: Dictionary) -> HitReaction:
	var mitigated_ratio := HitReactionRules.damage_ratio(mitigated_amount, get_max_health())
	var candidate_heavy := HitReactionRules.qualifies_for_knockback(
		mitigated_amount,
		get_max_health(),
		heavy_hit_damage_ratio,
		metadata
	)
	if mitigated_ratio >= heavy_airborne_damage_ratio and not _pre_hit_on_floor:
		candidate_heavy = true
	if mitigated_ratio >= heavy_sprint_damage_ratio and _was_true_sprint_into_hit(hit_direction):
		candidate_heavy = true
	if candidate_heavy and not is_heavy_reaction_protected():
		return HitReaction.HEAVY
	return HitReaction.NORMAL


func _hit_damage_ratio(mitigated_amount: int) -> float:
	return HitReactionRules.damage_ratio(mitigated_amount, get_max_health())


func _record_hit_observability(reaction: HitReaction, mitigated_amount: int) -> void:
	_last_hit_reaction = reaction
	_last_mitigated_hit_damage = mitigated_amount
	_last_hit_damage_ratio = _hit_damage_ratio(mitigated_amount)


func _was_true_sprint_into_hit(hit_direction: float) -> bool:
	if _pre_hit_state != State.SPRINT:
		return false
	var incoming_direction := signf(hit_direction)
	if incoming_direction == 0.0:
		return false
	if absf(_pre_hit_velocity.x) < sprint_speed * true_sprint_hit_speed_ratio:
		return false
	return signf(_pre_hit_velocity.x) == -incoming_direction


func _apply_hit_reaction(reaction: HitReaction, hit_direction: float, metadata: Dictionary) -> void:
	if reaction == HitReaction.HEAVY:
		var knockback_speed := minf(
			HitReactionRules.resolve_knockback_speed(damage_knockback_speed, metadata),
			heavy_hit_knockback_cap
		)
		_hit_stun_timer = maxf(heavy_hit_stun_time, hit_stun_time)
		_visual.show_hurt_feedback(_hit_stun_timer, 1.0)
		velocity.x = signf(hit_direction) * knockback_speed
		_heavy_reaction_protection_timer = heavy_reaction_protection_time
		return
	_hit_stun_timer = hit_stun_time
	_visual.show_hurt_feedback(hit_stun_time, 1.0)
	velocity.x = 0.0


func _update_hit(delta: float) -> void:
	_hit_stun_timer = maxf(_hit_stun_timer - delta, 0.0)
	if not is_on_floor():
		velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, damage_knockback_speed * 4.0 * delta)
	move_and_slide()
	if _hit_stun_timer == 0.0:
		_set_state(State.IDLE if is_on_floor() else State.FALL)


func _enter_dead() -> void:
	_cancel_attack()
	_clear_owned_projectiles()
	_clear_transient_movement_state(true, true)
	_visual.clear_hurt_feedback()
	_clear_hit_reaction_observability()
	current_state = State.DEAD
	velocity = Vector2.ZERO
	_death_respawn_timer = death_respawn_delay
	_hurtbox.enabled = false
	_hurtbox_collision.set_deferred("disabled", true)
	_visual.modulate = Color(0.45, 0.45, 0.45, 1.0)


func _update_dead(delta: float) -> void:
	_death_respawn_timer = maxf(_death_respawn_timer - delta, 0.0)
	if _death_respawn_timer == 0.0:
		respawn(RespawnReason.DEATH)


func _update_heavy_reaction_protection(delta: float) -> void:
	_heavy_reaction_protection_timer = maxf(_heavy_reaction_protection_timer - delta, 0.0)


func _clear_hit_reaction_observability() -> void:
	_heavy_reaction_protection_timer = 0.0
	_last_hit_reaction = HitReaction.NORMAL
	_last_mitigated_hit_damage = 0
	_last_hit_damage_ratio = 0.0


func _update_invulnerability(delta: float) -> void:
	if _invulnerability_timer <= 0.0:
		_visual.modulate.a = 1.0
		return
	_invulnerability_timer = maxf(_invulnerability_timer - delta, 0.0)
	_visual.modulate.a = 0.45 if int(_invulnerability_timer * 20.0) % 2 == 0 else 1.0
	if _invulnerability_timer == 0.0:
		_visual.modulate.a = 1.0


func get_navigation_feet_position() -> Vector2:
	var collision := _active_navigation_collision()
	if collision == null or collision.shape == null:
		return global_position
	var bottom := collision.position.y
	var shape := collision.shape
	if shape is CapsuleShape2D:
		bottom += (shape as CapsuleShape2D).height * 0.5
	elif shape is RectangleShape2D:
		bottom += (shape as RectangleShape2D).size.y * 0.5
	elif shape is CircleShape2D:
		bottom += (shape as CircleShape2D).radius
	else:
		var bounds := shape.get_rect()
		bottom += bounds.position.y + bounds.size.y
	return global_position + Vector2(collision.position.x, bottom)


func _active_navigation_collision() -> CollisionShape2D:
	if _crouching_collision != null and not _crouching_collision.disabled:
		return _crouching_collision
	if _standing_collision != null and not _standing_collision.disabled:
		return _standing_collision
	return _standing_collision


func get_health() -> int:
	return _health


func get_max_health() -> int:
	return maxi(floori(_stats.get_stat(PlayerStats.MAX_HEALTH) + 0.5), 1)


func get_level() -> int:
	return _stats.level


func get_experience() -> int:
	return _stats.experience


func get_experience_requirement() -> int:
	return _stats.get_experience_requirement()


func is_max_level() -> bool:
	return _stats.is_max_level()


func get_stat(stat_key: StringName) -> float:
	return _stats.get_stat(stat_key)


func get_profession_name() -> String:
	if profession_definition == null or profession_definition.display_name.is_empty():
		return "未选择职业"
	return profession_definition.display_name


func get_profession_id() -> StringName:
	return profession_definition.id if profession_definition != null else &""


func get_skill_points() -> int:
	return _skill_progress.unspent_points


func get_skill_rank(skill_id: StringName) -> int:
	return _skill_progress.get_rank(skill_id)


func get_profession_skills() -> Array[SkillDefinition]:
	var definitions: Array[SkillDefinition] = []
	if profession_definition == null:
		return definitions
	for skill_id in profession_definition.skill_ids:
		var definition := DefinitionRegistry.get_skill(skill_id)
		if definition != null:
			definitions.append(definition)
	return definitions


func get_skill_rank_up_status(skill_id: StringName) -> Dictionary:
	return _skill_progress.get_rank_up_status(
		skill_id,
		get_profession_id(),
		get_level()
	)


func increase_skill_rank(skill_id: StringName) -> Dictionary:
	var old_max := get_max_health()
	var result := _skill_progress.increase_rank(
		skill_id,
		get_profession_id(),
		get_level()
	)
	if not bool(result.get("ok", false)):
		return result
	_rebuild_passive_skill_modifiers()
	_apply_stats_change(old_max)
	skills_changed.emit()
	return result


func get_skill_rank_down_status(skill_id: StringName) -> Dictionary:
	if _current_skill_definition != null and _current_skill_definition.id == skill_id:
		return {"ok": false, "message": "技能施放期间不能减点"}
	return _skill_progress.get_rank_down_status(skill_id, get_profession_id())


func decrease_skill_rank(skill_id: StringName) -> Dictionary:
	var status := get_skill_rank_down_status(skill_id)
	if not bool(status.get("ok", false)):
		return status
	var old_max := get_max_health()
	var result := _skill_progress.decrease_rank(skill_id, get_profession_id())
	if not bool(result.get("ok", false)):
		return result
	if get_skill_rank(skill_id) <= 0:
		for slot_index in _skill_quickbar.size():
			if _skill_quickbar[slot_index] == skill_id:
				_skill_quickbar[slot_index] = &""
	_rebuild_passive_skill_modifiers()
	_apply_stats_change(old_max)
	skills_changed.emit()
	return result


func get_skill_quickbar() -> Array[StringName]:
	return _skill_quickbar.duplicate()


func get_skill_cooldown_remaining(skill_id: StringName) -> float:
	return maxf(float(_skill_cooldowns.get(skill_id, 0.0)) - _elapsed_time, 0.0)


func can_cast_skill(skill_id: StringName) -> Dictionary:
	var definition := DefinitionRegistry.get_skill(skill_id)
	return _get_skill_cast_status(definition)


func cast_skill(skill_id: StringName) -> Dictionary:
	var definition := DefinitionRegistry.get_skill(skill_id)
	var status := _get_skill_cast_status(definition)
	if not bool(status.get("ok", false)):
		return status
	_start_skill(definition)
	return {
		"ok": true,
		"message": "技能施放成功",
		"skill_id": definition.id,
	}


func set_skill_quickbar_slot(slot_index: int, skill_id: StringName) -> Dictionary:
	if slot_index < 0 or slot_index >= _skill_quickbar.size():
		return {"ok": false, "message": "技能快捷栏位置无效"}
	if skill_id == &"":
		_skill_quickbar[slot_index] = &""
		skills_changed.emit()
		return {"ok": true, "message": "快捷栏已清空"}
	var definition := DefinitionRegistry.get_skill(skill_id)
	if definition == null or not definition.is_active():
		return {"ok": false, "message": "只能配置有效的主动技能"}
	if not definition.is_available_to_profession(get_profession_id()):
		return {"ok": false, "message": "当前职业无法配置该技能"}
	if get_skill_rank(skill_id) <= 0:
		return {"ok": false, "message": "技能尚未学习"}
	_skill_quickbar[slot_index] = skill_id
	skills_changed.emit()
	return {"ok": true, "message": "快捷栏配置成功"}


func _default_skill_quickbar() -> Array[StringName]:
	var slots: Array[StringName] = []
	slots.resize(DEFAULT_SKILL_QUICKBAR_SIZE)
	slots.fill(&"")
	return slots


func _load_skill_quickbar(snapshot: Dictionary) -> void:
	_skill_quickbar = _default_skill_quickbar()
	var raw_slots := snapshot.get("slots", []) as Array
	if raw_slots.size() > _skill_quickbar.size():
		var previous_size := _skill_quickbar.size()
		_skill_quickbar.resize(raw_slots.size())
		for index in range(previous_size, _skill_quickbar.size()):
			_skill_quickbar[index] = &""
	for index in raw_slots.size():
		var skill_id := StringName(String(raw_slots[index]))
		var definition := DefinitionRegistry.get_skill(skill_id)
		if (
			definition != null
			and definition.is_active()
			and definition.is_available_to_profession(get_profession_id())
			and get_skill_rank(skill_id) > 0
		):
			_skill_quickbar[index] = skill_id


func _rebuild_passive_skill_modifiers() -> void:
	var modifiers: Array[StatModifier] = []
	for definition in get_profession_skills():
		if not definition.is_passive():
			continue
		var modifier := definition.passive_modifier_at_rank(
			get_skill_rank(definition.id)
		)
		if modifier != null:
			modifiers.append(modifier)
	_stats.set_modifier_source(PASSIVE_SKILL_MODIFIER_SOURCE, modifiers)


func get_save_snapshot() -> Dictionary:
	var equipped: Dictionary = {}
	var instances: Dictionary = {}
	for slot in EquipmentSlot.ALL:
		var item := get_equipped_item(slot)
		if item != null:
			equipped[String(slot)] = item.instance_id
			instances[item.instance_id] = item.to_snapshot()
	var inventory_ids: Array[String] = []
	for item in _equipment_inventory:
		if item == null or not item.is_valid():
			continue
		inventory_ids.append(item.instance_id)
		instances[item.instance_id] = item.to_snapshot()
	return {
		"progression": {"level": _stats.level, "experience": _stats.experience},
		"skills": _skill_progress.to_snapshot(),
		"skill_quickbar": {"slots": _skill_quickbar.duplicate()},
		"materials": {"stardust_fragment": _stardust_fragments},
		"equipment": {
			"next_instance_serial": _next_equipment_instance_serial,
			"instances": instances.values(),
			"equipped": equipped,
			"inventory": inventory_ids,
		},
	}


func apply_save_snapshot(profile: Dictionary) -> Dictionary:
	var profession_id := StringName(String(profile.get("profession_id", "")))
	var profession := DefinitionRegistry.get_profession(profession_id)
	if profession == null:
		return {"ok": false, "message": "角色职业定义不存在"}
	profession_definition = profession
	_stats.initialize(progression_definition)
	var progression := profile.get("progression", {}) as Dictionary
	_stats.level = clampi(int(progression.get("level", 1)), 1, progression_definition.maximum_level)
	_stats.experience = maxi(int(progression.get("experience", 0)), 0)
	if _stats.is_max_level():
		_stats.experience = 0
	_skill_progress.load_snapshot(
		profile.get("skills", {}) as Dictionary,
		profession_id
	)
	_load_skill_quickbar(profile.get("skill_quickbar", {}) as Dictionary)
	_skill_cooldowns.clear()
	_equipped_items.clear()
	_equipment_inventory.clear()
	var equipment := profile.get("equipment", {}) as Dictionary
	_next_equipment_instance_serial = maxi(int(equipment.get("next_instance_serial", 1)), 1)
	var instances_by_id: Dictionary = {}
	for snapshot in equipment.get("instances", []) as Array:
		if not snapshot is Dictionary:
			continue
		var item := EquipmentInstance.from_snapshot(snapshot)
		if item.is_valid() and not instances_by_id.has(item.instance_id):
			instances_by_id[item.instance_id] = item
	var equipped := equipment.get("equipped", {}) as Dictionary
	for slot in EquipmentSlot.ALL:
		var instance_id := String(equipped.get(String(slot), ""))
		var item := instances_by_id.get(instance_id) as EquipmentInstance
		if item != null and item.get_slot() == slot and profession_definition.can_equip(item.definition):
			_equipped_items[slot] = item
	var inventory := equipment.get("inventory", []) as Array
	for raw_id in inventory:
		var item := instances_by_id.get(String(raw_id)) as EquipmentInstance
		if item != null and not _is_equipped_instance(item.instance_id):
			_equipment_inventory.append(item)
	var materials := profile.get("materials", {}) as Dictionary
	_stardust_fragments = maxi(int(materials.get("stardust_fragment", 0)), 0)
	_stats.set_modifier_source(EQUIPMENT_MODIFIER_SOURCE, _equipment_modifiers())
	_rebuild_passive_skill_modifiers()
	_cancel_attack()
	_clear_owned_projectiles()
	_air_attack_consumed = false
	velocity = Vector2.ZERO
	_health = get_max_health()
	_hit_stun_timer = 0.0
	_invulnerability_timer = 0.0
	_clear_hit_reaction_observability()
	_death_respawn_timer = 0.0
	_visual.clear_hurt_feedback()
	_hurtbox.enabled = true
	_hurtbox_collision.set_deferred("disabled", false)
	_visual.modulate = Color.WHITE
	_set_state(State.IDLE)
	_set_crouched(false)
	suppress_gameplay_input()
	health_changed.emit(_health, get_max_health())
	material_changed.emit(_stardust_fragments)
	_emit_progression_changed()
	stats_changed.emit()
	equipment_changed.emit()
	equipment_inventory_changed.emit()
	skills_changed.emit()
	return {"ok": true, "message": ""}


func apply_safe_spawn(spawn_position: Vector2, preserve_horizontal_movement := false) -> void:
	_spawn_position = spawn_position
	global_position = spawn_position
	if preserve_horizontal_movement:
		velocity.y = 0.0
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_consumed = false
		_drop_through_timer = 0.0
		set_collision_mask_value(ONE_WAY_LAYER, true)
		return
	suppress_gameplay_input()


func set_facing_direction(direction: float) -> void:
	var resolved := signf(direction)
	if resolved == 0.0:
		return
	_facing_direction = resolved
	_visual.set_facing_direction(_facing_direction)


func suppress_gameplay_input(duration := -1.0) -> void:
	var suppression_duration := spawn_input_suppression_time if duration < 0.0 else duration
	_input_suppression_timer = maxf(_input_suppression_timer, suppression_duration)
	_reset_movement_input_state()


func set_gameplay_input_blocked(blocked: bool) -> void:
	if _gameplay_input_blocked == blocked:
		return
	_gameplay_input_blocked = blocked
	_reset_movement_input_state()
	if not blocked:
		_input_suppression_timer = 0.0


func is_gameplay_input_blocked() -> bool:
	return _gameplay_input_blocked


func _reset_movement_input_state() -> void:
	_clear_transient_movement_state(true, true)


func _clear_transient_movement_state(clear_horizontal_velocity: bool, restore_one_way_collision: bool) -> void:
	if clear_horizontal_velocity:
		velocity.x = 0.0
	_sprint_direction = 0.0
	_last_left_press_time = _elapsed_time - double_tap_window - 1.0
	_last_right_press_time = _elapsed_time - double_tap_window - 1.0
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jump_consumed = false
	if restore_one_way_collision:
		_drop_through_timer = 0.0
		set_collision_mask_value(ONE_WAY_LAYER, true)


func _input_suppressed() -> bool:
	return _gameplay_input_blocked or _input_suppression_timer > 0.0


func _movement_axis() -> float:
	return 0.0 if _input_suppressed() else Input.get_axis("move_left", "move_right")


func _action_pressed(action: StringName) -> bool:
	return not _input_suppressed() and Input.is_action_pressed(action)


func _action_just_pressed(action: StringName) -> bool:
	return not _input_suppressed() and Input.is_action_just_pressed(action)


func _action_just_released(action: StringName) -> bool:
	return not _input_suppressed() and Input.is_action_just_released(action)


func can_equip(candidate: Variant) -> bool:
	var definition := _definition_for_equipment_candidate(candidate)
	return definition != null and profession_definition != null and profession_definition.can_equip(definition)


func equip_item(candidate: Variant) -> bool:
	var item := _instance_for_equipment_candidate(candidate)
	if item == null or not can_equip(item):
		return false
	var inventory_owned := item in _equipment_inventory
	return _equip_instance(item, inventory_owned)


func _equip_instance(item: EquipmentInstance, remove_from_inventory: bool) -> bool:
	var slot := item.get_slot()
	var replaced := get_equipped_item(slot)
	if replaced == item:
		return true
	var inventory_changed := false
	if remove_from_inventory:
		_equipment_inventory.erase(item)
		inventory_changed = true
	elif item in _equipment_inventory:
		_equipment_inventory.erase(item)
		inventory_changed = true
	_equipped_items[slot] = item
	if replaced != null:
		_equipment_inventory.append(replaced)
		inventory_changed = true
	_refresh_equipment_modifiers()
	equipment_changed.emit()
	if inventory_changed:
		equipment_inventory_changed.emit()
	return true


func _definition_for_equipment_candidate(candidate: Variant) -> EquipmentDefinition:
	if candidate is EquipmentInstance:
		return (candidate as EquipmentInstance).definition
	if candidate is EquipmentDefinition:
		return candidate as EquipmentDefinition
	return null


func _instance_for_equipment_candidate(candidate: Variant) -> EquipmentInstance:
	if candidate is EquipmentInstance:
		return candidate as EquipmentInstance
	if candidate is EquipmentDefinition:
		return create_template_equipment(candidate as EquipmentDefinition)
	return null


func unequip_slot(slot: StringName) -> EquipmentInstance:
	if not EquipmentSlot.is_valid(slot):
		return null
	var removed := _remove_equipped_item(slot)
	if removed == null:
		return null
	_equipment_inventory.append(removed)
	_refresh_equipment_modifiers()
	equipment_changed.emit()
	equipment_inventory_changed.emit()
	return removed


func unequip_to_inventory(slot: StringName) -> bool:
	return unequip_slot(slot) != null


func _remove_equipped_item(slot: StringName) -> EquipmentInstance:
	var removed := _equipped_items.get(slot) as EquipmentInstance
	if removed != null:
		_equipped_items.erase(slot)
	return removed


func get_equipped_item(slot: StringName) -> EquipmentInstance:
	return _equipped_items.get(slot) as EquipmentInstance


func get_equipped_items() -> Dictionary:
	return _equipped_items.duplicate()


func reserve_equipment_instance_id() -> String:
	var instance_id := "equipment_%08d" % _next_equipment_instance_serial
	_next_equipment_instance_serial += 1
	return instance_id


func create_template_equipment(definition: EquipmentDefinition) -> EquipmentInstance:
	if definition == null or not definition.is_valid():
		return null
	return EquipmentInstance.create_template_instance(reserve_equipment_instance_id(), definition)


func collect_equipment(item: EquipmentInstance) -> bool:
	if item == null or not item.is_valid() or has_equipment_instance(item.instance_id):
		return false
	_equipment_inventory.append(item)
	equipment_inventory_changed.emit()
	return true


func get_equipment_inventory() -> Array[EquipmentInstance]:
	return _equipment_inventory.duplicate()


func discard_inventory_item(instance_id: String) -> bool:
	if instance_id.is_empty() or _is_equipped_instance(instance_id):
		return false
	for index in _equipment_inventory.size():
		var item := _equipment_inventory[index]
		if item != null and item.instance_id == instance_id:
			_equipment_inventory.remove_at(index)
			equipment_inventory_changed.emit()
			return true
	return false


func get_equipment_instance(instance_id: String) -> EquipmentInstance:
	for item in _equipment_inventory:
		if item != null and item.instance_id == instance_id:
			return item
	for item in _equipped_items.values():
		if item is EquipmentInstance and item.instance_id == instance_id:
			return item
	return null


func has_equipment_instance(instance_id: String) -> bool:
	return get_equipment_instance(instance_id) != null


func get_equipment_count(definition: EquipmentDefinition) -> int:
	var count := 0
	for item in _equipment_inventory:
		if item != null and item.definition == definition:
			count += 1
	return count


func equip_inventory_item(instance_id: String) -> bool:
	var item := get_equipment_instance(instance_id)
	if item == null or item not in _equipment_inventory:
		equipment_equip_failed.emit("背包中没有该装备")
		return false
	if not can_equip(item):
		equipment_equip_failed.emit("当前职业无法装备该武器" if item.is_weapon() else "当前职业无法装备该物品")
		return false
	return _equip_instance(item, true)


func preview_equipment_stats(item: EquipmentInstance) -> Dictionary:
	var before: Dictionary = {}
	var after: Dictionary = {}
	var delta: Dictionary = {}
	if item == null or not item.is_valid():
		return {"valid": false, "before": before, "after": after, "delta": delta, "current": null}
	var preview_stats := PlayerStats.new()
	preview_stats.initialize(progression_definition)
	preview_stats.level = _stats.level
	preview_stats.experience = _stats.experience
	var sources := _stats.get_modifier_sources_copy()
	sources[EQUIPMENT_MODIFIER_SOURCE] = _equipment_modifiers_with_replacement(item)
	preview_stats.set_modifier_sources(sources)
	for stat_key in _preview_stat_order():
		var current_value := get_stat(stat_key)
		var preview_value := preview_stats.get_stat(stat_key)
		before[stat_key] = current_value
		after[stat_key] = preview_value
		delta[stat_key] = preview_value - current_value
	return {
		"valid": can_equip(item),
		"before": before,
		"after": after,
		"delta": delta,
		"current": get_equipped_item(item.get_slot()),
	}


func _equipment_modifiers_with_replacement(candidate: EquipmentInstance) -> Array[StatModifier]:
	var combined: Array[StatModifier] = []
	for slot in EquipmentSlot.ALL:
		var item := candidate if slot == candidate.get_slot() else get_equipped_item(slot)
		if item != null:
			combined.append_array(item.get_modifiers())
	return combined


func _is_equipped_instance(instance_id: String) -> bool:
	for item in _equipped_items.values():
		if item is EquipmentInstance and item.instance_id == instance_id:
			return true
	return false


func _preview_stat_order() -> Array[StringName]:
	return [
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


func _apply_starting_equipment() -> void:
	_equipped_items.clear()
	_equipment_inventory.clear()
	_next_equipment_instance_serial = 1
	if profession_definition == null:
		return
	for definition in profession_definition.starting_equipment:
		if profession_definition.can_equip(definition):
			var item := create_template_equipment(definition)
			if item != null:
				_equipped_items[item.get_slot()] = item
	_stats.set_modifier_source(EQUIPMENT_MODIFIER_SOURCE, _equipment_modifiers())


func _refresh_equipment_modifiers() -> void:
	var old_max := get_max_health()
	_stats.set_modifier_source(EQUIPMENT_MODIFIER_SOURCE, _equipment_modifiers())
	_apply_stats_change(old_max)


func _equipment_modifiers() -> Array[StatModifier]:
	var combined: Array[StatModifier] = []
	for slot in EquipmentSlot.ALL:
		var item := get_equipped_item(slot)
		if item != null:
			combined.append_array(item.get_modifiers())
	return combined


func set_stat_modifier_source(source_id: StringName, modifiers: Array[StatModifier]) -> void:
	var old_max := get_max_health()
	_stats.set_modifier_source(source_id, modifiers)
	_apply_stats_change(old_max)


func remove_stat_modifier_source(source_id: StringName) -> void:
	var old_max := get_max_health()
	_stats.remove_modifier_source(source_id)
	_apply_stats_change(old_max)


func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	var old_max := get_max_health()
	var result := _stats.add_experience(amount)
	var levels_gained := int(result.levels_gained)
	if levels_gained > 0:
		_skill_progress.add_points(
			levels_gained * (
				progression_definition.skill_points_per_level
				if progression_definition != null else 1
			)
		)
		_apply_stats_change(old_max)
		level_up.emit(_stats.level, levels_gained)
		skills_changed.emit()
	_emit_progression_changed()


func _apply_stats_change(old_max: int) -> void:
	var new_max := get_max_health()
	if current_state != State.DEAD and new_max > old_max:
		_health = mini(_health + new_max - old_max, new_max)
	else:
		_health = mini(_health, new_max)
	stats_changed.emit()
	health_changed.emit(_health, new_max)


func _emit_progression_changed() -> void:
	progression_changed.emit(_stats.level, _stats.experience, _stats.get_experience_requirement(), _stats.is_max_level())


func get_credit_owner() -> Node:
	return self


func collect_material(material_id: StringName, amount: int) -> void:
	if material_id != STARDUST_FRAGMENT_ID or amount <= 0:
		return
	_stardust_fragments += amount
	material_changed.emit(_stardust_fragments)


func get_stardust_fragments() -> int:
	return _stardust_fragments


func can_collect_pickups() -> bool:
	return current_state != State.DEAD and _health > 0


func _update_sprint_input() -> void:
	if current_state == State.CROUCH or current_state == State.ATTACK:
		_sprint_direction = 0.0
		return

	if _action_just_pressed(&"move_left"):
		_sprint_direction = -1.0 if _elapsed_time - _last_left_press_time <= double_tap_window else 0.0
		_last_left_press_time = _elapsed_time
		_last_right_press_time = _elapsed_time - double_tap_window - 1.0
	if _action_just_pressed(&"move_right"):
		_sprint_direction = 1.0 if _elapsed_time - _last_right_press_time <= double_tap_window else 0.0
		_last_right_press_time = _elapsed_time
		_last_left_press_time = _elapsed_time - double_tap_window - 1.0

	var direction := _movement_axis()
	if _sprint_direction != 0.0 and direction != _sprint_direction:
		_sprint_direction = 0.0


func _handle_skill_input() -> void:
	if current_state == State.CROUCH or current_state == State.ATTACK:
		return
	for slot_index in _skill_quickbar.size():
		var action := StringName("skill_slot_%d" % (slot_index + 1))
		if not InputMap.has_action(action) or not _action_just_pressed(action):
			continue
		_cast_skill_quickbar_slot(slot_index)
		return


func _cast_skill_quickbar_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _skill_quickbar.size():
		return {"ok": false, "message": "技能快捷栏位置无效"}
	var skill_id := _skill_quickbar[slot_index]
	if skill_id == &"":
		return {"ok": false, "message": "技能快捷栏为空"}
	return cast_skill(skill_id)


func _get_skill_cast_status(definition: SkillDefinition) -> Dictionary:
	if definition == null or not definition.is_active():
		return {"ok": false, "message": "主动技能定义不存在"}
	if not definition.is_available_to_profession(get_profession_id()):
		return {"ok": false, "message": "当前职业无法使用该技能"}
	if get_skill_rank(definition.id) <= 0:
		return {"ok": false, "message": "技能尚未学习"}
	if current_state == State.CROUCH or current_state == State.ATTACK:
		return {"ok": false, "message": "当前状态无法施放技能"}
	if current_state == State.HIT or current_state == State.DEAD:
		return {"ok": false, "message": "当前状态无法施放技能"}
	if not _equipped_weapon_satisfies_skill(definition):
		return {"ok": false, "message": "当前武器无法施放该技能"}
	if is_on_floor():
		if not definition.allow_ground:
			return {"ok": false, "message": "该技能不能在地面施放"}
	else:
		if current_state != State.JUMP and current_state != State.FALL:
			return {"ok": false, "message": "当前状态无法施放技能"}
		if not definition.allow_air:
			return {"ok": false, "message": "该技能不能在空中施放"}
		if _air_attack_consumed:
			return {"ok": false, "message": "本次滞空已使用过攻击"}
	if get_skill_cooldown_remaining(definition.id) > 0.0:
		return {"ok": false, "message": "技能冷却中"}
	return {"ok": true, "message": "可以施放"}


func _equipped_weapon_satisfies_skill(definition: SkillDefinition) -> bool:
	if definition.required_weapon_types.is_empty():
		return true
	var weapon := get_equipped_item(EquipmentSlot.WEAPON)
	return weapon != null and weapon.get_weapon_type() in definition.required_weapon_types


func _handle_attack_input() -> void:
	if current_state == State.CROUCH or current_state == State.ATTACK:
		return
	if not is_on_floor():
		if current_state != State.JUMP and current_state != State.FALL:
			return
		if _air_attack_consumed:
			return

	var requested_type := -1
	var light_just_pressed := _action_just_pressed(&"light_attack")
	var heavy_just_pressed := _action_just_pressed(&"heavy_attack")
	var light_held := _action_pressed(&"light_attack")
	var heavy_held := _action_pressed(&"heavy_attack")

	if light_just_pressed:
		requested_type = AttackType.LIGHT
	elif heavy_just_pressed:
		requested_type = AttackType.HEAVY
	elif light_held and heavy_held:
		requested_type = AttackType.HEAVY if _last_auto_attack_type == AttackType.LIGHT else AttackType.LIGHT
	elif light_held:
		requested_type = AttackType.LIGHT
	elif heavy_held:
		requested_type = AttackType.HEAVY

	if requested_type < 0 or not _can_start_attack(requested_type):
		return
	_start_attack(requested_type)


func _can_start_attack(attack_type: AttackType) -> bool:
	var profile := _profile_for_attack(attack_type)
	if profile == null or not profile.is_valid():
		return false
	var next_attack_time := _next_light_attack_time if attack_type == AttackType.LIGHT else _next_heavy_attack_time
	return _elapsed_time >= next_attack_time


func _profile_for_attack(attack_type: AttackType) -> PlayerBasicAttackProfile:
	var weapon := get_equipped_item(EquipmentSlot.WEAPON)
	if weapon == null:
		return null
	return weapon.get_light_attack_profile() if attack_type == AttackType.LIGHT else weapon.get_heavy_attack_profile()


func _profile_for_id(profile_id: StringName) -> PlayerBasicAttackProfile:
	var weapon := get_equipped_item(EquipmentSlot.WEAPON)
	if weapon == null:
		return null
	var light_profile := weapon.get_light_attack_profile()
	var heavy_profile := weapon.get_heavy_attack_profile()
	if light_profile != null and light_profile.id == profile_id:
		return light_profile
	if heavy_profile != null and heavy_profile.id == profile_id:
		return heavy_profile
	return null


func _start_skill(definition: SkillDefinition) -> void:
	if definition == null or current_state == State.ATTACK:
		return
	var started_airborne := not is_on_floor()
	_attack_started_on_floor = not started_airborne
	_current_skill_definition = definition
	_current_skill_rank = get_skill_rank(definition.id)
	_current_attack_profile = null
	_current_attack_type = AttackType.SKILL
	_current_attack_critical = _stats.roll_critical()
	_current_attack_damage = _calculate_skill_damage(
		definition,
		_current_skill_rank,
		_current_attack_critical
	)
	_current_attack_projectile_spawned = false
	_current_attack_hit_confirmed = false
	_skill_cooldowns[definition.id] = _elapsed_time + definition.cooldown

	var direction := _movement_axis()
	_attack_direction = direction if direction != 0.0 else _facing_direction
	_facing_direction = _attack_direction
	_visual.set_facing_direction(_facing_direction)
	var weapon := get_equipped_item(EquipmentSlot.WEAPON)
	var weapon_type := weapon.get_weapon_type() if weapon != null else &""
	_visual.set_attack(true, _current_attack_type, weapon_type, definition.id)
	_set_attack_phase(AttackPhase.STARTUP)
	_configure_skill_melee_hitbox(definition)
	_attack_elapsed = 0.0
	_attack_hitbox_active = false
	_sprint_direction = 0.0
	if started_airborne:
		_air_attack_consumed = true
	_set_state(State.ATTACK)
	attack_started.emit(_current_attack_type, definition.id)


func _start_attack(attack_type: AttackType) -> void:
	if current_state == State.ATTACK:
		return
	var profile := _profile_for_attack(attack_type)
	if profile == null or not profile.is_valid():
		return
	var started_airborne := not is_on_floor()
	_attack_started_on_floor = not started_airborne
	_current_attack_profile = profile
	_current_attack_type = attack_type
	_last_auto_attack_type = attack_type
	_current_attack_critical = _stats.roll_critical()
	_current_attack_damage = _calculate_attack_damage(profile, _current_attack_critical)
	_current_attack_projectile_spawned = false
	_current_attack_hit_confirmed = false
	if attack_type == AttackType.LIGHT:
		_next_light_attack_time = _elapsed_time + profile.repeat_interval
	else:
		_next_heavy_attack_time = _elapsed_time + profile.repeat_interval

	var direction := _movement_axis()
	_attack_direction = direction if direction != 0.0 else _facing_direction
	_facing_direction = _attack_direction
	_visual.set_facing_direction(_facing_direction)
	_visual.set_attack(true, _current_attack_type, profile.weapon_type, profile.visual_key)
	_set_attack_phase(AttackPhase.STARTUP)
	_configure_melee_hitbox(profile)
	_attack_elapsed = 0.0
	_attack_hitbox_active = false
	_sprint_direction = 0.0
	if started_airborne:
		_air_attack_consumed = true
	_set_state(State.ATTACK)
	attack_started.emit(_current_attack_type, profile.id)


func _configure_skill_melee_hitbox(definition: SkillDefinition) -> void:
	_attack_hitbox.deactivate()
	if definition.delivery != SkillDefinition.Delivery.MELEE:
		return
	if _attack_collision.shape is RectangleShape2D:
		(_attack_collision.shape as RectangleShape2D).size = Vector2(
			maxf(definition.melee_hitbox_size.x, 1.0),
			maxf(definition.melee_hitbox_size.y, 1.0)
		)
	_attack_hitbox.position = Vector2(
		absf(definition.melee_hitbox_offset.x) * _attack_direction,
		definition.melee_hitbox_offset.y
	)


func _configure_melee_hitbox(profile: PlayerBasicAttackProfile) -> void:
	_attack_hitbox.deactivate()
	if profile.delivery != PlayerBasicAttackProfile.Delivery.MELEE:
		return
	if _attack_collision.shape is RectangleShape2D:
		(_attack_collision.shape as RectangleShape2D).size = Vector2(maxf(profile.melee_hitbox_size.x, 1.0), maxf(profile.melee_hitbox_size.y, 1.0))
	_attack_hitbox.position = Vector2(absf(profile.melee_hitbox_offset.x) * _attack_direction, profile.melee_hitbox_offset.y)


func _update_attack(delta: float) -> void:
	if current_state != State.ATTACK:
		return
	if _current_skill_definition != null:
		_update_skill_cast(delta)
		return
	if _current_attack_profile == null:
		_finish_attack()
		return

	_attack_elapsed += delta
	_set_attack_phase(_phase_for_attack_elapsed(_attack_elapsed, _current_attack_profile))
	if _current_attack_profile.delivery == PlayerBasicAttackProfile.Delivery.MELEE:
		var should_be_active := _attack_elapsed >= _current_attack_profile.hit_start and _attack_elapsed < _current_attack_profile.hit_end
		if should_be_active and not _attack_hitbox_active:
			_attack_hitbox.activate(_current_attack_damage, self, _attack_direction, _current_attack_metadata())
			_attack_hitbox_active = true
		elif not should_be_active and _attack_hitbox_active:
			_attack_hitbox.deactivate()
			_attack_hitbox_active = false
	elif not _current_attack_projectile_spawned and _attack_elapsed >= _current_attack_profile.hit_start:
		_spawn_attack_projectile(_current_attack_profile)
		_current_attack_projectile_spawned = true

	if _attack_elapsed >= _current_attack_profile.duration:
		_finish_attack()


func _update_skill_cast(delta: float) -> void:
	var definition := _current_skill_definition
	if definition == null:
		_finish_attack()
		return
	_attack_elapsed += delta
	_set_attack_phase(_phase_for_skill_elapsed(_attack_elapsed, definition))
	var hit_start := definition.startup_time
	var hit_end := hit_start + definition.active_time
	if definition.delivery == SkillDefinition.Delivery.MELEE:
		var should_be_active := _attack_elapsed >= hit_start and _attack_elapsed < hit_end
		if should_be_active and not _attack_hitbox_active:
			_attack_hitbox.activate(
				_current_attack_damage,
				self,
				_attack_direction,
				_current_skill_metadata()
			)
			_attack_hitbox_active = true
		elif not should_be_active and _attack_hitbox_active:
			_attack_hitbox.deactivate()
			_attack_hitbox_active = false
	elif not _current_attack_projectile_spawned and _attack_elapsed >= hit_start:
		_spawn_skill_projectile(definition)
		_current_attack_projectile_spawned = true

	if _attack_elapsed >= hit_end + definition.recovery_time:
		_finish_attack()


func _spawn_skill_projectile(definition: SkillDefinition) -> void:
	if get_parent() == null:
		return
	var projectile := PLAYER_ATTACK_PROJECTILE_SCENE.instantiate() as PlayerAttackProjectile
	projectile.hit_confirmed.connect(
		_on_skill_projectile_hit_confirmed.bind(definition.id)
	)
	get_parent().add_child(projectile)
	projectile.global_position = global_position + Vector2(
		definition.projectile_spawn_offset.x * _attack_direction,
		definition.projectile_spawn_offset.y
	)
	projectile.initialize_skill(
		definition,
		_current_attack_damage,
		self,
		_attack_direction,
		_current_skill_metadata()
	)


func _spawn_attack_projectile(profile: PlayerBasicAttackProfile) -> void:
	if get_parent() == null:
		return
	var projectile := PLAYER_ATTACK_PROJECTILE_SCENE.instantiate() as PlayerAttackProjectile
	projectile.hit_confirmed.connect(_on_projectile_hit_confirmed.bind(_current_attack_type, profile.id))
	get_parent().add_child(projectile)
	projectile.global_position = global_position + Vector2(profile.projectile_spawn_offset.x * _attack_direction, profile.projectile_spawn_offset.y)
	projectile.initialize(profile, _current_attack_damage, self, _attack_direction, _current_attack_metadata())


func _finish_attack() -> void:
	_end_attack(false, true)


func _cancel_attack() -> void:
	if (
		current_state != State.ATTACK
		and not _attack_hitbox_active
		and _current_attack_profile == null
		and _current_skill_definition == null
	):
		return
	_end_attack(true, false)


func _end_attack(cancelled: bool, resolve_after_end: bool) -> void:
	var ended_type := _current_attack_type
	var ended_profile_id := (
		_current_skill_definition.id
		if _current_skill_definition != null
		else _current_attack_profile.id
		if _current_attack_profile != null
		else &""
	)
	_attack_hitbox.deactivate()
	_attack_hitbox_active = false
	_attack_elapsed = 0.0
	_set_attack_phase(AttackPhase.NONE)
	_visual.set_attack(false, ended_type)
	_clear_attack_snapshot()
	attack_ended.emit(ended_type, ended_profile_id, cancelled)
	if resolve_after_end:
		_resolve_state_after_attack()


func _resolve_state_after_attack() -> void:
	if not is_on_floor():
		_set_state(State.JUMP if velocity.y < 0.0 else State.FALL)
		return
	_set_state(State.IDLE)
	_resolve_state()


func _clear_attack_snapshot() -> void:
	_current_attack_profile = null
	_current_skill_definition = null
	_current_skill_rank = 0
	_current_attack_damage = 1
	_current_attack_projectile_spawned = false
	_current_attack_hit_confirmed = false
	_attack_started_on_floor = false


func _current_skill_metadata() -> Dictionary:
	if _current_skill_definition == null:
		return {}
	var metadata := {
		"attack_id": _current_skill_definition.id,
		"skill_id": _current_skill_definition.id,
		"skill_rank": _current_skill_rank,
		"is_critical": _current_attack_critical,
	}
	if _current_skill_definition.force_knockback:
		metadata["force_knockback"] = true
		metadata["minimum_knockback_speed"] = (
			_current_skill_definition.minimum_knockback_speed
		)
	return metadata


func _current_attack_metadata() -> Dictionary:
	if _current_attack_profile == null:
		return {}
	var metadata := {
		"attack_id": _current_attack_profile.id,
		"is_critical": _current_attack_critical,
	}
	if _current_attack_profile.attack_type == AttackType.HEAVY:
		metadata["force_knockback"] = true
		metadata["minimum_knockback_speed"] = _current_attack_profile.minimum_knockback_speed
	return metadata


func _phase_for_skill_elapsed(elapsed: float, definition: SkillDefinition) -> AttackPhase:
	if definition == null:
		return AttackPhase.NONE
	var hit_start := definition.startup_time
	var hit_end := hit_start + definition.active_time
	var duration := hit_end + definition.recovery_time
	if elapsed < hit_start:
		return AttackPhase.STARTUP
	if elapsed < hit_end:
		return AttackPhase.ACTIVE
	if elapsed < duration:
		return AttackPhase.RECOVERY
	return AttackPhase.NONE


func _phase_for_attack_elapsed(elapsed: float, profile: PlayerBasicAttackProfile) -> AttackPhase:
	if profile == null:
		return AttackPhase.NONE
	if elapsed < profile.hit_start:
		return AttackPhase.STARTUP
	if elapsed < profile.hit_end:
		return AttackPhase.ACTIVE
	if elapsed < profile.duration:
		return AttackPhase.RECOVERY
	return AttackPhase.NONE


func _set_attack_phase(phase: AttackPhase) -> void:
	if _current_attack_phase == phase:
		return
	_current_attack_phase = phase
	_visual.set_attack_phase(phase)
	attack_phase_changed.emit(_current_attack_type, phase)


func _apply_skill_hit_feedback(definition: SkillDefinition) -> void:
	if definition == null:
		return
	_visual.show_attack_hit_feedback(
		definition.hit_feedback_time,
		definition.hit_feedback_intensity
	)


func _apply_attack_hit_feedback(profile: PlayerBasicAttackProfile) -> void:
	if profile == null:
		return
	_visual.show_attack_hit_feedback(profile.hit_feedback_time, profile.hit_feedback_intensity)


func _on_attack_hit_confirmed(_hurtbox: Hurtbox, _damage: int, source: Node, _hit_direction: float) -> void:
	if source != self or current_state != State.ATTACK:
		return
	if _current_skill_definition != null:
		_current_attack_hit_confirmed = true
		_apply_skill_hit_feedback(_current_skill_definition)
		attack_hit_confirmed.emit(
			AttackType.SKILL,
			_current_skill_definition.id
		)
		return
	if _current_attack_profile == null:
		return
	_current_attack_hit_confirmed = true
	_apply_attack_hit_feedback(_current_attack_profile)
	attack_hit_confirmed.emit(_current_attack_type, _current_attack_profile.id)


func _on_skill_projectile_hit_confirmed(
	_hurtbox: Hurtbox,
	_damage: int,
	source: Node,
	_hit_direction: float,
	skill_id: StringName
) -> void:
	if source != self:
		return
	var definition := DefinitionRegistry.get_skill(skill_id)
	if (
		current_state == State.ATTACK
		and _current_skill_definition != null
		and _current_skill_definition.id == skill_id
	):
		_current_attack_hit_confirmed = true
		definition = _current_skill_definition
	_apply_skill_hit_feedback(definition)
	attack_hit_confirmed.emit(AttackType.SKILL, skill_id)


func _on_projectile_hit_confirmed(
	_hurtbox: Hurtbox,
	_damage: int,
	source: Node,
	_hit_direction: float,
	attack_type: int,
	profile_id: StringName
) -> void:
	if source != self:
		return
	if current_state == State.ATTACK and _current_attack_profile != null and _current_attack_profile.id == profile_id:
		_current_attack_hit_confirmed = true
		_apply_attack_hit_feedback(_current_attack_profile)
	else:
		_apply_attack_hit_feedback(_profile_for_id(profile_id))
	attack_hit_confirmed.emit(attack_type, profile_id)


func _calculate_skill_damage(
	definition: SkillDefinition,
	rank: int,
	critical: bool
) -> int:
	var stat_key := (
		PlayerStats.MAGIC_ATTACK
		if definition.damage_stat == SkillDefinition.DamageStat.MAGIC_ATTACK
		else PlayerStats.PHYSICAL_ATTACK
	)
	return _stats.calculate_attack_damage(
		stat_key,
		definition.damage_multiplier_at_rank(rank),
		critical
	)


func _calculate_attack_damage(profile: PlayerBasicAttackProfile, critical: bool) -> int:
	var stat_key := PlayerStats.MAGIC_ATTACK if profile.damage_stat == PlayerBasicAttackProfile.DamageStat.MAGIC_ATTACK else PlayerStats.PHYSICAL_ATTACK
	return _stats.calculate_attack_damage(stat_key, profile.damage_multiplier, critical)


func _attack_duration() -> float:
	return _current_attack_profile.duration if _current_attack_profile != null else 0.0


func _attack_hit_start() -> float:
	return _current_attack_profile.hit_start if _current_attack_profile != null else 0.0


func _attack_hit_end() -> float:
	return _current_attack_profile.hit_end if _current_attack_profile != null else 0.0


func _attack_damage() -> int:
	return _current_attack_damage


func _attack_walk_speed_multiplier() -> float:
	if _current_skill_definition != null:
		return 0.0
	return _current_attack_profile.walk_speed_multiplier if _current_attack_profile != null else 0.0


func _update_jump_timers(delta: float, was_on_floor: bool) -> void:
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	if was_on_floor:
		_coyote_timer = coyote_time
		_jump_consumed = false
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if _input_suppressed():
		_jump_buffer_timer = 0.0
		return
	if _action_just_pressed(&"jump"):
		_jump_buffer_timer = jump_buffer_time


func _handle_ground_actions(was_on_floor: bool) -> void:
	var crouch_pressed := _action_pressed(&"interact_down")
	if was_on_floor and crouch_pressed and _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_consumed = true
		if _is_on_one_way_platform():
			_start_drop_through()
		else:
			_set_state(State.CROUCH)
		return

	if was_on_floor and crouch_pressed:
		_set_state(State.CROUCH)
		return

	if current_state == State.CROUCH:
		if _can_stand():
			_set_state(State.IDLE)
		else:
			return

	if _can_consume_jump(was_on_floor):
		_consume_jump()


func _can_consume_jump(was_on_floor: bool) -> bool:
	if _jump_buffer_timer <= 0.0 or _jump_consumed:
		return false
	if current_state == State.CROUCH or current_state == State.ATTACK or current_state == State.HIT or current_state == State.DEAD:
		return false
	return was_on_floor or _coyote_timer > 0.0


func _consume_jump() -> void:
	velocity.y = jump_velocity
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jump_consumed = true
	_set_state(State.JUMP)


func _apply_horizontal_movement(delta: float, was_on_floor: bool) -> void:
	if current_state == State.CROUCH:
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		return

	var direction := _movement_axis()
	if current_state == State.ATTACK:
		var attack_target_velocity := direction * move_speed * _attack_walk_speed_multiplier()
		if was_on_floor:
			velocity.x = attack_target_velocity
		elif direction == 0.0:
			velocity.x = move_toward(velocity.x, 0.0, air_deceleration * delta)
		else:
			velocity.x = move_toward(velocity.x, attack_target_velocity, air_acceleration * delta)
		return

	if direction != 0.0:
		_facing_direction = direction
		_visual.set_facing_direction(_facing_direction)
	var speed := sprint_speed if direction != 0.0 and direction == _sprint_direction else move_speed
	var target_velocity := direction * speed

	if was_on_floor:
		var acceleration := ground_acceleration
		if direction == 0.0:
			acceleration = ground_deceleration
		elif velocity.x != 0.0 and signf(velocity.x) != direction:
			acceleration = ground_reversal_acceleration
		velocity.x = move_toward(velocity.x, target_velocity, acceleration * delta)
	elif direction == 0.0:
		velocity.x = move_toward(velocity.x, 0.0, air_deceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, target_velocity, air_acceleration * delta)


func _apply_vertical_movement(delta: float, was_on_floor: bool) -> void:
	if not was_on_floor:
		var gravity_scale := 1.0
		if velocity.y > 0.0:
			gravity_scale = fall_gravity_multiplier
		elif absf(velocity.y) <= apex_velocity_threshold:
			gravity_scale = apex_gravity_multiplier
		velocity.y = minf(velocity.y + gravity * gravity_scale * delta, maximum_fall_speed)

	if _action_just_released(&"jump") and velocity.y < jump_velocity * jump_cutoff_multiplier:
		velocity.y = jump_velocity * jump_cutoff_multiplier


func _handle_floor_transition(was_on_floor: bool, attack_started_on_floor_before_move: bool) -> void:
	var on_floor_now := is_on_floor()
	if not was_on_floor and on_floor_now:
		_handle_landing()
		return
	if was_on_floor and not on_floor_now and attack_started_on_floor_before_move:
		_air_attack_consumed = true


func _handle_landing() -> void:
	_jump_consumed = false
	_coyote_timer = coyote_time
	_air_attack_consumed = false


func _resolve_state() -> void:
	if current_state == State.ATTACK:
		return

	if not is_on_floor():
		_set_state(State.JUMP if velocity.y < 0.0 else State.FALL)
		return

	if _action_pressed(&"interact_down") or current_state == State.CROUCH and not _can_stand():
		_set_state(State.CROUCH)
		return

	if current_state == State.CROUCH:
		_set_state(State.IDLE)

	var direction := _movement_axis()
	if direction == 0.0:
		_set_state(State.IDLE)
	elif direction == _sprint_direction:
		_set_state(State.SPRINT)
	else:
		_set_state(State.WALK)


func _set_state(next_state: State) -> void:
	if current_state == next_state:
		return

	var was_crouched := current_state == State.CROUCH
	current_state = next_state
	var is_crouched := current_state == State.CROUCH

	if is_crouched:
		_sprint_direction = 0.0
		_last_left_press_time = _elapsed_time - double_tap_window - 1.0
		_last_right_press_time = _elapsed_time - double_tap_window - 1.0
		_jump_buffer_timer = 0.0
		velocity.x = 0.0

	if was_crouched != is_crouched:
		_set_crouched(is_crouched)


func _set_crouched(crouched: bool) -> void:
	_standing_collision.set_deferred("disabled", crouched)
	_crouching_collision.set_deferred("disabled", not crouched)
	_visual.set_crouched(crouched)


func _can_stand() -> bool:
	# Check only the extra headroom needed by the standing capsule. Querying the
	# whole standing shape also touches the floor and can trap the player crouched.
	var clearance_shape := RectangleShape2D.new()
	clearance_shape.size = Vector2(34.0, 28.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = clearance_shape
	query.transform = Transform2D(0.0, global_position + Vector2(0.0, -24.0))
	query.collision_mask = CROUCH_CLEARANCE_MASK
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _is_on_one_way_platform() -> bool:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		if collision.get_normal().y < -0.7:
			var collider := collision.get_collider() as CollisionObject2D
			if collider != null and collider.get_collision_layer_value(ONE_WAY_LAYER):
				return true
	return false


func _start_drop_through() -> void:
	_drop_through_timer = DROP_THROUGH_TIME
	set_collision_mask_value(ONE_WAY_LAYER, false)
	velocity.y = maxf(velocity.y, DROP_THROUGH_SPEED)
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jump_consumed = true
	_sprint_direction = 0.0
	_set_state(State.FALL)


func _update_drop_through(delta: float) -> void:
	if _drop_through_timer <= 0.0:
		return

	_drop_through_timer = maxf(_drop_through_timer - delta, 0.0)
	if _drop_through_timer == 0.0:
		set_collision_mask_value(ONE_WAY_LAYER, true)


func _clear_owned_projectiles() -> void:
	for projectile in get_tree().get_nodes_in_group("player_attack_projectile"):
		if projectile.has_method("get_source") and projectile.get_source() == self:
			projectile.queue_free()


func respawn(reason: RespawnReason = RespawnReason.DEATH) -> void:
	_cancel_attack()
	_clear_owned_projectiles()
	_air_attack_consumed = false
	global_position = _spawn_position
	velocity = Vector2.ZERO
	suppress_gameplay_input()
	_drop_through_timer = 0.0
	_next_light_attack_time = 0.0
	_next_heavy_attack_time = 0.0
	_skill_cooldowns.clear()
	_last_auto_attack_type = AttackType.HEAVY
	_current_attack_critical = false
	_health = get_max_health()
	_hit_stun_timer = 0.0
	_invulnerability_timer = 0.0
	_clear_hit_reaction_observability()
	_death_respawn_timer = 0.0
	_visual.clear_hurt_feedback()
	_hurtbox.enabled = true
	_hurtbox_collision.set_deferred("disabled", false)
	_visual.modulate = Color.WHITE
	set_collision_mask_value(ONE_WAY_LAYER, true)
	_set_state(State.IDLE)
	_set_crouched(false)
	health_changed.emit(_health, get_max_health())
	respawned.emit(reason)
