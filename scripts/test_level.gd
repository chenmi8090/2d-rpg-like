extends Node2D

const MATERIAL_PICKUP_SCENE := preload("res://scenes/items/material_pickup.tscn")
const EQUIPMENT_PICKUP_SCENE := preload("res://scenes/items/equipment_pickup.tscn")
const COMBAT_AUDIO_SERVICE_SCRIPT := preload("res://scripts/combat/combat_audio_service.gd")
const PLATFORM_COLOR := Color("42626b")
const PLATFORM_TOP_COLOR := Color("91b86d")
const MAP_LEFT := -370.0
const MAP_RIGHT := 3300.0
const HEALTH_BAR_WIDTH := 180.0
const EXPERIENCE_BAR_WIDTH := 180.0
const AREA_ID := &"test_level"
const SAFE_SPAWN_ID := &"start"
const SAFE_SPAWN_POSITION := Vector2(80.0, 550.0)

@onready var _player: Player = $Player
@onready var _drops: Node2D = $Drops
@onready var _platform_navigation: PlatformNavigationRegistry = $PlatformNavigation
@onready var _encounter_manager: EncounterManager = $EncounterManager
@onready var _health_fill: ColorRect = $Interface/HealthPanel/HealthFill
@onready var _health_text: Label = $Interface/HealthPanel/HealthText
@onready var _material_text: Label = $Interface/HealthPanel/MaterialText
@onready var _level_text: Label = $Interface/HealthPanel/LevelText
@onready var _experience_fill: ColorRect = $Interface/HealthPanel/ExpFill
@onready var _experience_text: Label = $Interface/HealthPanel/ExpText
@onready var _level_up_text: Label = $Interface/LevelUpText
@onready var _backpack_panel: Control = $Interface/BackpackPanel
@onready var _backpack_list: VBoxContainer = $Interface/BackpackPanel/ItemList
@onready var _backpack_empty_text: Label = $Interface/BackpackPanel/EmptyText
@onready var _backpack_detail_panel: Control = $Interface/BackpackPanel/DetailPanel
@onready var _backpack_detail_text: Label = $Interface/BackpackPanel/DetailPanel/DetailText
@onready var _backpack_feedback_text: Label = $Interface/BackpackPanel/FeedbackText
@onready var _attributes_panel: Control = $Interface/AttributesPanel
@onready var _attributes_text: Label = $Interface/AttributesPanel/StatsText
@onready var _profession_text: Label = $Interface/AttributesPanel/ProfessionText
@onready var _equipment_list: VBoxContainer = $Interface/AttributesPanel/EquipmentList
@onready var _equipment_detail_panel: Control = $Interface/AttributesPanel/EquipmentDetailPanel
@onready var _equipment_detail_text: Label = $Interface/AttributesPanel/EquipmentDetailPanel/DetailText
@onready var _character_name_text: Label = $Interface/AttributesPanel/CharacterNameText
@onready var _return_button: Button = $Interface/SessionPanel/ReturnButton
@onready var _save_status_text: Label = $Interface/SessionPanel/SaveStatusText
@onready var _return_status_text: Label = $Interface/SessionPanel/ReturnStatusText

var _rng := RandomNumberGenerator.new()
var _connected_enemies: Dictionary = {}
var _equipment_rows: Dictionary = {}
var _hovered_equipment_slot: StringName = &""
var _hovered_backpack_item: EquipmentDefinition
var _level_up_tween: Tween
var _combat_audio_service: CombatAudioService


func _ready() -> void:
	_ensure_combat_audio_service()
	_build_course()
	_register_platform_navigation()
	_rng.randomize()
	_setup_equipment_rows()
	_player.respawned.connect(_on_player_respawned)
	_player.health_changed.connect(_update_player_health)
	_player.material_changed.connect(_update_material_count)
	_player.progression_changed.connect(_update_player_progression)
	_player.level_up.connect(_show_level_up)
	_player.stats_changed.connect(_update_attributes_panel)
	_player.equipment_changed.connect(_on_player_equipment_changed)
	_player.equipment_inventory_changed.connect(_update_backpack_panel)
	_player.equipment_equip_failed.connect(_on_equipment_equip_failed)
	_encounter_manager.experience_reward_accepted.connect(_on_experience_reward_accepted)
	_return_button.pressed.connect(_on_return_button_pressed)
	GameSession.save_status_changed.connect(_on_save_status_changed)
	GameSession.return_countdown_changed.connect(_on_return_countdown_changed)
	var bind_result := GameSession.bind_level(self, _player)
	if not bind_result.ok:
		_on_save_status_changed(String(bind_result.message), true)
	_update_player_health(_player.get_health(), _player.get_max_health())
	_update_material_count(_player.get_stardust_fragments())
	_update_player_progression(_player.get_level(), _player.get_experience(), _player.get_experience_requirement(), _player.is_max_level())
	_update_attributes_panel()
	_update_equipment_panel()
	_update_backpack_panel()
	_connect_enemy_drop_sources()
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if GameSession.save_status_changed.is_connected(_on_save_status_changed):
		GameSession.save_status_changed.disconnect(_on_save_status_changed)
	if GameSession.return_countdown_changed.is_connected(_on_return_countdown_changed):
		GameSession.return_countdown_changed.disconnect(_on_return_countdown_changed)
	GameSession.unbind_level(self)


