extends Control

@onready var _slot_list: VBoxContainer = $Margin/Layout/SlotList
@onready var _message_label: Label = $Margin/Layout/MessageLabel
@onready var _delete_panel: PanelContainer = $DeletePanel
@onready var _delete_warning: Label = $DeletePanel/Margin/Layout/Warning
@onready var _delete_input: LineEdit = $DeletePanel/Margin/Layout/ConfirmInput
@onready var _delete_confirm: Button = $DeletePanel/Margin/Layout/Buttons/Delete

var _active_slot := -1


func _ready() -> void:
	GameSession.index_changed.connect(_refresh_slots)
	_delete_input.text_changed.connect(_on_delete_confirmation_changed)
	$DeletePanel/Margin/Layout/Buttons/Delete.pressed.connect(_on_delete_confirmed)
	$DeletePanel/Margin/Layout/Buttons/Cancel.pressed.connect(_close_delete_panel)
	var result := GameSession.refresh_index()
	_show_message(String(result.message), false)
	_refresh_slots()


func _refresh_slots() -> void:
	for child in _slot_list.get_children():
		child.queue_free()
	for slot in GameSession.get_slots():
		_slot_list.add_child(_build_slot_card(slot))


func _build_slot_card(slot: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 142.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	var marker := ColorRect.new()
	marker.custom_minimum_size = Vector2(86.0, 86.0)
	marker.color = _profession_color(StringName(String(slot.get("profession_id", ""))))
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 18)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var occupied := not String(slot.get("profile_id", "")).is_empty()
	if occupied:
		var profession := GameSession.get_profession_definition(StringName(String(slot.profession_id)))
		var profession_name := profession.display_name if profession != null else "未知职业"
		info.text = "%s\n%s · 等级 %d\n%s · 游玩 %s\n最近游玩：%s" % [
			String(slot.name),
			profession_name,
			int(slot.level),
			_area_display_name(String(slot.area_id)),
			_format_play_time(int(slot.play_time_seconds)),
			_format_timestamp(int(slot.updated_at)),
		]
	else:
		info.text = "空栏位\n创建一名新的冒险者"
	row.add_child(info)

	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size.x = 150.0
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	row.add_child(buttons)
	var slot_index := int(slot.slot)
	if occupied:
		var continue_button := Button.new()
		continue_button.text = "继续旅程"
		continue_button.pressed.connect(_on_continue_pressed.bind(slot_index))
		buttons.add_child(continue_button)
		var delete_button := Button.new()
		delete_button.text = "删除角色"
		delete_button.pressed.connect(_open_delete_panel.bind(slot_index))
		buttons.add_child(delete_button)
	else:
		var create_button := Button.new()
		create_button.text = "创建角色"
		create_button.pressed.connect(_on_create_pressed.bind(slot_index))
		buttons.add_child(create_button)
	return panel


func _on_create_pressed(slot_index: int) -> void:
	var result := GameSession.begin_character_creation(slot_index)
	if not result.ok:
		_show_message(String(result.message), true)


func _on_continue_pressed(slot_index: int) -> void:
	GameSession.prepare_gameplay_scene_transition(get_viewport())
	_show_message("正在读取角色档案...", false)
	var result := GameSession.continue_character(slot_index)
	if not result.ok:
		_show_message(String(result.message), true)
	elif not String(result.message).is_empty():
		_show_message(String(result.message), false)


func _open_delete_panel(slot_index: int) -> void:
	var slot := GameSession.get_slot(slot_index)
	var profession := GameSession.get_profession_definition(StringName(String(slot.profession_id)))
	_active_slot = slot_index
	_delete_warning.text = "即将删除：%s\n职业：%s · 等级 %d\n\n等级、装备、背包和地图进度都会被删除。\n请输入角色名“%s”确认。" % [
		String(slot.name),
		profession.display_name if profession != null else "未知职业",
		int(slot.level),
		String(slot.name),
	]
	_delete_input.text = ""
	_delete_confirm.disabled = true
	_delete_panel.visible = true
	_delete_input.grab_focus()


func _close_delete_panel() -> void:
	_delete_panel.visible = false
	_active_slot = -1
	get_viewport().gui_release_focus()


func _on_delete_confirmation_changed(value: String) -> void:
	var slot := GameSession.get_slot(_active_slot)
	_delete_confirm.disabled = value != String(slot.get("name", ""))


func _on_delete_confirmed() -> void:
	var result := GameSession.delete_character(_active_slot, _delete_input.text)
	if not result.ok:
		_show_message(String(result.message), true)
		return
	_close_delete_panel()
	_show_message(String(result.message), false)
	_refresh_slots()


func _show_message(message: String, failed: bool) -> void:
	_message_label.text = message
	_message_label.modulate = Color("ff916f") if failed else Color("e8d579")


func _profession_color(profession_id: StringName) -> Color:
	if profession_id == &"star_seeker":
		return Color("5367a5")
	if profession_id == &"traveler":
		return Color("5f8b72")
	return Color("33434b")


func _area_display_name(area_id: String) -> String:
	return "战斗试验场" if area_id == "test_level" else "未知地区"


func _format_play_time(total_seconds: int) -> String:
	var hours := total_seconds / 3600
	var minutes := total_seconds % 3600 / 60
	return "%d 小时 %02d 分" % [hours, minutes]


func _format_timestamp(unix_time: int) -> String:
	if unix_time <= 0:
		return "从未"
	var values := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [values.year, values.month, values.day, values.hour, values.minute]
