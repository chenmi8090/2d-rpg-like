extends Node2D

const MATERIAL_PICKUP_SCENE := preload("res://scenes/items/material_pickup.tscn")
const EQUIPMENT_PICKUP_SCENE := preload("res://scenes/items/equipment_pickup.tscn")
const UI_STYLE := preload("res://scripts/ui/ui_style.gd")
const SKILL_DRAG_BUTTON := preload("res://scripts/ui/skill_drag_button.gd")
const SKILL_QUICKBAR_SLOT := preload("res://scripts/ui/skill_quickbar_slot.gd")
const BACKPACK_SLOT_BUTTON := preload("res://scripts/ui/backpack_slot_button.gd")
const PLATFORM_COLOR := Color("42626b")
const PLATFORM_TOP_COLOR := Color("91b86d")
const MAP_LEFT := -370.0
const MAP_RIGHT := 3300.0
const HEALTH_BAR_WIDTH := 180.0
const EXPERIENCE_BAR_WIDTH := 180.0
const DEFAULT_MAP_ID := &"test_level"
const DEFAULT_ENTRY_ID := &"start"
const PORTAL_REARM_DISTANCE := 112.0
const REMINDER_DURATION := 2.5
const BACKPACK_COLUMNS := 10
const SELECTED_COLOR := Color("ffe17a")

@onready var _player: Player = $Player
@onready var _map_root: Node2D = $MapRoot
@onready var _platforms: Node2D = $Platforms
@onready var _world_markers: Node2D = $WorldMarkers
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
@onready var _skill_quickbar_hud: Control = $Interface/SkillQuickbarHUD
@onready var _skill_quickbar_rows: Array[HBoxContainer] = [
	$Interface/SkillQuickbarHUD/Rows/Row1,
	$Interface/SkillQuickbarHUD/Rows/Row2,
]
var _skill_hud_slots: Array[SkillQuickbarSlot] = []
var _skill_hud_names: Array[Label] = []
var _skill_hud_statuses: Array[Label] = []
@onready var _backpack_panel: Control = $Interface/BackpackPanel
@onready var _backpack_scroll: ScrollContainer = $Interface/BackpackPanel/ItemScroll
@onready var _backpack_list: GridContainer = $Interface/BackpackPanel/ItemScroll/ItemList
@onready var _backpack_hint_text: Label = $Interface/BackpackPanel/HintText
@onready var _backpack_tab_buttons: Dictionary = {
	BackpackCategory.EQUIPMENT: $Interface/BackpackPanel/Tabs/Equipment,
	BackpackCategory.CONSUMABLE: $Interface/BackpackPanel/Tabs/Consumable,
	BackpackCategory.OTHER: $Interface/BackpackPanel/Tabs/Other,
	BackpackCategory.QUEST: $Interface/BackpackPanel/Tabs/Quest,
}
@onready var _backpack_detail_panel: Control = $Interface/BackpackPanel/DetailPanel
@onready var _backpack_detail_text: Label = $Interface/BackpackPanel/DetailPanel/DetailText
@onready var _backpack_feedback_text: Label = $Interface/BackpackPanel/FeedbackText
@onready var _discard_confirmation: Control = $Interface/BackpackPanel/DiscardConfirmation
@onready var _discard_confirmation_text: Label = $Interface/BackpackPanel/DiscardConfirmation/Panel/ItemText
@onready var _attributes_panel: Control = $Interface/AttributesPanel
@onready var _attributes_text: Label = $Interface/AttributesPanel/StatsText
@onready var _profession_text: Label = $Interface/AttributesPanel/ProfessionText
@onready var _equipment_list: VBoxContainer = $Interface/AttributesPanel/EquipmentList
@onready var _equipment_detail_panel: Control = $Interface/AttributesPanel/EquipmentDetailPanel
@onready var _equipment_detail_text: Label = $Interface/AttributesPanel/EquipmentDetailPanel/DetailText
@onready var _character_name_text: Label = $Interface/AttributesPanel/CharacterNameText
@onready var _skills_panel: Control = $Interface/SkillsPanel
@onready var _skills_points_text: Label = $Interface/SkillsPanel/PointsText
@onready var _skills_scroll: ScrollContainer = $Interface/SkillsPanel/SkillScroll
@onready var _skills_list: VBoxContainer = $Interface/SkillsPanel/SkillScroll/SkillList
@onready var _skills_empty_text: Label = $Interface/SkillsPanel/EmptyText
@onready var _skills_detail_text: Label = $Interface/SkillsPanel/DetailPanel/DetailText
@onready var _skills_decrease_button: Button = $Interface/SkillsPanel/DetailPanel/DecreaseButton
@onready var _skills_increase_button: Button = $Interface/SkillsPanel/DetailPanel/IncreaseButton
@onready var _skills_feedback_text: Label = $Interface/SkillsPanel/FeedbackText
@onready var _return_button: Button = $Interface/SessionPanel/ReturnButton
@onready var _save_status_text: Label = $Interface/SessionPanel/SaveStatusText
@onready var _return_status_text: Label = $Interface/SessionPanel/ReturnStatusText
@onready var _map_title_text: Label = $Interface/MapTitle
@onready var _interaction_prompt_text: Label = $Interface/InteractionPrompt
@onready var _world_status_text: Label = $Interface/WorldStatus

var _map_definition: MapDefinition
var _map_layout: Node2D
var _active_portal: PortalDefinition
var _active_checkpoint: CheckpointDefinition
var _locked_portal_ids: Dictionary = {}
var _portal_transition_locked := false
var _portal_rearm_position := Vector2.INF
var _rng := RandomNumberGenerator.new()
var _connected_enemies: Dictionary = {}
var _equipment_rows: Dictionary = {}
var _hovered_equipment_slot: StringName = &""
var _selected_equipment_slot: StringName = &""
var _hovered_backpack_instance_id := ""
var _selected_backpack_instance_id := ""
var _selected_backpack_index_hint := -1
var _sorted_backpack_items: Array[EquipmentInstance] = []
var _backpack_buttons_by_id: Dictionary = {}
var _backpack_slot_buttons: Array[BackpackSlotButton] = []
var _backpack_category: StringName = BackpackCategory.EQUIPMENT
var _selected_stack_index := -1
var _hovered_stack_index := -1
var _pending_discard_instance_id := ""
var _pending_discard_index := -1
var _selected_skill_id: StringName = &""
var _profession_skills: Array[SkillDefinition] = []
var _skill_buttons_by_id: Dictionary = {}
var _skill_hud_states: Array[StringName] = []
var _level_up_tween: Tween
var _reminder_versions: Dictionary = {}


func _ready() -> void:
	_setup_skill_quickbar_hud()
	_setup_backpack_tabs()
	_apply_ui_foundation()
	_rng.randomize()
	var initial_map_result := load_world_map(DEFAULT_MAP_ID, DEFAULT_ENTRY_ID)
	if not initial_map_result.ok:
		_on_save_status_changed(String(initial_map_result.message), true)
	_setup_equipment_rows()
	_player.respawned.connect(_on_player_respawned)
	_player.health_changed.connect(_update_player_health)
	_player.material_changed.connect(_update_material_count)
	_player.progression_changed.connect(_update_player_progression)
	_player.level_up.connect(_show_level_up)
	_player.stats_changed.connect(_update_attributes_panel)
	_player.equipment_changed.connect(_on_player_equipment_changed)
	_player.equipment_changed.connect(_update_skill_quickbar_hud)
	_player.equipment_inventory_changed.connect(_update_backpack_panel)
	_player.stackable_inventory_changed.connect(_update_backpack_panel)
	_player.equipment_equip_failed.connect(_on_equipment_equip_failed)
	_player.skills_changed.connect(_update_skills_panel)
	_player.skills_changed.connect(_update_skill_quickbar_hud)
	_skills_decrease_button.pressed.connect(_decrease_selected_skill_rank)
	_skills_increase_button.pressed.connect(_increase_selected_skill_rank)
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
	_update_skills_panel()
	_update_skill_quickbar_hud()
	_connect_enemy_drop_sources()
	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	_update_world_interaction()
	_update_skill_quickbar_hud()