func get_area_id() -> StringName:
	return AREA_ID


func get_safe_spawn_position(spawn_id: StringName) -> Vector2:
	return SAFE_SPAWN_POSITION if spawn_id == SAFE_SPAWN_ID else Vector2.INF


func _ensure_combat_audio_service() -> void:
	if _combat_audio_service != null and is_instance_valid(_combat_audio_service):
		return
	_combat_audio_service = get_node_or_null("CombatAudioService") as CombatAudioService
	if _combat_audio_service == null:
		_combat_audio_service = COMBAT_AUDIO_SERVICE_SCRIPT.new() as CombatAudioService
		_combat_audio_service.name = "CombatAudioService"
		add_child(_combat_audio_service)
	if not _combat_audio_service.is_in_group("combat_audio_service"):
		_combat_audio_service.add_to_group("combat_audio_service")
	_combat_audio_service.cleanup_owner(_player)


func is_combat_active() -> bool:
	for enemy in _encounter_manager.get_owned_enemies():
		if enemy != null and is_instance_valid(enemy) and enemy.is_engaged_with_target():
			return true
	return false


func _on_return_button_pressed() -> void:
	var result := GameSession.request_return_to_list()
	if not result.ok:
		_return_status_text.text = String(result.message)


func _on_save_status_changed(message: String, failed: bool) -> void:
	_save_status_text.text = message
	_save_status_text.modulate = Color("ff916f") if failed else Color("e8d579")


func _on_return_countdown_changed(message: String, active: bool) -> void:
	_return_status_text.text = message
	_return_button.disabled = active


func _on_player_respawned(reason: Player.RespawnReason) -> void:
	if reason != Player.RespawnReason.MANUAL_RESET:
		return
	_clear_drops()
	_encounter_manager.reset_encounter()


func _on_experience_reward_accepted(amount: int, _enemy: GroundedEnemyController, credited_player: Player, _group_index: int, _spawn_index: int) -> void:
	if credited_player == _player:
		_player.add_experience(amount)


func _clear_drops() -> void:
	for drop in _drops.get_children():
		if drop.has_method("deactivate"):
			drop.deactivate()
		drop.queue_free()


func _connect_enemy_drop_sources() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_connect_enemy_drop_source(enemy)


func _connect_enemy_drop_source(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	_ensure_combat_audio_service()
	if _combat_audio_service != null:
		_combat_audio_service.cleanup_owner(enemy)
	if _connected_enemies.has(enemy) or not enemy.has_signal("drop_requested"):
		return
	enemy.connect("drop_requested", _on_enemy_drop_requested)
	if enemy.has_signal("equipment_drop_requested"):
		enemy.connect("equipment_drop_requested", _on_enemy_equipment_drop_requested)
	_connected_enemies[enemy] = true
	enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy), CONNECT_ONE_SHOT)


func _on_enemy_tree_exited(enemy: Node) -> void:
	_connected_enemies.erase(enemy)
	if _combat_audio_service != null:
		_combat_audio_service.cleanup_owner(enemy)


func _on_node_added(node: Node) -> void:
	if node.is_in_group("enemy"):
		_connect_enemy_drop_source.call_deferred(node)


func _on_enemy_drop_requested(enemy: GroundedEnemyController, drop_rules: Array[EnemyDropRule]) -> void:
	for rule in drop_rules:
		var amount := _roll_drop_amount(rule)
		for index in amount:
			_spawn_pickup(rule.collectible, enemy.global_position, index, amount)


