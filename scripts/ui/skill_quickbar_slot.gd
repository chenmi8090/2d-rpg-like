class_name SkillQuickbarSlot
extends PanelContainer

signal drop_requested(slot_index: int, data: Dictionary)
signal clear_requested(slot_index: int)

var slot_index := -1
var skill_id: StringName = &""
var key_label: Label
var name_label: Label
var status_label: Label


func setup(index: int, key_text: String) -> void:
	slot_index = index
	custom_minimum_size = Vector2(78.0, 43.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "%s：空槽\n从 K 职业技能页拖入主动技能；右键清空" % key_text

	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	key_label = Label.new()
	key_label.position = Vector2(5.0, 2.0)
	key_label.size = Vector2(18.0, 18.0)
	key_label.text = key_text
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", Color("f4d66b"))
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(key_label)

	name_label = Label.new()
	name_label.position = Vector2(20.0, 2.0)
	name_label.size = Vector2(54.0, 19.0)
	name_label.text = "空"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)

	status_label = Label.new()
	status_label.position = Vector2(5.0, 21.0)
	status_label.size = Vector2(68.0, 18.0)
	status_label.text = "未配置"
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(status_label)

	gui_input.connect(_on_gui_input)


func update_tooltip(display_name: String, message: String) -> void:
	var key_text := key_label.text if key_label != null else str(slot_index + 1)
	tooltip_text = "%s：%s\n%s\n拖动可交换位置；右键清空" % [key_text, display_name, message]


func _get_drag_data(_at_position: Vector2) -> Variant:
	if skill_id == &"":
		return null
	var preview := Label.new()
	preview.text = name_label.text
	preview.add_theme_font_size_override("font_size", 14)
	preview.add_theme_color_override("font_color", Color("fff0ad"))
	set_drag_preview(preview)
	return {
		"kind": &"skill_quickbar",
		"skill_id": skill_id,
		"source_slot": slot_index,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and StringName(data.get("kind", &"")) == &"skill_quickbar"
		and StringName(data.get("skill_id", &"")) != &""
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_requested.emit(slot_index, (data as Dictionary).duplicate())


func _on_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		clear_requested.emit(slot_index)
		accept_event()
