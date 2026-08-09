extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const TEST_ROOT := "user://issue_11_test_profiles"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_session := root.get_node("GameSession")
	_clean_test_root()
	game_session.use_test_save_root(TEST_ROOT)
	game_session.set_test_disable_scene_changes(true)
	await _test_player_inventory_transactions()
	await _test_level_inventory_ui()
	game_session.set_test_disable_scene_changes(false)
	game_session.reset_save_root()
	_clean_test_root()
	if _failures.is_empty():
		print("Issue #11 inventory management tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_player_inventory_transactions() -> void:
	var container := Node2D.new()
	root.add_child(container)
	var player := PLAYER_SCENE.instantiate() as Player
	container.add_child(player)
	await process_frame
	var definition := DefinitionRegistry.get_equipment(&"tempered_sword")
	var first := player.create_template_equipment(definition)
	var second := player.create_template_equipment(definition)
	_expect(player.collect_equipment(first), "可以收集第一个具体实例")
	_expect(player.collect_equipment(second), "可以收集同模板的第二个实例")
	var initial := player.get_equipped_item(EquipmentSlot.WEAPON)
	_expect(player.equip_inventory_item(first.instance_id), "按实例 ID 装备背包物品")
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON) == first, "装备栏持有同一个对象实例")
	_expect(first not in player.get_equipment_inventory(), "已装备实例不同时留在背包")
	_expect(initial in player.get_equipment_inventory(), "被替换实例返回背包")
	var snapshot := first.to_snapshot()
	_expect(player.unequip_to_inventory(EquipmentSlot.WEAPON), "已装备物品可以卸回背包")
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON) == null, "卸下后槽位为空")
	_expect(first in player.get_equipment_inventory() and first.to_snapshot() == snapshot, "卸下保持实例 ID、品质和属性")
	_expect(not player.unequip_to_inventory(EquipmentSlot.WEAPON), "重复卸下空槽安全无操作")
	_expect(player.discard_inventory_item(first.instance_id), "可以丢弃指定背包实例")
	_expect(not player.has_equipment_instance(first.instance_id), "丢弃后目标实例不存在")
	_expect(second in player.get_equipment_inventory(), "丢弃不影响同模板其他实例")
	_expect(not player.discard_inventory_item(first.instance_id), "重复丢弃同一实例保持幂等")
	_expect(player.equip_inventory_item(second.instance_id), "第二个实例可以装备")
	_expect(not player.discard_inventory_item(second.instance_id), "背包丢弃 API 不能删除已装备实例")
	var equipped_snapshot := second.to_snapshot()
	var removed := player.unequip_slot(EquipmentSlot.WEAPON)
	_expect(removed == second, "兼容卸下 API 返回同一个已装备实例")
	_expect(second in player.get_equipment_inventory(), "任何卸下入口都把装备放回背包")
	_expect(second.to_snapshot() == equipped_snapshot, "卸下到背包保持完整装备实例")
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON) == null, "卸下后专用装备槽为空")
	player.set_gameplay_input_blocked(true)
	_expect(player.is_gameplay_input_blocked(), "面板可以持久阻止玩家命令输入")
	player.set_gameplay_input_blocked(false)
	_expect(not player.is_gameplay_input_blocked(), "关闭面板后恢复玩家命令输入")
	_expect(not player._input_suppressed(), "解除面板阻止后不保留短时输入抑制")
	container.queue_free()
	await process_frame


func _test_level_inventory_ui() -> void:
	var level_scene := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := level_scene.instantiate()
	root.add_child(level)
	await process_frame
	var player := level.get_node("Player") as Player
	var definition := DefinitionRegistry.get_equipment(&"tempered_sword")
	var items: Array[EquipmentInstance] = []
	for index in 12:
		var item := player.create_template_equipment(definition)
		item.instance_id = "ui_item_%02d" % index
		player.collect_equipment(item)
		items.append(item)
	await process_frame
	level._set_backpack_panel_visible(true)
	_expect(level.backpack_navigation_index(0, 0, Vector2i.RIGHT) == -1, "空背包没有无效导航选择")
	_expect(level.backpack_navigation_index(9, 11, Vector2i.RIGHT) == 9, "完整行末尾不会横向换行")
	_expect(level.backpack_navigation_index(5, 11, Vector2i.DOWN) == 10, "末行缺少同列时落到末项")
	_expect(level.backpack_navigation_index(10, 11, Vector2i.UP) == 0, "不完整末行可以向上返回同列")
	_expect(level._backpack_panel.visible, "键盘背包面板可以打开")
	_expect(not level._attributes_panel.visible, "打开背包会关闭角色信息")
	_expect(player.is_gameplay_input_blocked(), "背包打开时阻止游戏命令")
	_expect(not level._selected_backpack_instance_id.is_empty(), "非空背包自动选择具体实例")
	var selected_id: String = level._selected_backpack_instance_id
	level._update_backpack_panel()
	_expect(level._selected_backpack_instance_id == selected_id, "重建背包后保持同一实例选择")
	level._move_backpack_selection(Vector2i.DOWN)
	_expect(level._selected_backpack_instance_id != selected_id, "十列网格键盘导航更新选择")
	var discard_id: String = level._selected_backpack_instance_id
	level._open_discard_confirmation()
	_expect(level._discard_confirmation.visible, "丢弃前显示确认步骤")
	level._cancel_discard()
	_expect(player.has_equipment_instance(discard_id), "取消丢弃不改变实例所有权")
	level._open_discard_confirmation()
	level._confirm_discard()
	_expect(not player.has_equipment_instance(discard_id), "确认丢弃只移除捕获的具体实例")
	_expect(not level._selected_backpack_instance_id.is_empty(), "丢弃后回退到有效选择")
	level._set_attributes_panel_visible(true)
	_expect(level._attributes_panel.visible and not level._backpack_panel.visible, "角色信息与背包保持互斥")
	_expect(player.is_gameplay_input_blocked(), "面板切换期间保持输入阻止")
	var equipped_for_click := player.get_equipped_item(EquipmentSlot.WEAPON)
	if equipped_for_click == null:
		var click_item := player.create_template_equipment(definition)
		player.collect_equipment(click_item)
		player.equip_inventory_item(click_item.instance_id)
		equipped_for_click = click_item
	level._on_equipment_row_pressed(EquipmentSlot.WEAPON)
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON) == null, "点击已装备槽可以卸下装备")
	_expect(equipped_for_click in player.get_equipment_inventory(), "点击卸下后同一装备实例返回背包")
	level._set_attributes_panel_visible(false)
	_expect(not player.is_gameplay_input_blocked(), "关闭最后一个面板后恢复输入")
	_expect(not player._input_suppressed(), "关闭最后一个面板后立即恢复攻击输入")
	level.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _clean_test_root() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_directory(path.path_join(directory_name))
	DirAccess.remove_absolute(path)