func _roll_drop_amount(rule: EnemyDropRule) -> int:
	if rule == null or rule.collectible == null:
		return 0
	if _rng.randf() > clampf(rule.chance, 0.0, 1.0):
		return 0
	var minimum := maxi(rule.min_amount, 0)
	var maximum := maxi(rule.max_amount, minimum)
	return _rng.randi_range(minimum, maximum)


func _spawn_pickup(definition: CollectibleDefinition, origin: Vector2, index: int, total: int) -> void:
	if definition == null:
		return
	var pickup := MATERIAL_PICKUP_SCENE.instantiate() as MaterialPickup
	_drops.add_child(pickup)
	pickup.global_position = origin + Vector2(0.0, -34.0)
	var fan := 0.0
	if total > 1:
		fan = lerpf(-90.0, 90.0, float(index) / float(total - 1))
	var launch_velocity := Vector2(
		fan + _rng.randf_range(-45.0, 45.0),
		_rng.randf_range(-460.0, -340.0)
	)
	pickup.initialize(definition, 1, launch_velocity)


func _on_enemy_equipment_drop_requested(enemy: GroundedEnemyController, drop_rules: Array[EquipmentDropRule]) -> void:
	for rule in drop_rules:
		var amount := _roll_equipment_drop_amount(rule)
		for index in amount:
			_spawn_equipment_pickup(rule.equipment, enemy.global_position, index, amount)


func _roll_equipment_drop_amount(rule: EquipmentDropRule) -> int:
	if rule == null or rule.equipment == null:
		return 0
	if _rng.randf() > clampf(rule.chance, 0.0, 1.0):
		return 0
	var minimum := maxi(rule.min_amount, 0)
	var maximum := maxi(rule.max_amount, minimum)
	return _rng.randi_range(minimum, maximum)


func _spawn_equipment_pickup(definition: EquipmentDefinition, origin: Vector2, index: int, total: int) -> void:
	if definition == null:
		return
	var pickup := EQUIPMENT_PICKUP_SCENE.instantiate() as EquipmentPickup
	_drops.add_child(pickup)
	pickup.global_position = origin + Vector2(0.0, -34.0)
	var fan := 0.0
	if total > 1:
		fan = lerpf(-90.0, 90.0, float(index) / float(total - 1))
	pickup.initialize(definition, 1, Vector2(fan + _rng.randf_range(-45.0, 45.0), _rng.randf_range(-460.0, -340.0)))


func _update_player_health(current: int, maximum: int) -> void:
	var ratio := 0.0 if maximum <= 0 else clampf(float(current) / float(maximum), 0.0, 1.0)
	_health_fill.size.x = HEALTH_BAR_WIDTH * ratio
	_health_text.text = "生命 %d / %d" % [current, maximum]


func _update_material_count(total: int) -> void:
	_material_text.text = "星尘碎片 × %d" % total


func _update_player_progression(level: int, current_experience: int, required_experience: int, maximum_level_reached: bool) -> void:
	_level_text.text = "等级 %d" % level
	if maximum_level_reached:
		_experience_fill.size.x = EXPERIENCE_BAR_WIDTH
		_experience_text.text = "经验已满"
		return
	var ratio := 0.0 if required_experience <= 0 else clampf(float(current_experience) / float(required_experience), 0.0, 1.0)
	_experience_fill.size.x = EXPERIENCE_BAR_WIDTH * ratio
	_experience_text.text = "经验 %d / %d" % [current_experience, required_experience]


