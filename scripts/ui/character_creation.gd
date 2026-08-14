extends Control

const UI_STYLE := preload("res://scripts/ui/ui_style.gd")

@onready var _slot_label: Label = $Margin/Layout/SlotLabel
@onready var _name_input: LineEdit = $Margin/Layout/MainColumns/Form/Margin/Layout/NameInput
@onready var _profession_options: OptionButton = $Margin/Layout/MainColumns/Form/Margin/Layout/ProfessionOptions
@onready var _profession_detail: Label = $Margin/Layout/MainColumns/Form/Margin/Layout/ProfessionDetail
@onready var _appearance_placeholder: Label = $Margin/Layout/MainColumns/FutureOptions/AppearancePanel/Margin/Layout/Placeholder
@onready var _loadout_placeholder: Label = $Margin/Layout/MainColumns/FutureOptions/LoadoutPanel/Margin/Layout/Placeholder
@onready var _feedback: Label = $Margin/Layout/Feedback
@onready var _confirm_button: Button = $Margin/Layout/Buttons/Confirm

var _active_slot := -1
var _profession_definitions: Array[ProfessionDefinition] = []
var _creation_draft := {
	"slot": -1,
	"name": "",
	"profession_id": "",
	"appearance": {"preset_id": "", "palette_id": "", "body_options": {}},
	"starting_loadout": {"preset_id": "", "equipment_ids": []},
}


func _ready() -> void:
	_apply_ui_foundation()
	_active_slot = GameSession.get_pending_creation_slot()
	if _active_slot < 0 or _active_slot >= GameSession.SLOT_COUNT:
		GameSession.return_to_character_select.call_deferred()
		return
	var slot := GameSession.get_slot(_active_slot)
	if not String(slot.get("profile_id", "")).is_empty():
		GameSession.return_to_character_select.call_deferred()
		return
	_creation_draft.slot = _active_slot
	_slot_label.text = "角色栏位 %d" % (_active_slot + 1)
	_name_input.text_changed.connect(_on_name_changed)
	_profession_options.item_selected.connect(_on_profession_selected)
	_confirm_button.pressed.connect(_on_create_confirmed)
	$Margin/Layout/Buttons/Cancel.pressed.connect(_on_cancel_pressed)
	_profession_definitions = GameSession.get_profession_options()
	for definition in _profession_definitions:
		_profession_options.add_item(definition.display_name)
	_profession_options.select(0 if not _profession_definitions.is_empty() else -1)
	_update_profession_detail()
	_name_input.grab_focus()


func _apply_ui_foundation() -> void:
	$Background.color = UI_STYLE.PAGE_BG
	$Accent.color = UI_STYLE.ACCENT
	$Margin/Layout/Title.add_theme_color_override("font_color", UI_STYLE.ACCENT)
	_slot_label.add_theme_color_override("font_color", UI_STYLE.TEXT_MUTED)
	UI_STYLE.apply_panel_container($Margin/Layout/MainColumns/Form, true)
	UI_STYLE.apply_panel_container(
		$Margin/Layout/MainColumns/FutureOptions/AppearancePanel
	)
	UI_STYLE.apply_panel_container(
		$Margin/Layout/MainColumns/FutureOptions/LoadoutPanel
	)
	UI_STYLE.apply_line_edit(_name_input)
	UI_STYLE.apply_option_button(_profession_options)
	UI_STYLE.apply_button(_confirm_button, &"primary")
	UI_STYLE.apply_button($Margin/Layout/Buttons/Cancel)
	_profession_detail.add_theme_color_override("font_color", UI_STYLE.TEXT_PRIMARY)
	_appearance_placeholder.add_theme_color_override("font_color", UI_STYLE.TEXT_MUTED)
	_loadout_placeholder.add_theme_color_override("font_color", UI_STYLE.TEXT_MUTED)
	for title_path in [
		NodePath("Margin/Layout/MainColumns/FutureOptions/AppearancePanel/Margin/Layout/Title"),
		NodePath("Margin/Layout/MainColumns/FutureOptions/LoadoutPanel/Margin/Layout/Title"),
	]:
		var title := get_node(title_path) as Label
		title.add_theme_color_override("font_color", UI_STYLE.TEXT_MUTED)
	$Margin/Layout/MainColumns/FutureOptions/AppearancePanel/Margin/Layout/Preview.color = \
		UI_STYLE.SLOT_BG


func _on_name_changed(value: String) -> void:
	_creation_draft.name = value
	var result := GameSession.validate_character_name(value)
	_feedback.text = "" if result.ok or value.is_empty() else String(result.message)
	if not _feedback.text.is_empty():
		UI_STYLE.apply_message(_feedback, true)
	_confirm_button.disabled = not result.ok or _profession_options.selected < 0


func _on_profession_selected(index: int) -> void:
	if index >= 0 and index < _profession_definitions.size():
		_creation_draft.profession_id = String(_profession_definitions[index].id)
	_update_profession_detail()
	_on_name_changed(_name_input.text)


func _update_profession_detail() -> void:
	var index := _profession_options.selected
	if index < 0 or index >= _profession_definitions.size():
		_profession_detail.text = ""
		_loadout_placeholder.text = "请选择职业后查看初始装备。"
		return
	var definition := _profession_definitions[index]
	_creation_draft.profession_id = String(definition.id)
	if definition.id == &"star_seeker":
		_profession_detail.text = "观星者\n定位：远程魔法攻击\n可用武器：法杖\n初始能力：星纹法杖的魔法投射物"
	else:
		_profession_detail.text = "旅人\n定位：近战探索者\n可用武器：剑、法杖\n初始能力：旅人之剑的快速与重型斩击"
	var equipment_names: Array[String] = []
	for equipment in definition.starting_equipment:
		if equipment != null:
			equipment_names.append(equipment.display_name)
	_loadout_placeholder.text = "当前初始装备：\n%s\n\n后续将在此处选择初始武器与装备方案。" % "、".join(equipment_names)
	_appearance_placeholder.text = "当前使用职业默认外观。\n\n后续将在此处加入体型、发型、配色和其他外观选项。"


func _on_create_confirmed() -> void:
	var profession_index := _profession_options.selected
	if profession_index < 0 or profession_index >= _profession_definitions.size():
		_feedback.text = "请选择职业"
		UI_STYLE.apply_message(_feedback, true)
		return
	var result := GameSession.create_character(_active_slot, _name_input.text, _profession_definitions[profession_index].id)
	if not result.ok:
		_feedback.text = String(result.message)
		UI_STYLE.apply_message(_feedback, true)
		return
	_release_focus()
	GameSession.return_to_character_select()


func _on_cancel_pressed() -> void:
	_release_focus()
	GameSession.return_to_character_select()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


func _release_focus() -> void:
	get_viewport().gui_release_focus()