func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.set_gameplay_input_blocked(false)
	if GameSession.save_status_changed.is_connected(_on_save_status_changed):
		GameSession.save_status_changed.disconnect(_on_save_status_changed)
	if GameSession.return_countdown_changed.is_connected(_on_return_countdown_changed):
		GameSession.return_countdown_changed.disconnect(_on_return_countdown_changed)
	GameSession.unbind_level(self)


func get_area_id() -> StringName:
	return _map_definition.id if _map_definition != null else DEFAULT_MAP_ID


func get_safe_spawn_position(spawn_id: StringName) -> Vector2:
	if _map_definition == null:
		return Vector2.INF
	var entry := _map_definition.get_entry(spawn_id)
	return entry.position if entry != null else Vector2.INF


func load_world_map(
	map_id: StringName,
	entry_id: StringName,
	preserve_player_horizontal_movement := false
) -> Dictionary:
	var definition := DefinitionRegistry.get_map(map_id)
	if definition == null:
		return {"ok": false, "message": "地图定义无效"}
	var entry := definition.get_entry(entry_id)
	if entry == null:
		entry = definition.get_entry(definition.default_entry_id)
	if entry == null:
		return {"ok": false, "message": "地图入口无效"}
	var packed_scene := load(definition.scene_path) as PackedScene
	if packed_scene == null:
		return {"ok": false, "message": "地图场景无法载入"}
	var new_layout := packed_scene.instantiate() as Node2D
	if new_layout == null:
		return {"ok": false, "message": "地图场景根节点无效"}
	_encounter_manager.clear_encounter()
	_clear_drops()
	_clear_world_map()
	_map_definition = definition
	_map_layout = new_layout
	_map_root.add_child(_map_layout)
	_build_course_from_layout(_map_layout)
	_build_world_markers()
	_configure_player_camera(definition.camera_bounds)
	_player.apply_safe_spawn(entry.position, preserve_player_horizontal_movement)
	_player.set_facing_direction(entry.facing_direction)
	_encounter_manager.load_encounter(definition.encounter_definition, false)
	_map_title_text.text = "%s / %s" % [
		DefinitionRegistry.get_region(definition.region_id).display_name,
		definition.display_name,
	]
	_portal_transition_locked = true
	_portal_rearm_position = entry.position
	_interaction_prompt_text.visible = false
	_world_status_text.text = ""
	return {"ok": true, "message": ""}


func set_portal_condition(condition_id: StringName, unlocked: bool) -> void:
	if condition_id == &"":
		return
	if unlocked:
		_locked_portal_ids.erase(condition_id)
	else:
		_locked_portal_ids[condition_id] = true


func is_combat_active() -> bool:
	for enemy in _encounter_manager.get_owned_enemies():
		if enemy != null and is_instance_valid(enemy) and enemy.is_engaged_with_target():
			return true
	return false


func _show_reminder(label: Label, message: String, duration := REMINDER_DURATION) -> void:
	if label == null:
		return
	label.text = message
	var version := int(_reminder_versions.get(label, 0)) + 1
	_reminder_versions[label] = version
	if message.is_empty() or duration <= 0.0:
		return
	_clear_reminder_after_delay(label, version, duration)


func _clear_reminder_after_delay(label: Label, version: int, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(label) or int(_reminder_versions.get(label, 0)) != version:
		return
	label.text = ""


func _on_return_button_pressed() -> void:
	var result := GameSession.request_return_to_list()
	if not result.ok:
		_show_reminder(_return_status_text, String(result.message))


func _on_save_status_changed(message: String, failed: bool) -> void:
	_show_reminder(_save_status_text, message)
	_save_status_text.modulate = Color("ff916f") if failed else Color("e8d579")


func _on_return_countdown_changed(message: String, active: bool) -> void:
	_show_reminder(_return_status_text, message, 0.0 if active else REMINDER_DURATION)
	_return_button.disabled = active


func _on_player_respawned(reason: Player.RespawnReason) -> void:
	if reason == Player.RespawnReason.DEATH and GameSession.has_active_profile():
		_recover_from_checkpoint.call_deferred()
		return
	if reason != Player.RespawnReason.MANUAL_RESET:
		return
	_clear_drops()
	_encounter_manager.reset_encounter()


func _recover_from_checkpoint() -> void:
	var respawn := GameSession.get_respawn_location()
	var map_id := StringName(String(respawn.get("map_id", DEFAULT_MAP_ID)))
	var entry_id := StringName(String(respawn.get("entry_id", DEFAULT_ENTRY_ID)))
	var result := load_world_map(map_id, entry_id)
	if not result.ok:
		_show_reminder(_world_status_text, String(result.message))
		return
	_show_reminder(_world_status_text, "已从复活点恢复")


func _on_experience_reward_accepted(amount: int, _enemy: GroundedEnemyController, credited_player: Player, _group_index: int, _spawn_index: int) -> void:
	if credited_player == _player:
		_player.add_experience(amount)


func _clear_drops() -> void:
	for drop in _drops.get_children():
		if drop.has_method("deactivate"):
			drop.deactivate()
		if drop.get_parent() != null:
			drop.get_parent().remove_child(drop)
		drop.queue_free()


func _connect_enemy_drop_sources() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_connect_enemy_drop_source(enemy)


func _connect_enemy_drop_source(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	if _connected_enemies.has(enemy) or not enemy.has_signal("drop_requested"):
		return
	enemy.connect("drop_requested", _on_enemy_drop_requested)
	if enemy.has_signal("equipment_drop_requested"):
		enemy.connect("equipment_drop_requested", _on_enemy_equipment_drop_requested)
	_connected_enemies[enemy] = true
	enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy), CONNECT_ONE_SHOT)


func _on_enemy_tree_exited(enemy: Node) -> void:
	_connected_enemies.erase(enemy)


func _on_node_added(node: Node) -> void:
	if node.is_in_group("enemy"):
		_connect_enemy_drop_source.call_deferred(node)


func _on_enemy_drop_requested(enemy: GroundedEnemyController, drop_rules: Array[EnemyDropRule]) -> void:
	if not _encounter_manager.owns_enemy(enemy):
		return
	for rule in drop_rules:
		var amount := _roll_drop_amount(rule)
		for index in amount:
			_spawn_pickup(rule.collectible, enemy.global_position, index, amount)


func _roll_drop_amount(rule: EnemyDropRule) -> int:
	if rule == null or rule.collectible == null:
		return 0
	var chance := clampf(rule.chance, 0.0, 1.0)
	if chance <= 0.0 or (chance < 1.0 and _rng.randf() >= chance):
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
	if not _encounter_manager.owns_enemy(enemy):
		return
	var dropped_items: Array[EquipmentInstance] = []
	for rule in drop_rules:
		var item := _roll_equipment_drop(rule)
		if item != null:
			dropped_items.append(item)
	for index in dropped_items.size():
		_spawn_equipment_pickup(dropped_items[index], enemy.global_position, index, dropped_items.size())


func _roll_equipment_drop(rule: EquipmentDropRule) -> EquipmentInstance:
	if rule == null or rule.equipment == null or not rule.has_valid_quality_weights():
		return null
	var chance := clampf(rule.chance, 0.0, 1.0)
	if chance <= 0.0 or (chance < 1.0 and _rng.randf() >= chance):
		return null
	var quality := EquipmentLootRoller.roll_quality(_rng, rule.common_weight, rule.uncommon_weight, rule.rare_weight)
	return EquipmentLootRoller.create_instance(rule.equipment, quality, _player.reserve_equipment_instance_id(), _rng)