func _show_level_up(level: int, _levels_gained: int) -> void:
	if _level_up_tween != null and _level_up_tween.is_valid():
		_level_up_tween.kill()
	_level_up_text.text = "升级！ 等级 %d" % level
	_level_up_text.visible = true
	_level_up_text.modulate.a = 1.0
	_level_up_text.scale = Vector2(0.9, 0.9)
	_level_up_tween = create_tween()
	_level_up_tween.tween_property(_level_up_text, "scale", Vector2(1.15, 1.15), 0.18)
	_level_up_tween.tween_interval(0.55)
	_level_up_tween.tween_property(_level_up_text, "modulate:a", 0.0, 0.3)
	_level_up_tween.tween_callback(func() -> void: _level_up_text.visible = false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if event is InputEventKey and event.echo:
			return
		_set_attributes_panel_visible(false)
		_set_backpack_panel_visible(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_attributes"):
		if event is InputEventKey and event.echo:
			return
		_set_attributes_panel_visible(not _attributes_panel.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_backpack"):
		if event is InputEventKey and event.echo:
			return
		_set_backpack_panel_visible(not _backpack_panel.visible)
		get_viewport().set_input_as_handled()


func _set_backpack_panel_visible(visible: bool) -> void:
	_backpack_panel.visible = visible
	_hide_backpack_detail()
	_backpack_feedback_text.text = ""
	if visible:
		_update_backpack_panel()


func _set_attributes_panel_visible(visible: bool) -> void:
	_attributes_panel.visible = visible
	_hide_equipment_detail()
	if visible:
		_update_attributes_panel()
		_update_equipment_panel()


func _setup_equipment_rows() -> void:
	var row_names: Array[StringName] = [
		&"WeaponRow",
		&"HeadRow",
		&"BodyRow",
		&"LegsRow",
		&"GlovesRow",
		&"ShoesRow",
		&"RingRow",
	]
	for index in EquipmentSlot.ALL.size():
		var slot: StringName = EquipmentSlot.ALL[index]
		var row := _equipment_list.get_node(String(row_names[index])) as Button
		_equipment_rows[slot] = row
		row.set_meta(&"equipment_slot", slot)
		row.mouse_entered.connect(_on_equipment_row_entered.bind(slot))
		row.mouse_exited.connect(_on_equipment_row_exited.bind(slot))


func _update_attributes_panel() -> void:
	_character_name_text.text = "角色：%s" % (GameSession.get_active_character_name() if GameSession.has_active_profile() else "测试角色")
	_attributes_text.text = "\n".join([
		"力量：%s" % _format_stat(_player.get_stat(PlayerStats.STRENGTH)),
		"精神：%s" % _format_stat(_player.get_stat(PlayerStats.SPIRIT)),
		"体魄：%s" % _format_stat(_player.get_stat(PlayerStats.VITALITY)),
		"技巧：%s" % _format_stat(_player.get_stat(PlayerStats.TECHNIQUE)),
		"",
		"最大生命：%d" % _player.get_max_health(),
		"物理攻击：%s" % _format_stat(_player.get_stat(PlayerStats.PHYSICAL_ATTACK)),
		"魔法攻击：%s" % _format_stat(_player.get_stat(PlayerStats.MAGIC_ATTACK)),
		"物理防御：%s" % _format_stat(_player.get_stat(PlayerStats.PHYSICAL_DEFENSE)),
		"暴击率：%s" % _format_percent(_player.get_stat(PlayerStats.CRITICAL_CHANCE)),
		"暴击伤害：%s" % _format_percent(_player.get_stat(PlayerStats.CRITICAL_DAMAGE)),
	])


func _update_equipment_panel() -> void:
	_profession_text.text = "职业：%s" % _player.get_profession_name()
	for slot in EquipmentSlot.ALL:
		var row := _equipment_rows.get(slot) as Button
		if row == null:
			continue
		var definition := _player.get_equipped_item(slot)
		var item_name := definition.display_name if definition != null else "未装备"
		row.text = "%s：%s" % [EquipmentSlot.display_name(slot), item_name]
		row.disabled = definition == null
	if _hovered_equipment_slot != &"":
		_show_equipment_detail(_hovered_equipment_slot)


func _on_equipment_row_entered(slot: StringName) -> void:
	_hovered_equipment_slot = slot
	_show_equipment_detail(slot)


func _on_equipment_row_exited(slot: StringName) -> void:
	if _hovered_equipment_slot == slot:
		_hide_equipment_detail()


func _show_equipment_detail(slot: StringName) -> void:
	var definition := _player.get_equipped_item(slot)
	if definition == null:
		_hide_equipment_detail()
		return
	_equipment_detail_text.text = EquipmentTextFormatter.format_equipment_detail(definition)
	_equipment_detail_panel.visible = true


func _hide_equipment_detail() -> void:
	_hovered_equipment_slot = &""
	_equipment_detail_panel.visible = false
	_equipment_detail_text.text = ""


func _format_equipment_detail(definition: EquipmentDefinition) -> String:
	var lines: Array[String] = [
		definition.display_name,
		"部位：%s" % EquipmentSlot.display_name(definition.slot),
	]
	if definition.is_weapon():
		lines.append("类型：%s" % _weapon_type_display_name(definition.weapon_type))
	lines.append("")
	lines.append("属性加成")
	var aggregated := _aggregate_modifiers(definition.modifiers)
	if aggregated.is_empty():
		lines.append("无属性加成")
		return "\n".join(lines)
	for stat_key in _stat_display_order():
		if not aggregated.has(stat_key):
			continue
		var totals := aggregated[stat_key] as Vector2
		lines.append(_format_modifier_line(stat_key, totals.x, totals.y))
	return "\n".join(lines)


func _aggregate_modifiers(modifiers: Array[StatModifier]) -> Dictionary:
	var totals: Dictionary = {}
	for modifier in modifiers:
		if modifier == null:
			continue
		var current := totals.get(modifier.stat_key, Vector2.ZERO) as Vector2
		current.x += modifier.flat_bonus
		current.y += modifier.percent_bonus
		totals[modifier.stat_key] = current
	return totals


func _format_modifier_line(stat_key: StringName, flat_bonus: float, percent_bonus: float) -> String:
	var parts: Array[String] = []
	if not is_zero_approx(flat_bonus):
		if stat_key == PlayerStats.CRITICAL_CHANCE or stat_key == PlayerStats.CRITICAL_DAMAGE:
			parts.append("%s 个百分点" % _format_signed_number(flat_bonus * 100.0))
		else:
			parts.append(_format_signed_number(flat_bonus))
	if not is_zero_approx(percent_bonus):
		parts.append("百分比 %s%%" % _format_signed_number(percent_bonus * 100.0))
	if parts.is_empty():
		parts.append("0")
	return "%s：%s" % [_stat_display_name(stat_key), "；".join(parts)]


func _format_signed_number(value: float) -> String:
	var formatted := _format_stat(absf(value))
	return "%s%s" % ["+" if value >= 0.0 else "-", formatted]


func _stat_display_order() -> Array[StringName]:
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


func _stat_display_name(stat_key: StringName) -> String:
	match stat_key:
		PlayerStats.STRENGTH:
			return "力量"
		PlayerStats.SPIRIT:
			return "精神"
		PlayerStats.VITALITY:
			return "体魄"
		PlayerStats.TECHNIQUE:
			return "技巧"
		PlayerStats.MAX_HEALTH:
			return "最大生命"
		PlayerStats.PHYSICAL_ATTACK:
			return "物理攻击"
		PlayerStats.MAGIC_ATTACK:
			return "魔法攻击"
		PlayerStats.PHYSICAL_DEFENSE:
			return "物理防御"
		PlayerStats.CRITICAL_CHANCE:
			return "暴击率"
		PlayerStats.CRITICAL_DAMAGE:
			return "暴击伤害"
	return "未知属性"


func _weapon_type_display_name(weapon_type: StringName) -> String:
	match weapon_type:
		WeaponType.SWORD:
			return "剑"
		WeaponType.STAFF:
			return "法杖"
		WeaponType.BOW:
			return "弓"
		WeaponType.DAGGER:
			return "匕首"
	return "未知"


func _on_player_equipment_changed() -> void:
	_update_equipment_panel()
	_update_attributes_panel()
	_update_backpack_panel()


func _update_backpack_panel() -> void:
	for child in _backpack_list.get_children():
		child.queue_free()
	var inventory := _player.get_equipment_inventory()
	var items: Array[EquipmentDefinition] = []
	for key in inventory:
		if key is EquipmentDefinition and int(inventory[key]) > 0:
			items.append(key as EquipmentDefinition)
	items.sort_custom(func(first: EquipmentDefinition, second: EquipmentDefinition) -> bool: return first.display_name < second.display_name)
	_backpack_empty_text.visible = items.is_empty()
	for definition in items:
		var row := Button.new()
		row.custom_minimum_size = Vector2(248.0, 34.0)
		row.focus_mode = Control.FOCUS_NONE
		row.text = "%s × %d" % [definition.display_name, _player.get_equipment_count(definition)]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.set_meta(&"equipment_definition", definition)
		row.mouse_entered.connect(_on_backpack_item_entered.bind(definition))
		row.mouse_exited.connect(_on_backpack_item_exited.bind(definition))
		row.pressed.connect(_on_backpack_item_pressed.bind(definition))
		_backpack_list.add_child(row)
	if _hovered_backpack_item != null and _player.get_equipment_count(_hovered_backpack_item) > 0:
		_show_backpack_detail(_hovered_backpack_item)
	else:
		_hide_backpack_detail()


func _on_backpack_item_entered(definition: EquipmentDefinition) -> void:
	_hovered_backpack_item = definition
	_show_backpack_detail(definition)


func _on_backpack_item_exited(definition: EquipmentDefinition) -> void:
	if _hovered_backpack_item == definition:
		_hide_backpack_detail()


func _on_backpack_item_pressed(definition: EquipmentDefinition) -> void:
	if _player.equip_inventory_item(definition):
		_backpack_feedback_text.text = "已装备：%s" % definition.display_name


func _on_equipment_equip_failed(message: String) -> void:
	_backpack_feedback_text.text = "无法装备：%s" % message


func _show_backpack_detail(definition: EquipmentDefinition) -> void:
	if definition == null or _player.get_equipment_count(definition) <= 0:
		_hide_backpack_detail()
		return
	_backpack_detail_text.text = EquipmentTextFormatter.format_backpack_comparison(definition, _player.preview_equipment_stats(definition))
	_backpack_detail_panel.visible = true


func _hide_backpack_detail() -> void:
	_hovered_backpack_item = null
	_backpack_detail_panel.visible = false
	_backpack_detail_text.text = ""


func _format_stat(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value


func _format_percent(value: float) -> String:
	return "%s%%" % _format_stat(value * 100.0)


func _register_platform_navigation() -> void:
	_platform_navigation.clear()
	_platform_navigation.register_surface(&"ground", -400.0, 3300.0, 640.0, false, true)
	_platform_navigation.register_surface(&"p1", 370.0, 670.0, 554.0, true)
	_platform_navigation.register_surface(&"p2", 770.0, 1030.0, 484.0, true)
	_platform_navigation.register_surface(&"p3", 1110.0, 1430.0, 539.0, true)
	_platform_navigation.register_surface(&"p4", 1530.0, 1830.0, 459.0, true)
	_platform_navigation.register_surface(&"p5", 1920.0, 2260.0, 529.0, true)
	_platform_navigation.register_surface(&"p6", 2360.0, 2660.0, 439.0, true)
	_platform_navigation.add_bidirectional_link(&"ground", &"p1")
	_platform_navigation.add_bidirectional_link(&"p1", &"p2")
	_platform_navigation.add_bidirectional_link(&"p2", &"p3")
	_platform_navigation.add_bidirectional_link(&"ground", &"p3")
	_platform_navigation.add_bidirectional_link(&"p3", &"p4")
	_platform_navigation.add_bidirectional_link(&"p4", &"p5")
	_platform_navigation.add_bidirectional_link(&"ground", &"p5")
	_platform_navigation.add_bidirectional_link(&"p5", &"p6")


func _build_course() -> void:
	# Every map keeps a continuous floor and solid left/right limits.
	_create_platform(Vector2(1450, 680), Vector2(3700, 80), false)
	_create_map_boundary(MAP_LEFT)
	_create_map_boundary(MAP_RIGHT)

	# Upper platforms allow passage from below and support actors landing from above.
	_create_platform(Vector2(520, 570), Vector2(300, 32), true)
	_create_platform(Vector2(900, 500), Vector2(260, 32), true)
	_create_platform(Vector2(1270, 555), Vector2(320, 32), true)
	_create_platform(Vector2(1680, 475), Vector2(300, 32), true)
	_create_platform(Vector2(2090, 545), Vector2(340, 32), true)
	_create_platform(Vector2(2510, 455), Vector2(300, 32), true)


func _create_map_boundary(x_position: float) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x_position, 0.0)
	body.collision_layer = 1
	body.collision_mask = 2
	$Platforms.add_child(body)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40.0, 4000.0)
	collision.position = Vector2(0.0, -1000.0)
	collision.shape = shape
	body.add_child(collision)


func _create_platform(center: Vector2, size: Vector2, one_way: bool) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 4 if one_way else 1
	body.collision_mask = 2
	$Platforms.add_child(body)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	collision.one_way_collision = one_way
	collision.one_way_collision_margin = 12.0
	body.add_child(collision)

	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, size.y / 2.0),
		Vector2(-size.x / 2.0, size.y / 2.0),
	])
	base.color = PLATFORM_COLOR
	body.add_child(base)

	var top := Polygon2D.new()
	top.polygon = PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, -size.y / 2.0 + 8.0),
		Vector2(-size.x / 2.0, -size.y / 2.0 + 8.0),
	])
	top.color = PLATFORM_TOP_COLOR
	body.add_child(top)