func _spawn_equipment_pickup(instance: EquipmentInstance, origin: Vector2, index: int, total: int) -> void:
	if instance == null or not instance.is_valid():
		return
	var pickup := EQUIPMENT_PICKUP_SCENE.instantiate() as EquipmentPickup
	_drops.add_child(pickup)
	pickup.global_position = _equipment_drop_position(origin)
	var fan := 0.0
	if total > 1:
		fan = lerpf(-90.0, 90.0, float(index) / float(total - 1))
	pickup.initialize(instance, Vector2(fan + _rng.randf_range(-45.0, 45.0), _rng.randf_range(-460.0, -340.0)))


func _equipment_drop_position(origin: Vector2) -> Vector2:
	var surface := _platform_navigation.get_surface_at_position(origin, 0.0, 72.0)
	if surface != null:
		return Vector2(surface.clamp_safe_x(origin.x, 24.0), surface.top_y - 34.0)
	var bounds := _map_definition.camera_bounds if _map_definition != null else Rect2(-370.0, -100.0, 3670.0, 820.0)
	return Vector2(clampf(origin.x, bounds.position.x + 24.0, bounds.end.x - 24.0), origin.y - 34.0)


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


func _apply_ui_foundation() -> void:
	_return_button = $Interface/SessionPanel/ReturnButton
	UI_STYLE.apply_button(_return_button)
	_health_fill.color = UI_STYLE.BAR_HEALTH
	_experience_fill.color = UI_STYLE.BAR_EXPERIENCE
	$Interface/HealthPanel/HealthBack.color = UI_STYLE.BAR_HEALTH_BACK
	$Interface/HealthPanel/ExpBack.color = UI_STYLE.BAR_EXPERIENCE_BACK
	$Interface/BackpackPanel/Background.color = UI_STYLE.PANEL_BG_ELEVATED
	$Interface/BackpackPanel/Header.color = UI_STYLE.HEADER_BG
	$Interface/BackpackPanel/DetailPanel.color = UI_STYLE.DETAIL_BG
	$Interface/BackpackPanel/DiscardConfirmation.color = Color("05090dcc")
	$Interface/BackpackPanel/DiscardConfirmation/Panel.color = UI_STYLE.PANEL_BG_ELEVATED
	$Interface/AttributesPanel/Background.color = UI_STYLE.PANEL_BG_ELEVATED
	$Interface/AttributesPanel/Header.color = UI_STYLE.HEADER_BG
	$Interface/AttributesPanel/EquipmentDetailPanel.color = UI_STYLE.DETAIL_BG
	$Interface/SkillsPanel/Background.color = UI_STYLE.PANEL_BG_ELEVATED
	$Interface/SkillsPanel/Header.color = UI_STYLE.HEADER_BG
	$Interface/SkillsPanel/DetailPanel.color = UI_STYLE.DETAIL_BG
	UI_STYLE.apply_button(_skills_decrease_button)
	UI_STYLE.apply_button(_skills_increase_button)
	for title_path in [
		NodePath("Interface/BackpackPanel/Title"),
		NodePath("Interface/AttributesPanel/Title"),
		NodePath("Interface/SkillsPanel/Title"),
	]:
		var title := get_node(title_path) as Label
		title.add_theme_color_override("font_color", UI_STYLE.ACCENT)
	for hint_path in [
		NodePath("Interface/BackpackPanel/HintText"),
		NodePath("Interface/AttributesPanel/HintText"),
		NodePath("Interface/SkillsPanel/HintText"),
	]:
		var hint := get_node(hint_path) as Label
		hint.add_theme_color_override("font_color", UI_STYLE.TEXT_MUTED)
	_save_status_text.add_theme_color_override("font_color", UI_STYLE.TEXT_SUCCESS)
	_return_status_text.add_theme_color_override("font_color", UI_STYLE.TEXT_WARNING)
	_backpack_feedback_text.add_theme_color_override("font_color", UI_STYLE.TEXT_WARNING)
	_skills_feedback_text.add_theme_color_override("font_color", UI_STYLE.TEXT_WARNING)
	for category in BackpackCategory.ALL:
		UI_STYLE.apply_runtime_row(
			_backpack_tab_buttons[category] as Button,
			category == _backpack_category
		)
	for slot in _skill_hud_slots:
		UI_STYLE.apply_panel_container(slot, true)


func _setup_skill_quickbar_hud() -> void:
	var key_texts := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
	for slot_index in key_texts.size():
		var slot := SKILL_QUICKBAR_SLOT.new() as SkillQuickbarSlot
		slot.name = "Slot%d" % (slot_index + 1)
		slot.setup(slot_index, key_texts[slot_index])
		slot.drop_requested.connect(_on_skill_quickbar_drop)
		slot.clear_requested.connect(_on_skill_quickbar_clear)
		_skill_quickbar_rows[floori(slot_index / 5.0)].add_child(slot)
		_skill_hud_slots.append(slot)
		_skill_hud_names.append(slot.name_label)
		_skill_hud_statuses.append(slot.status_label)
		_skill_hud_states.append(&"")


func _setup_backpack_tabs() -> void:
	for category in BackpackCategory.ALL:
		var button := _backpack_tab_buttons[category] as Button
		button.pressed.connect(_set_backpack_category.bind(category))


func _set_backpack_category(category: StringName) -> void:
	if not BackpackCategory.is_valid(category) or category == _backpack_category:
		return
	_cancel_discard()
	_backpack_category = category
	_hovered_backpack_instance_id = ""
	_selected_backpack_instance_id = ""
	_selected_backpack_index_hint = -1
	_hovered_stack_index = -1
	_selected_stack_index = -1
	_update_backpack_panel()


func _cycle_backpack_category(direction: int) -> void:
	var index := BackpackCategory.ALL.find(_backpack_category)
	if index < 0:
		index = 0
	index = posmod(index + direction, BackpackCategory.ALL.size())
	_set_backpack_category(BackpackCategory.ALL[index])


func _update_skill_quickbar_hud() -> void:
	for slot_index in _skill_hud_slots.size():
		var status := _player.get_skill_hud_status(slot_index)
		var state := StringName(status.get("state", &"empty"))
		var display_name := String(status.get("display_name", "未配置"))
		var message := String(status.get("message", "未配置"))
		_skill_hud_slots[slot_index].skill_id = StringName(status.get("skill_id", &""))
		_skill_hud_names[slot_index].text = display_name if display_name != "未配置" else "空"
		_skill_hud_statuses[slot_index].text = message
		_skill_hud_slots[slot_index].update_tooltip(display_name, message)
		if _skill_hud_states[slot_index] != state:
			_skill_hud_states[slot_index] = state
			_apply_skill_hud_state(slot_index, state)


func _apply_skill_hud_state(slot_index: int, state: StringName) -> void:
	var background := UI_STYLE.SLOT_BG
	var border := UI_STYLE.PANEL_BORDER
	var name_color := UI_STYLE.TEXT_PRIMARY
	var status_color := UI_STYLE.TEXT_MUTED
	match state:
		&"ready":
			background = Color("183a33ee")
			border = Color("66a683")
			status_color = UI_STYLE.TEXT_SUCCESS
		&"cooldown":
			background = Color("252b34ee")
			border = Color("596572")
			name_color = Color("a6afb6")
			status_color = Color("d1b36d")
		&"unavailable":
			background = Color("33252aee")
			border = Color("86565a")
			name_color = UI_STYLE.TEXT_DISABLED
			status_color = UI_STYLE.TEXT_DANGER
	_skill_hud_slots[slot_index].add_theme_stylebox_override(
		"panel",
		UI_STYLE.style_box(background, border, 1, 6)
	)
	_skill_hud_names[slot_index].add_theme_color_override("font_color", name_color)
	_skill_hud_statuses[slot_index].add_theme_color_override("font_color", status_color)


func _on_skill_quickbar_drop(slot_index: int, data: Dictionary) -> void:
	var source_slot := int(data.get("source_slot", -1))
	var result: Dictionary
	if source_slot >= 0:
		result = _player.move_skill_quickbar_slot(source_slot, slot_index)
	else:
		result = _player.set_skill_quickbar_slot(
			slot_index,
			StringName(data.get("skill_id", &""))
		)
	_show_reminder(_skills_feedback_text, String(result.get("message", "快捷栏配置失败")))
	_update_skill_quickbar_hud()


func _on_skill_quickbar_clear(slot_index: int) -> void:
	var result := _player.set_skill_quickbar_slot(slot_index, &"")
	_show_reminder(_skills_feedback_text, String(result.get("message", "快捷栏清空失败")))
	_update_skill_quickbar_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var echoed: bool = event is InputEventKey and event.echo
	if _discard_confirmation.visible:
		if event.is_action_pressed("ui_cancel") and not echoed:
			_cancel_discard()
		elif event.is_action_pressed("light_attack") and not echoed:
			_confirm_discard()
		get_viewport().set_input_as_handled()
		return
	if _backpack_panel.visible:
		if event is InputEventKey and event.keycode == KEY_TAB:
			if not echoed:
				_cycle_backpack_category(-1 if event.shift_pressed else 1)
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_backpack"):
			if not echoed:
				_set_backpack_panel_visible(false)
		elif event.is_action_pressed("toggle_attributes"):
			if not echoed:
				_set_attributes_panel_visible(true)
		elif event.is_action_pressed("toggle_skills"):
			if not echoed:
				_set_skills_panel_visible(true)
		elif event.is_action_pressed("light_attack"):
			if not echoed and _backpack_category == BackpackCategory.EQUIPMENT:
				_equip_selected_backpack_item()
		elif event.is_action_pressed("heavy_attack"):
			if not echoed and _backpack_category == BackpackCategory.EQUIPMENT:
				_open_discard_confirmation()
		elif event.is_action_pressed("move_left"):
			_move_backpack_selection(Vector2i.LEFT)
		elif event.is_action_pressed("move_right"):
			_move_backpack_selection(Vector2i.RIGHT)
		elif event.is_action_pressed("interact_up"):
			_move_backpack_selection(Vector2i.UP)
		elif event.is_action_pressed("interact_down"):
			_move_backpack_selection(Vector2i.DOWN)
		get_viewport().set_input_as_handled()
		return
	if _attributes_panel.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_attributes"):
			if not echoed:
				_set_attributes_panel_visible(false)
		elif event.is_action_pressed("toggle_backpack"):
			if not echoed:
				_set_backpack_panel_visible(true)
		elif event.is_action_pressed("toggle_skills"):
			if not echoed:
				_set_skills_panel_visible(true)
		elif event.is_action_pressed("light_attack"):
			if not echoed:
				_unequip_selected_slot()
		elif event.is_action_pressed("interact_up"):
			_move_equipment_selection(-1)
		elif event.is_action_pressed("interact_down"):
			_move_equipment_selection(1)
		get_viewport().set_input_as_handled()
		return
	if _skills_panel.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_skills"):
			if not echoed:
				_set_skills_panel_visible(false)
		elif event.is_action_pressed("toggle_backpack"):
			if not echoed:
				_set_backpack_panel_visible(true)
		elif event.is_action_pressed("toggle_attributes"):
			if not echoed:
				_set_attributes_panel_visible(true)
		elif event.is_action_pressed("interact_up"):
			_move_skill_selection(-1)
		elif event.is_action_pressed("interact_down"):
			_move_skill_selection(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact_up") and not echoed:
		if _has_activatable_checkpoint():
			_use_active_checkpoint()
			get_viewport().set_input_as_handled()
		elif _active_portal != null:
			_use_active_portal()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_attributes") and not echoed:
		_set_attributes_panel_visible(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_backpack") and not echoed:
		_set_backpack_panel_visible(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_skills") and not echoed:
		_set_skills_panel_visible(true)
		get_viewport().set_input_as_handled()


func _set_backpack_panel_visible(visible: bool) -> void:
	if visible:
		_attributes_panel.visible = false
		_hovered_equipment_slot = &""
		_skills_panel.visible = false
		_backpack_panel.visible = true
		_backpack_category = BackpackCategory.EQUIPMENT
		_selected_stack_index = -1
		_hovered_stack_index = -1
		_backpack_feedback_text.text = ""
		_update_backpack_panel()
	else:
		_cancel_discard()
		_backpack_panel.visible = false
		_hovered_backpack_instance_id = ""
	_update_gameplay_input_block()


func _set_attributes_panel_visible(visible: bool) -> void:
	if visible:
		_cancel_discard()
		_backpack_panel.visible = false
		_hovered_backpack_instance_id = ""
		_skills_panel.visible = false
		_attributes_panel.visible = true
		if not EquipmentSlot.is_valid(_selected_equipment_slot):
			_selected_equipment_slot = EquipmentSlot.ALL[0]
		_update_attributes_panel()
		_update_equipment_panel()
	else:
		_attributes_panel.visible = false
		_hovered_equipment_slot = &""
	_update_gameplay_input_block()


func _set_skills_panel_visible(visible: bool) -> void:
	if visible:
		_cancel_discard()
		_backpack_panel.visible = false
		_hovered_backpack_instance_id = ""
		_attributes_panel.visible = false
		_hovered_equipment_slot = &""
		_skills_panel.visible = true
		_skills_feedback_text.text = ""
		_update_skills_panel()
	else:
		_skills_panel.visible = false
	_update_gameplay_input_block()


func _update_gameplay_input_block() -> void:
	_player.set_gameplay_input_blocked(
		_backpack_panel.visible
		or _attributes_panel.visible
		or _skills_panel.visible
	)


func _update_skills_panel() -> void:
	var previous_id := _selected_skill_id
	for child in _skills_list.get_children():
		_skills_list.remove_child(child)
		child.queue_free()
	_skill_buttons_by_id.clear()
	_profession_skills = _player.get_profession_skills()
	_profession_skills.sort_custom(_skill_tree_order_before)
	_skills_empty_text.visible = _profession_skills.is_empty()
	if _find_skill_index(previous_id) >= 0:
		_selected_skill_id = previous_id
	elif _profession_skills.is_empty():
		_selected_skill_id = &""
	else:
		_selected_skill_id = _profession_skills[0].id
	_skills_points_text.text = "职业：%s    角色等级：%d    剩余技能点：%d" % [
		_player.get_profession_name(),
		_player.get_level(),
		_player.get_skill_points(),
	]
	for definition in _profession_skills:
		var row := SKILL_DRAG_BUTTON.new() as SkillDragButton
		var rank := _player.get_skill_rank(definition.id)
		var prerequisite_met := _is_skill_prerequisite_met(definition)
		row.custom_minimum_size = Vector2(400.0, 54.0)
		row.focus_mode = Control.FOCUS_NONE
		row.text = "%s%s    %s    Lv.%d / %d%s" % [
			_skill_tree_prefix(definition),
			definition.display_name,
			_skill_category_display_name(definition),
			rank,
			definition.get_maximum_rank(),
			"    [前置未满足]" if definition.has_prerequisite() and not prerequisite_met else "",
		]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.set_meta(&"skill_id", definition.id)
		row.skill_id = definition.id
		row.drag_enabled = definition.is_active() and rank > 0
		row.drag_label = definition.display_name
		row.tooltip_text = (
			"拖到顶部快捷栏进行配置"
			if row.drag_enabled
			else "只有已学习的主动技能可以拖入快捷栏"
		)
		UI_STYLE.apply_runtime_row(
			row,
			definition.id == _selected_skill_id
		)
		row.pressed.connect(_on_skill_pressed.bind(definition.id))
		_skills_list.add_child(row)
		_skill_buttons_by_id[definition.id] = row
	_update_skill_detail()
	_scroll_selected_skill.call_deferred()


func _find_skill_index(skill_id: StringName) -> int:
	if skill_id == &"":
		return -1
	for index in _profession_skills.size():
		if _profession_skills[index].id == skill_id:
			return index
	return -1


func _skill_tree_order_before(left: SkillDefinition, right: SkillDefinition) -> bool:
	var left_rank := _skill_tree_order_rank(left)
	var right_rank := _skill_tree_order_rank(right)
	if left_rank != right_rank:
		return left_rank < right_rank
	return String(left.id) < String(right.id)


func _skill_tree_order_rank(definition: SkillDefinition) -> int:
	if definition.is_passive():
		return 2
	if definition.has_prerequisite():
		return 1
	return 0


func _skill_tree_prefix(definition: SkillDefinition) -> String:
	if definition.is_passive():
		return "◆ "
	if definition.has_prerequisite():
		return "    └─ "
	return "● "


func _is_skill_prerequisite_met(definition: SkillDefinition) -> bool:
	if not definition.has_prerequisite():
		return true
	return _player.get_skill_rank(definition.prerequisite_skill_id) >= definition.prerequisite_rank


func _move_skill_selection(direction: int) -> void:
	if _profession_skills.is_empty():
		return
	var index := _find_skill_index(_selected_skill_id)
	index = 0 if index < 0 else clampi(index + direction, 0, _profession_skills.size() - 1)
	_selected_skill_id = _profession_skills[index].id
	_refresh_skill_selection()


func _on_skill_pressed(skill_id: StringName) -> void:
	if _find_skill_index(skill_id) < 0:
		return
	_selected_skill_id = skill_id
	_refresh_skill_selection()


func _refresh_skill_selection() -> void:
	for skill_id in _skill_buttons_by_id:
		var row := _skill_buttons_by_id[skill_id] as Button
		if row != null:
			UI_STYLE.apply_runtime_row(
				row,
				skill_id == _selected_skill_id
			)
	_update_skill_detail()
	_scroll_selected_skill.call_deferred()


func _scroll_selected_skill() -> void:
	var row := _skill_buttons_by_id.get(_selected_skill_id) as Control
	if row != null and is_instance_valid(row):
		_skills_scroll.ensure_control_visible(row)


func _increase_selected_skill_rank() -> void:
	if _selected_skill_id == &"":
		_show_reminder(_skills_feedback_text, "没有可加点的技能")
		return
	var result := _player.increase_skill_rank(_selected_skill_id)
	_update_skills_panel()
	_show_reminder(_skills_feedback_text, String(result.get("message", "加点失败")))


func _decrease_selected_skill_rank() -> void:
	if _selected_skill_id == &"":
		_show_reminder(_skills_feedback_text, "没有可减点的技能")
		return
	var result := _player.decrease_skill_rank(_selected_skill_id)
	_update_skills_panel()
	_show_reminder(_skills_feedback_text, String(result.get("message", "减点失败")))


func _update_skill_detail() -> void:
	var definition := DefinitionRegistry.get_skill(_selected_skill_id)
	if definition == null or not definition.is_available_to_profession(_player.get_profession_id()):
		_skills_detail_text.text = "选择技能查看详情"
		_skills_decrease_button.disabled = true
		_skills_increase_button.disabled = true
		return
	var rank := _player.get_skill_rank(definition.id)
	var status := _player.get_skill_rank_up_status(definition.id)
	var down_status := _player.get_skill_rank_down_status(definition.id)
	_skills_increase_button.disabled = not bool(status.get("ok", false))
	_skills_decrease_button.disabled = not bool(down_status.get("ok", false))
	var next_rank := mini(rank + 1, definition.get_maximum_rank())
	var lines: Array[String] = [
		definition.display_name,
		definition.description,
		"",
		"类型：%s" % _skill_category_display_name(definition),
		"成长位置：%s" % _skill_tree_position_text(definition),
		"需求角色等级：%d" % definition.required_level,
		"当前等级：%d / %d" % [rank, definition.get_maximum_rank()],
		"当前效果：%s" % (definition.effect_text_at_rank(rank) if rank > 0 else "未学习，无效果"),
	]
	if definition.has_prerequisite():
		var prerequisite := DefinitionRegistry.get_skill(definition.prerequisite_skill_id)
		var prerequisite_name := prerequisite.display_name if prerequisite != null else String(definition.prerequisite_skill_id)
		var prerequisite_current_rank := _player.get_skill_rank(definition.prerequisite_skill_id)
		lines.insert(6, "前置要求：%s Lv.%d（当前 Lv.%d，%s）" % [
			prerequisite_name,
			definition.prerequisite_rank,
			prerequisite_current_rank,
			"已满足" if prerequisite_current_rank >= definition.prerequisite_rank else "未满足",
		])
	if rank < definition.get_maximum_rank():
		lines.append("下一级效果：%s" % definition.effect_text_at_rank(next_rank))
	if definition.is_active():
		lines.append("施放环境：%s" % _skill_environment_text(definition))
		lines.append("冷却：%.1f 秒" % definition.cooldown)
		if not definition.required_weapon_types.is_empty():
			var weapon_names: Array[String] = []
			for weapon_type in definition.required_weapon_types:
				weapon_names.append(_weapon_type_display_name(weapon_type))
			lines.append("武器要求：%s" % " / ".join(weapon_names))
	lines.append("")
	lines.append("升级状态：%s" % String(status.get("message", "无法升级")))
	lines.append("降级状态：%s" % String(down_status.get("message", "无法降级")))
	_skills_detail_text.text = "\n".join(lines)


func _skill_category_display_name(definition: SkillDefinition) -> String:
	match definition.category:
		SkillCategory.NORMAL_OFFENSIVE:
			return "普通攻击技能"
		SkillCategory.OFFENSIVE_ULTIMATE:
			return "攻击大招"
		SkillCategory.BASIC_STAT_PASSIVE:
			return "基础属性被动"
	return "未知类型"


func _skill_tree_position_text(definition: SkillDefinition) -> String:
	if definition.is_passive():
		return "独立被动"
	if definition.has_prerequisite():
		return "进阶主动"
	return "基础主动"


func _skill_environment_text(definition: SkillDefinition) -> String:
	if definition.allow_ground and definition.allow_air:
		return "地面 / 空中"
	if definition.allow_ground:
		return "仅地面"
	return "仅空中"


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
		UI_STYLE.apply_runtime_row(row, false)
		row.mouse_entered.connect(_on_equipment_row_entered.bind(slot))
		row.mouse_exited.connect(_on_equipment_row_exited.bind(slot))
		row.pressed.connect(_on_equipment_row_pressed.bind(slot))


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
		var item := _player.get_equipped_item(slot)
		var item_name := "[%s] %s" % [EquipmentQuality.display_name(item.quality), item.get_display_name()] if item != null else "未装备"
		row.text = "%s：%s" % [EquipmentSlot.display_name(slot), item_name]
		row.disabled = false
		UI_STYLE.apply_runtime_row(
			row,
			slot == _selected_equipment_slot,
			EquipmentQuality.color(item.quality) if item != null else UI_STYLE.TEXT_MUTED
		)
	_show_active_equipment_detail()


func _on_equipment_row_entered(slot: StringName) -> void:
	_hovered_equipment_slot = slot
	_show_equipment_detail(slot)


func _on_equipment_row_exited(slot: StringName) -> void:
	if _hovered_equipment_slot == slot:
		_hovered_equipment_slot = &""
		_show_active_equipment_detail()


func _on_equipment_row_pressed(slot: StringName) -> void:
	_selected_equipment_slot = slot
	if _player.get_equipped_item(slot) != null:
		_unequip_selected_slot()
	else:
		_update_equipment_panel()


func _move_equipment_selection(direction: int) -> void:
	var index := EquipmentSlot.ALL.find(_selected_equipment_slot)
	if index < 0:
		index = 0
	else:
		index = clampi(index + direction, 0, EquipmentSlot.ALL.size() - 1)
	_selected_equipment_slot = EquipmentSlot.ALL[index]
	_update_equipment_panel()


func _unequip_selected_slot() -> void:
	if not EquipmentSlot.is_valid(_selected_equipment_slot):
		return
	var item := _player.get_equipped_item(_selected_equipment_slot)
	if item == null:
		return
	if _player.unequip_to_inventory(_selected_equipment_slot):
		_show_reminder(_backpack_feedback_text, "已卸下：[%s] %s" % [EquipmentQuality.display_name(item.quality), item.get_display_name()])


func _show_active_equipment_detail() -> void:
	var slot := _hovered_equipment_slot if _hovered_equipment_slot != &"" else _selected_equipment_slot
	if EquipmentSlot.is_valid(slot):
		_show_equipment_detail(slot)
	else:
		_hide_equipment_detail()


func _show_equipment_detail(slot: StringName) -> void:
	var item := _player.get_equipped_item(slot)
	if item == null:
		_equipment_detail_text.text = "%s\n\n未装备" % EquipmentSlot.display_name(slot)
	else:
		_equipment_detail_text.text = EquipmentTextFormatter.format_equipment_detail(item)
	_equipment_detail_panel.visible = true


func _hide_equipment_detail() -> void:
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


func _update_backpack_panel() -> void:
	for child in _backpack_list.get_children():
		_backpack_list.remove_child(child)
		child.queue_free()
	_backpack_buttons_by_id.clear()
	_backpack_slot_buttons.clear()
	for category in BackpackCategory.ALL:
		UI_STYLE.apply_runtime_row(
			_backpack_tab_buttons[category] as Button,
			category == _backpack_category
		)
	if _backpack_category == BackpackCategory.EQUIPMENT:
		_update_equipment_backpack_grid()
		_backpack_hint_text.text = "鼠标拖拽整理    Tab / Shift+Tab 切换分类    Z 装备    X 丢弃    I / Esc 关闭"
	else:
		_update_stackable_backpack_grid()
		_backpack_hint_text.text = "鼠标拖拽移动 / 合并    Tab / Shift+Tab 切换分类    I / Esc 关闭"


func _update_equipment_backpack_grid() -> void:
	var previous_id := _selected_backpack_instance_id
	var previous_index := _selected_backpack_index_hint
	_sorted_backpack_items = _player.get_equipment_inventory_slots()
	if _player.get_equipment_inventory().is_empty():
		_selected_backpack_instance_id = ""
		_selected_backpack_index_hint = -1
	else:
		var restored_index := _find_backpack_index(previous_id)
		if restored_index < 0:
			restored_index = _first_occupied_equipment_slot(previous_index)
		_selected_backpack_index_hint = restored_index
		_selected_backpack_instance_id = _sorted_backpack_items[restored_index].instance_id
	var capacity := _player.get_backpack_capacity(BackpackCategory.EQUIPMENT)
	for slot_index in capacity:
		var row := BACKPACK_SLOT_BUTTON.new() as BackpackSlotButton
		row.custom_minimum_size = Vector2(50.0, 50.0)
		row.focus_mode = Control.FOCUS_NONE
		row.set_quantity(0)
		row.configure_drag(BackpackCategory.EQUIPMENT, slot_index, _sorted_backpack_items[slot_index] != null, _on_backpack_slot_dropped)
		_backpack_slot_buttons.append(row)
		if _sorted_backpack_items[slot_index] == null:
			row.text = ""
			UI_STYLE.apply_backpack_slot(row, false, UI_STYLE.TEXT_DISABLED)
			_backpack_list.add_child(row)
			continue
		var item := _sorted_backpack_items[slot_index]
		row.text = _format_backpack_slot_text(item)
		row.tooltip_text = "[%s] %s" % [EquipmentQuality.display_name(item.quality), item.get_display_name()]
		UI_STYLE.apply_backpack_slot(
			row,
			item.instance_id == _selected_backpack_instance_id,
			EquipmentQuality.color(item.quality)
		)
		row.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.set_meta(&"equipment_instance_id", item.instance_id)
		row.mouse_entered.connect(_on_backpack_item_entered.bind(item.instance_id))
		row.mouse_exited.connect(_on_backpack_item_exited.bind(item.instance_id))
		row.pressed.connect(_on_backpack_item_pressed.bind(item.instance_id))
		_backpack_list.add_child(row)
		_backpack_buttons_by_id[item.instance_id] = row
	_show_active_backpack_detail()
	_scroll_selected_backpack_item.call_deferred()


func _update_stackable_backpack_grid() -> void:
	var stacks := _player.get_stackable_item_slots(_backpack_category, true)
	if _player.get_stackable_item_slots(_backpack_category).is_empty():
		_selected_stack_index = -1
	else:
		if _selected_stack_index < 0 or _selected_stack_index >= stacks.size() or stacks[_selected_stack_index].is_empty():
			_selected_stack_index = _first_occupied_stack_slot(stacks)
	var capacity := _player.get_backpack_capacity(_backpack_category)
	for slot_index in capacity:
		var row := BACKPACK_SLOT_BUTTON.new() as BackpackSlotButton
		row.custom_minimum_size = Vector2(50.0, 50.0)
		row.focus_mode = Control.FOCUS_NONE
		row.configure_drag(_backpack_category, slot_index, not stacks[slot_index].is_empty(), _on_backpack_slot_dropped)
		_backpack_slot_buttons.append(row)
		if stacks[slot_index].is_empty():
			row.text = ""
			row.set_quantity(0)
			UI_STYLE.apply_backpack_slot(row, false, UI_STYLE.TEXT_DISABLED)
			_backpack_list.add_child(row)
			continue
		var stack := stacks[slot_index]
		var item_id := StringName(String(stack.get("item_id", "")))
		var definition := DefinitionRegistry.get_stackable_item(item_id)
		if definition == null:
			row.set_quantity(0)
			UI_STYLE.apply_backpack_slot(row, false, UI_STYLE.TEXT_DISABLED)
			_backpack_list.add_child(row)
			continue
		row.text = definition.display_name.substr(0, mini(definition.display_name.length(), 3))
		row.tooltip_text = "%s ×%d" % [definition.display_name, int(stack.get("quantity", 0))]
		row.set_quantity(int(stack.get("quantity", 0)))
		row.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.set_meta(&"stack_index", slot_index)
		UI_STYLE.apply_backpack_slot(row, slot_index == _selected_stack_index, definition.color)
		row.mouse_entered.connect(_on_stackable_item_entered.bind(slot_index))
		row.mouse_exited.connect(_on_stackable_item_exited.bind(slot_index))
		row.pressed.connect(_on_stackable_item_pressed.bind(slot_index))
		_backpack_list.add_child(row)
	_show_active_stackable_detail()


func _backpack_item_before(first: EquipmentInstance, second: EquipmentInstance) -> bool:
	var first_rank := EquipmentQuality.sort_rank(first.quality)
	var second_rank := EquipmentQuality.sort_rank(second.quality)
	if first_rank != second_rank:
		return first_rank > second_rank
	var first_slot := EquipmentSlot.ALL.find(first.get_slot())
	var second_slot := EquipmentSlot.ALL.find(second.get_slot())
	first_slot = EquipmentSlot.ALL.size() if first_slot < 0 else first_slot
	second_slot = EquipmentSlot.ALL.size() if second_slot < 0 else second_slot
	if first_slot != second_slot:
		return first_slot < second_slot
	if first.get_display_name() != second.get_display_name():
		return first.get_display_name() < second.get_display_name()
	return first.instance_id < second.instance_id


static func backpack_navigation_index(current: int, count: int, direction: Vector2i, columns := BACKPACK_COLUMNS) -> int:
	if count <= 0 or current < 0 or current >= count or columns <= 0:
		return -1
	if direction == Vector2i.LEFT:
		return current - 1 if current % columns > 0 else current
	if direction == Vector2i.RIGHT:
		return current + 1 if current % columns < columns - 1 and current + 1 < count else current
	if direction == Vector2i.UP:
		return current - columns if current >= columns else current
	if direction == Vector2i.DOWN:
		var target := current + columns
		if target < count:
			return target
		var last_row_start := ((count - 1) / columns) * columns
		if current < last_row_start:
			return count - 1
	return current


func _find_backpack_index(instance_id: String) -> int:
	if instance_id.is_empty():
		return -1
	for index in _sorted_backpack_items.size():
		var item := _sorted_backpack_items[index]
		if item != null and item.instance_id == instance_id:
			return index
	return -1


func _first_occupied_equipment_slot(preferred_index := -1) -> int:
	if preferred_index >= 0 and preferred_index < _sorted_backpack_items.size() and _sorted_backpack_items[preferred_index] != null:
		return preferred_index
	for index in _sorted_backpack_items.size():
		if _sorted_backpack_items[index] != null:
			return index
	return -1


func _first_occupied_stack_slot(stacks: Array[Dictionary]) -> int:
	for index in stacks.size():
		if not stacks[index].is_empty():
			return index
	return -1


func _move_backpack_selection(direction: Vector2i) -> void:
	if _backpack_category != BackpackCategory.EQUIPMENT:
		var stacks := _player.get_stackable_item_slots(_backpack_category, true)
		var target_stack := backpack_navigation_index(
			_selected_stack_index,
			stacks.size(),
			direction
		)
		if target_stack < 0 or target_stack == _selected_stack_index or stacks[target_stack].is_empty():
			return
		_selected_stack_index = target_stack
		_refresh_stackable_selection()
		return
	var current := _find_backpack_index(_selected_backpack_instance_id)
	var target := backpack_navigation_index(current, _sorted_backpack_items.size(), direction)
	if target < 0 or target == current or _sorted_backpack_items[target] == null:
		return
	_selected_backpack_index_hint = target
	_selected_backpack_instance_id = _sorted_backpack_items[target].instance_id
	_refresh_backpack_selection()


func _refresh_backpack_selection() -> void:
	for instance_id in _backpack_buttons_by_id:
		var row := _backpack_buttons_by_id[instance_id] as Button
		var item := _player.get_equipment_instance(String(instance_id))
		if row != null and item != null:
			UI_STYLE.apply_backpack_slot(
				row,
				instance_id == _selected_backpack_instance_id,
				EquipmentQuality.color(item.quality)
			)
	_show_active_backpack_detail()
	_scroll_selected_backpack_item.call_deferred()


func _refresh_stackable_selection() -> void:
	var stacks := _player.get_stackable_item_slots(_backpack_category, true)
	for slot_index in mini(stacks.size(), _backpack_slot_buttons.size()):
		var row := _backpack_slot_buttons[slot_index]
		var stack := stacks[slot_index]
		if stack.is_empty():
			UI_STYLE.apply_backpack_slot(row, false, UI_STYLE.TEXT_DISABLED)
			continue
		var definition := DefinitionRegistry.get_stackable_item(
			StringName(String(stack.get("item_id", "")))
		)
		if row != null and definition != null:
			UI_STYLE.apply_backpack_slot(
				row,
				slot_index == _selected_stack_index,
				definition.color
			)
	_show_active_stackable_detail()
	if _selected_stack_index >= 0 and _selected_stack_index < _backpack_slot_buttons.size():
		_backpack_scroll.ensure_control_visible(_backpack_slot_buttons[_selected_stack_index])


func _scroll_selected_backpack_item() -> void:
	var row := _backpack_buttons_by_id.get(_selected_backpack_instance_id) as Control
	if row != null and is_instance_valid(row):
		_backpack_scroll.ensure_control_visible(row)


func _format_backpack_slot_text(item: EquipmentInstance) -> String:
	var quality_mark := EquipmentQuality.display_name(item.quality).substr(0, 1)
	var short_name := item.get_display_name().substr(0, mini(item.get_display_name().length(), 3))
	return "%s\n%s" % [quality_mark, short_name]


func _on_backpack_item_entered(instance_id: String) -> void:
	_hovered_backpack_instance_id = instance_id
	_show_backpack_detail(instance_id)


func _on_backpack_item_exited(instance_id: String) -> void:
	if _hovered_backpack_instance_id == instance_id:
		_hovered_backpack_instance_id = ""
		_show_active_backpack_detail()


func _on_backpack_item_pressed(instance_id: String) -> void:
	var index := _find_backpack_index(instance_id)
	if index < 0:
		return
	_selected_backpack_instance_id = instance_id
	_selected_backpack_index_hint = index
	_refresh_backpack_selection()
	_equip_selected_backpack_item()


func _on_stackable_item_entered(stack_index: int) -> void:
	_hovered_stack_index = stack_index
	_show_stackable_detail(stack_index)


func _on_stackable_item_exited(stack_index: int) -> void:
	if _hovered_stack_index == stack_index:
		_hovered_stack_index = -1
		_show_active_stackable_detail()


func _on_stackable_item_pressed(stack_index: int) -> void:
	var stacks := _player.get_stackable_item_slots(_backpack_category, true)
	if stack_index < 0 or stack_index >= stacks.size() or stacks[stack_index].is_empty():
		return
	_selected_stack_index = stack_index
	_refresh_stackable_selection()


func _on_backpack_slot_dropped(source_index: int, target_index: int) -> void:
	var moved := false
	if _backpack_category == BackpackCategory.EQUIPMENT:
		moved = _player.move_equipment_inventory_slot(source_index, target_index)
		if moved:
			_selected_backpack_index_hint = target_index
	else:
		moved = _player.move_stackable_item_slot(_backpack_category, source_index, target_index)
		if moved:
			_selected_stack_index = target_index
	if moved:
		_backpack_feedback_text.text = "背包栏位已调整"


func _equip_selected_backpack_item() -> void:
	var instance_id := _selected_backpack_instance_id
	var item := _player.get_equipment_instance(instance_id)
	if item == null or item not in _player.get_equipment_inventory():
		return
	_selected_backpack_index_hint = _find_backpack_index(instance_id)
	if _player.equip_inventory_item(instance_id):
		_show_reminder(_backpack_feedback_text, "已装备：[%s] %s" % [EquipmentQuality.display_name(item.quality), item.get_display_name()])


func _open_discard_confirmation() -> void:
	var item := _player.get_equipment_instance(_selected_backpack_instance_id)
	if item == null or item not in _player.get_equipment_inventory():
		return
	_pending_discard_instance_id = item.instance_id
	_pending_discard_index = _find_backpack_index(item.instance_id)
	_discard_confirmation_text.text = "确定丢弃这件装备？\n\n%s\n\nZ 确认    Esc 取消" % EquipmentTextFormatter.format_equipment_detail(item)
	_discard_confirmation.visible = true


func _cancel_discard() -> void:
	_pending_discard_instance_id = ""
	_pending_discard_index = -1
	if is_instance_valid(_discard_confirmation):
		_discard_confirmation.visible = false


func _confirm_discard() -> void:
	var instance_id := _pending_discard_instance_id
	var fallback_index := _pending_discard_index
	_cancel_discard()
	var item := _player.get_equipment_instance(instance_id)
	if item == null or item not in _player.get_equipment_inventory():
		return
	_selected_backpack_instance_id = instance_id
	_selected_backpack_index_hint = fallback_index
	if _player.discard_inventory_item(instance_id):
		_show_reminder(_backpack_feedback_text, "已丢弃：[%s] %s" % [EquipmentQuality.display_name(item.quality), item.get_display_name()])


func _on_equipment_equip_failed(message: String) -> void:
	_show_reminder(_backpack_feedback_text, "无法装备：%s" % message)


func _show_active_backpack_detail() -> void:
	if _backpack_category != BackpackCategory.EQUIPMENT:
		_show_active_stackable_detail()
		return
	var instance_id := _hovered_backpack_instance_id if not _hovered_backpack_instance_id.is_empty() else _selected_backpack_instance_id
	if instance_id.is_empty():
		_hide_backpack_detail()
	else:
		_show_backpack_detail(instance_id)


func _show_backpack_detail(instance_id: String) -> void:
	var item := _player.get_equipment_instance(instance_id)
	if item == null or item not in _player.get_equipment_inventory():
		_hide_backpack_detail()
		return
	_backpack_detail_text.text = EquipmentTextFormatter.format_backpack_comparison(item, _player.preview_equipment_stats(item))
	_backpack_detail_panel.visible = true


func _hide_backpack_detail() -> void:
	_backpack_detail_panel.visible = false
	_backpack_detail_text.text = ""


func _show_active_stackable_detail() -> void:
	var stack_index := _hovered_stack_index if _hovered_stack_index >= 0 else _selected_stack_index
	if stack_index < 0:
		_hide_backpack_detail()
	else:
		_show_stackable_detail(stack_index)


func _show_stackable_detail(stack_index: int) -> void:
	var stacks := _player.get_stackable_item_slots(_backpack_category, true)
	if stack_index < 0 or stack_index >= stacks.size() or stacks[stack_index].is_empty():
		_hide_backpack_detail()
		return
	var stack := stacks[stack_index]
	var definition := DefinitionRegistry.get_stackable_item(
		StringName(String(stack.get("item_id", "")))
	)
	if definition == null:
		_hide_backpack_detail()
		return
	_backpack_detail_text.text = "\n".join([
		definition.display_name,
		"",
		"分类：%s" % BackpackCategory.display_name(definition.category),
		"当前格数量：%d / %d" % [int(stack.get("quantity", 0)), definition.stack_limit],
		"背包总数：%d" % _player.get_stackable_item_quantity(definition.id),
		"",
		definition.description,
	])
	_backpack_detail_panel.visible = true


func _format_stat(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value


func _format_percent(value: float) -> String:
	return "%s%%" % _format_stat(value * 100.0)


func _reset_enemy_aggro() -> void:
	for enemy in _encounter_manager.get_owned_enemies():
		if enemy != null and is_instance_valid(enemy) and enemy.visible:
			enemy.reset_aggro_at_current_position()


func _clear_world_map() -> void:
	_active_portal = null
	_active_checkpoint = null
	_interaction_prompt_text.visible = false
	for child in _map_root.get_children():
		_map_root.remove_child(child)
		child.queue_free()
	for child in _platforms.get_children():
		_platforms.remove_child(child)
		child.queue_free()
	for child in _world_markers.get_children():
		_world_markers.remove_child(child)
		child.queue_free()
	_platform_navigation.clear()


func _build_course_from_layout(layout: Node) -> void:
	if not layout.has_method("get_floor_center") or not layout.has_method("get_floor_size"):
		return
	var floor_center: Vector2 = layout.call("get_floor_center")
	var floor_size: Vector2 = layout.call("get_floor_size")
	_create_platform(floor_center, floor_size, false)
	var left := floor_center.x - floor_size.x * 0.5
	var right := floor_center.x + floor_size.x * 0.5
	_create_map_boundary(left)
	_create_map_boundary(right)
	_platform_navigation.register_surface(&"ground", left, right, floor_center.y - floor_size.y * 0.5, false, true)
	var previous_id := &"ground"
	var platform_rects: Array[Rect2] = layout.call("get_platform_rects")
	for index in platform_rects.size():
		var rect := platform_rects[index]
		var center := rect.position + rect.size * 0.5
		_create_platform(center, rect.size, true)
		var surface_id := StringName("platform_%d" % index)
		_platform_navigation.register_surface(surface_id, rect.position.x, rect.end.x, rect.position.y, true)
		_platform_navigation.add_bidirectional_link(previous_id, surface_id)
		previous_id = surface_id


func _build_world_markers() -> void:
	if _map_definition == null:
		return
	for portal in _map_definition.portals:
		_world_markers.add_child(_create_world_marker(portal.position, Color("7ed8ff"), "传送门"))
	for checkpoint in _map_definition.checkpoints:
		_world_markers.add_child(_create_world_marker(checkpoint.position, Color("ffe072"), checkpoint.display_name))


func _create_world_marker(position: Vector2, color: Color, label_text: String) -> Node2D:
	var marker := Node2D.new()
	marker.position = position
	var pillar := Polygon2D.new()
	pillar.polygon = PackedVector2Array([
		Vector2(-16.0, 54.0), Vector2(16.0, 54.0),
		Vector2(11.0, -42.0), Vector2(-11.0, -42.0),
	])
	pillar.color = color
	marker.add_child(pillar)
	var label := Label.new()
	label.position = Vector2(-100.0, -82.0)
	label.size = Vector2(200.0, 30.0)
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	marker.add_child(label)
	return marker


func _configure_player_camera(bounds: Rect2) -> void:
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = floori(bounds.position.x)
	camera.limit_top = floori(bounds.position.y)
	camera.limit_right = ceili(bounds.end.x)
	camera.limit_bottom = ceili(bounds.end.y)
	camera.reset_smoothing()


func _update_world_interaction() -> void:
	if _map_definition == null or not is_instance_valid(_player):
		return
	if _portal_transition_locked:
		if (
			not Input.is_action_pressed("interact_up")
			or _player.global_position.distance_to(_portal_rearm_position) >= PORTAL_REARM_DISTANCE
		):
			_portal_transition_locked = false
		else:
			_active_portal = null
	_active_checkpoint = _nearest_checkpoint()
	_active_portal = null if _portal_transition_locked else _nearest_portal()
	if _has_activatable_checkpoint():
		_interaction_prompt_text.text = "按 ↑ 激活 %s" % _active_checkpoint.display_name
		_interaction_prompt_text.visible = true
		return
	if _active_portal == null:
		_interaction_prompt_text.visible = false
		return
	_interaction_prompt_text.text = (
		_active_portal.interaction_prompt
		if not _active_portal.interaction_prompt.is_empty()
		else "按 ↑ 进入传送门"
	)
	_interaction_prompt_text.visible = true


func _nearest_portal() -> PortalDefinition:
	var nearest: PortalDefinition
	var nearest_distance := INF
	for portal in _map_definition.portals:
		var distance := _player.global_position.distance_to(portal.position)
		if distance <= portal.interaction_radius and distance < nearest_distance:
			nearest = portal
			nearest_distance = distance
	return nearest


func _nearest_checkpoint() -> CheckpointDefinition:
	var nearest: CheckpointDefinition
	var nearest_distance := INF
	for checkpoint in _map_definition.checkpoints:
		var distance := _player.global_position.distance_to(checkpoint.position)
		if distance <= checkpoint.interaction_radius and distance < nearest_distance:
			nearest = checkpoint
			nearest_distance = distance
	return nearest


func _has_activatable_checkpoint() -> bool:
	if _active_checkpoint == null:
		return false
	var location := GameSession.get_active_world_location()
	return (
		StringName(String(location.get("active_checkpoint_id", "")))
		!= _active_checkpoint.id
	)


func _use_active_checkpoint() -> void:
	if not _has_activatable_checkpoint():
		return
	var result := GameSession.activate_checkpoint(_active_checkpoint.id)
	_show_reminder(_world_status_text, String(result.get("message", "")))
	_update_world_interaction()


func _use_active_portal() -> void:
	if _active_portal == null or _portal_transition_locked:
		return
	if _active_portal.condition_id != &"" and _locked_portal_ids.has(_active_portal.condition_id):
		_show_reminder(
			_world_status_text,
			_active_portal.locked_message
			if not _active_portal.locked_message.is_empty()
			else "当前无法使用传送门"
		)
		return
	var portal := _active_portal
	_portal_transition_locked = true
	_active_portal = null
	_interaction_prompt_text.visible = false
	var result := load_world_map(
		portal.target_map_id,
		portal.target_entry_id,
		true
	)
	if not result.ok:
		_portal_transition_locked = false
		_show_reminder(_world_status_text, String(result.message))
		return
	var location_result := GameSession.set_continue_location(portal.target_map_id, portal.target_entry_id)
	if not location_result.ok:
		_show_reminder(_world_status_text, String(location_result.message))
		return
	GameSession.request_autosave(&"portal")


func _create_map_boundary(x_position: float) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x_position, 0.0)
	body.collision_layer = 1
	body.collision_mask = 2
	_platforms.add_child(body)

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
	_platforms.add_child(body)

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
