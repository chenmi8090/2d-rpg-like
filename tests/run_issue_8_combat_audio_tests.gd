extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/patrol_enemy.tscn")
const SWORD_LIGHT := preload("res://resources/combat/player_attacks/sword_light.tres")
const SWORD_HEAVY := preload("res://resources/combat/player_attacks/sword_heavy.tres")
const STAFF_LIGHT := preload("res://resources/combat/player_attacks/staff_light.tres")
const STAFF_HEAVY := preload("res://resources/combat/player_attacks/staff_heavy.tres")
const PLAYER_AUDIO := preload("res://resources/audio/combat/actors/player_audio.tres")
const GRUNT_DEFINITION := preload("res://resources/enemies/patrol_grunt_definition.tres")
const HEAVY_DEFINITION := preload("res://resources/enemies/heavy_guard_definition.tres")
const MANIFEST_PATH := "res://assets/audio/combat/generated/manifest.json"
const FLOOR_Y := 120.0
const PLAYER_FLOOR_POSITION_Y := 82.0
const EXPECTED_CUES := [
	"sword_light_release", "sword_light_impact", "sword_heavy_release", "sword_heavy_impact",
	"staff_light_release", "staff_heavy_release", "magic_impact",
	"player_normal_hurt", "player_heavy_hurt", "player_death",
	"grunt_release", "grunt_hurt", "grunt_death", "heavy_release", "heavy_hurt", "heavy_death",
]

var _failures: Array[String] = []
var _test_root: Node2D
var _audio_service: CombatAudioService


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_generator_manifest_wav_load_and_hash()
	await _test_resource_profile_bindings()
	await _test_service_deterministic_logs_limits_cleanup_and_test_mode()
	await _test_sword_staff_release_distinct_once()
	await _test_missed_attacks_do_not_log_impact()
	await _test_accepted_and_rejected_melee_and_projectile_impacts()
	await _test_delayed_projectile_uses_original_audio_profile()
	await _test_critical_impact_fallback()
	await _test_player_hurt_death_audio_cases()
	await _test_enemy_release_hurt_death_reset_and_respawn_audio()
	_release_inputs()

	if _failures.is_empty():
		print("Issue #8 combat audio tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_generator_manifest_wav_load_and_hash() -> void:
	var manifest_text := FileAccess.get_file_as_string(MANIFEST_PATH)
	_expect(not manifest_text.is_empty(), "生成器 manifest 存在且可读取")
	var parsed: Variant = JSON.parse_string(manifest_text)
	_expect(parsed is Dictionary, "生成器 manifest 是 JSON 对象")
	if not parsed is Dictionary:
		return
	var manifest := parsed as Dictionary
	_expect(String(manifest.get("generator", "")) == "tools/generate_combat_sfx.py", "manifest 记录生成器路径")
	var format := manifest.get("format", {}) as Dictionary
	_expect(format.get("container") == "WAV", "manifest 记录 WAV 容器")
	_expect(int(format.get("channels", 0)) == 1, "manifest 记录单声道")
	_expect(int(format.get("sample_rate_hz", 0)) == 44100, "manifest 记录 44100Hz")
	_expect(int(format.get("bits_per_sample", 0)) == 16, "manifest 记录 16-bit PCM")
	var cues := manifest.get("cues", []) as Array
	_expect(cues.size() == EXPECTED_CUES.size(), "manifest 包含全部 Issue #8 音效条目")
	var seen := {}
	for entry_variant in cues:
		var entry := entry_variant as Dictionary
		var cue_name := String(entry.get("name", ""))
		seen[cue_name] = true
		var path := String(entry.get("path", ""))
		var sha := String(entry.get("sha256", ""))
		_expect(path.ends_with("%s.wav" % cue_name), "%s manifest 路径指向同名 wav" % cue_name)
		_expect(sha.length() == 64, "%s manifest 记录 sha256" % cue_name)
		var bytes := FileAccess.get_file_as_bytes("res://" + path)
		_expect(bytes.size() > 44, "%s wav 文件可读取" % cue_name)
		if bytes.size() > 44:
			_expect(bytes.slice(0, 4).get_string_from_ascii() == "RIFF", "%s wav RIFF 头正确" % cue_name)
			_expect(bytes.slice(8, 12).get_string_from_ascii() == "WAVE", "%s wav WAVE 头正确" % cue_name)
			_expect(bytes.decode_u16(22) == 1, "%s wav 单声道头正确" % cue_name)
			_expect(bytes.decode_u32(24) == 44100, "%s wav 采样率头正确" % cue_name)
			_expect(bytes.decode_u16(34) == 16, "%s wav 位深头正确" % cue_name)
			_expect(_sha256(bytes) == sha, "%s wav 内容 hash 匹配 manifest" % cue_name)
		var stream := load("res://" + path)
		_expect(stream is AudioStream, "%s wav 可作为 AudioStream 加载" % cue_name)
	for cue_name in EXPECTED_CUES:
		_expect(seen.has(cue_name), "manifest 包含 %s" % cue_name)


func _test_resource_profile_bindings() -> void:
	_assert_attack_profile(SWORD_LIGHT, &"sword_light_release", &"sword_light_impact", &"sword_heavy_impact", "轻剑")
	_assert_attack_profile(SWORD_HEAVY, &"sword_heavy_release", &"sword_heavy_impact", &"sword_heavy_impact", "重剑")
	_assert_attack_profile(STAFF_LIGHT, &"staff_light_release", &"magic_impact", &"magic_impact", "轻法杖")
	_assert_attack_profile(STAFF_HEAVY, &"staff_heavy_release", &"magic_impact", &"magic_impact", "重法杖")
	_expect(PLAYER_AUDIO.normal_hurt_cue.cue_id == &"player_normal_hurt", "玩家普通受击音效绑定")
	_expect(PLAYER_AUDIO.heavy_hurt_cue.cue_id == &"player_heavy_hurt", "玩家重受击音效绑定")
	_expect(PLAYER_AUDIO.death_cue.cue_id == &"player_death", "玩家死亡音效绑定")
	_expect(GRUNT_DEFINITION.audio_profile.normal_hurt_cue.cue_id == &"grunt_hurt", "巡逻敌人受击音效绑定")
	_expect(GRUNT_DEFINITION.audio_profile.death_cue.cue_id == &"grunt_death", "巡逻敌人死亡音效绑定")
	_expect(GRUNT_DEFINITION.melee_attack.audio_profile.release_cue.cue_id == &"grunt_release", "巡逻敌人攻击释放音效绑定")
	_expect(HEAVY_DEFINITION.audio_profile.normal_hurt_cue.cue_id == &"heavy_hurt", "重型敌人受击音效绑定")
	_expect(HEAVY_DEFINITION.audio_profile.death_cue.cue_id == &"heavy_death", "重型敌人死亡音效绑定")
	_expect(HEAVY_DEFINITION.melee_attack.audio_profile.release_cue.cue_id == &"heavy_release", "重型敌人攻击释放音效绑定")


func _test_service_deterministic_logs_limits_cleanup_and_test_mode() -> void:
	_create_world(false)
	_audio_service.pool_size = 2
	_audio_service.test_mode = false
	var owner_a := Node2D.new()
	var owner_b := Node2D.new()
	_test_root.add_child(owner_a)
	_test_root.add_child(owner_b)
	var cue := _make_cue(&"service_limit", 0.0, 2, 1)
	var profile := _attack_audio(cue, cue)
	_expect(_audio_service.request_attack_release(profile, owner_a, Vector2(3, 4)), "service 接受第一次播放")
	_expect(_audio_service.event_log[0][&"accepted"] == true and _audio_service.event_log[0][&"event"] == CombatAudioService.EVENT_RELEASE, "service 记录接受 release 日志")
	_expect(_audio_service.event_log[0][&"owner_id"] == owner_a.get_instance_id(), "service 日志记录 owner")
	_expect(not _audio_service.request_attack_release(profile, owner_a, Vector2.ZERO), "service 拒绝同 owner 并发")
	_expect(_last_reason() == "owner_concurrency", "service 记录 owner 并发拒绝原因")
	_expect(_audio_service.request_attack_release(profile, owner_b, Vector2.ZERO), "service 接受不同 owner 并发")
	var owner_c := Node2D.new()
	_test_root.add_child(owner_c)
	_expect(not _audio_service.request_attack_release(profile, owner_c, Vector2.ZERO), "service 拒绝全局并发超限")
	_expect(_last_reason() == "global_concurrency", "service 记录全局并发拒绝原因")
	owner_a.queue_free()
	await process_frame
	_expect(_audio_service._active_count(_audio_service._active_by_cue, cue.cue_id) == 1, "owner 退出树清理活跃播放器")
	_audio_service._on_player_finished(_audio_service._players[1])
	_expect(_audio_service.request_attack_release(profile, owner_b, Vector2.ZERO), "播放器结束后释放并发槽")
	_audio_service._on_player_finished(_audio_service._players[0])
	_audio_service._on_player_finished(_audio_service._players[1])
	var cooldown_cue := _make_cue(&"cooldown", 5.0, 4, 4)
	var cooldown_profile := _attack_audio(cooldown_cue, null)
	_expect(_audio_service.request_attack_release(cooldown_profile, owner_b, Vector2.ZERO), "service 接受冷却 cue 首次播放")
	_audio_service._on_player_finished(_audio_service._players[0])
	_expect(not _audio_service.request_attack_release(cooldown_profile, owner_b, Vector2.ZERO), "service 拒绝冷却中的 cue")
	_expect(_last_reason() == "cooldown", "service 记录 cooldown 拒绝原因")
	var missing_profile := _attack_audio(null, null)
	_audio_service.fallback_cue = null
	_expect(not _audio_service.request_attack_release(missing_profile, owner_b, Vector2.ZERO), "缺 cue 且无 fallback 时拒绝")
	_expect(_last_reason() == "missing_cue", "缺 cue 记录 missing_cue")
	_audio_service.fallback_cue = _make_cue(&"fallback", 0.0, 4, 4)
	_expect(_audio_service.request_attack_release(missing_profile, owner_b, Vector2.ZERO), "缺 cue 时使用 fallback")
	_audio_service._on_player_finished(_audio_service._players[0])
	_audio_service._on_player_finished(_audio_service._players[1])
	var before := _audio_service.event_log.size()
	_audio_service.test_mode = true
	_expect(_audio_service.request_attack_release(profile, owner_b, Vector2.ZERO), "test_mode 接受播放")
	_expect(_audio_service.event_log.size() == before + 1, "test_mode 只记录一次接受日志")
	_expect(_audio_service._active_by_cue.is_empty(), "test_mode 立即释放活跃计数")
	_audio_service.clear_event_log()
	_expect(_audio_service.event_log.is_empty(), "service 可清空日志")
	await _destroy_world()


func _test_sword_staff_release_distinct_once() -> void:
	_create_world(true)
	var sword_player := _spawn_player(Vector2.ZERO)
	sword_player._request_attack_release_audio(SWORD_LIGHT)
	_expect(_count_events(CombatAudioService.EVENT_RELEASE) == 1, "剑轻攻击释放只记录一次")
	_expect(_last_cue() == &"sword_light_release", "剑轻攻击释放音效正确")
	sword_player._request_attack_release_audio(SWORD_HEAVY)
	_expect(_last_cue() == &"sword_heavy_release", "剑重攻击释放音效不同")
	sword_player._request_attack_release_audio(STAFF_LIGHT)
	_expect(_last_cue() == &"staff_light_release", "法杖轻攻击释放音效不同")
	sword_player._request_attack_release_audio(STAFF_HEAVY)
	_expect(_last_cue() == &"staff_heavy_release", "法杖重攻击释放音效不同")
	await _destroy_world()


func _test_missed_attacks_do_not_log_impact() -> void:
	_create_world(true)
	var player := _spawn_player(Vector2.ZERO)
	player._request_attack_release_audio(SWORD_LIGHT)
	_expect(_count_events(CombatAudioService.EVENT_IMPACT) == 0, "未命中近战不播放 impact")
	# A projectile that never overlaps a hurtbox should not emit hit_confirmed,
	# so combat audio should not receive an impact request.
	await process_frame
	_expect(_count_events(CombatAudioService.EVENT_IMPACT) == 0, "未命中投射物不播放 impact")
	await _destroy_world()


func _test_accepted_and_rejected_melee_and_projectile_impacts() -> void:
	_create_world(true)
	var player := _spawn_player(Vector2.ZERO)
	player._current_attack_profile = SWORD_LIGHT
	player._current_attack_type = Player.AttackType.LIGHT
	player._current_attack_critical = false
	player.current_state = Player.State.ATTACK
	player._on_attack_hit_confirmed(null, 1, player, 1.0)
	_expect(_last_cue() == &"sword_light_impact", "命中近战播放 impact")
	var reject_profile := SWORD_LIGHT.duplicate()
	reject_profile.audio_profile = _attack_audio(null, null)
	player._request_attack_impact_audio(reject_profile, false)
	_expect(_last_reason() == "missing_cue", "缺失近战 impact 记录拒绝")
	_audio_service.clear_event_log()
	var projectile_source := Node.new()
	_test_root.add_child(projectile_source)
	projectile_source.set_script(_AudioProfileSourceScript)
	projectile_source.audio_profile = STAFF_LIGHT.audio_profile
	projectile_source.source_owner = player
	player._current_attack_profile = null
	player.current_state = Player.State.IDLE
	player._on_projectile_hit_confirmed(null, 1, projectile_source, 1.0, Player.AttackType.LIGHT, STAFF_LIGHT.id)
	_expect(_count_events(CombatAudioService.EVENT_IMPACT) == 1, "命中投射物只播放一次 impact")
	_expect(_event_exists(CombatAudioService.EVENT_IMPACT, &"magic_impact"), "命中投射物播放 magic impact")
	var source := Node.new()
	_test_root.add_child(source)
	source.set_script(_AudioProfileSourceScript)
	source.audio_profile = _attack_audio(null, null)
	source.source_owner = player
	player._on_projectile_hit_confirmed(null, 1, source, 1.0, Player.AttackType.LIGHT, &"missing_profile")
	_expect(_last_reason() == "missing_cue", "缺失投射物 impact 记录拒绝")
	await _destroy_world()


func _test_delayed_projectile_uses_original_audio_profile() -> void:
	_create_world(true)
	var player := _spawn_player(Vector2.ZERO)
	var delayed_source := Node.new()
	_test_root.add_child(delayed_source)
	delayed_source.set_script(_AudioProfileSourceScript)
	delayed_source.audio_profile = STAFF_LIGHT.audio_profile
	delayed_source.source_owner = player
	player._on_projectile_hit_confirmed(null, 1, delayed_source, 1.0, Player.AttackType.LIGHT, &"stale_staff_light")
	_expect(_event_exists(CombatAudioService.EVENT_IMPACT, &"magic_impact"), "延迟投射物命中使用投射物保存的原始 profile")
	await _destroy_world()


func _test_critical_impact_fallback() -> void:
	_create_world(true)
	var profile := CombatAttackAudioProfile.new()
	profile.impact_cue = _make_cue(&"normal_only_impact", 0.0, 4, 4)
	profile.critical_impact_cue = null
	_expect(_audio_service.request_attack_impact(profile, _test_root, Vector2.ZERO, true), "暴击缺专用 cue 时回退普通 impact")
	_expect(_last_cue() == &"normal_only_impact", "暴击回退普通 impact cue")
	await _destroy_world()


func _test_player_hurt_death_audio_cases() -> void:
	_create_world(true)
	var player := _spawn_player(Vector2.ZERO)
	player._health = player.get_max_health()
	_expect(player.receive_hit(1, null, 1.0), "玩家普通受击被接受")
	_expect(_last_cue() == &"player_normal_hurt", "玩家普通受击播放普通 hurt")
	player._invulnerability_timer = 0.0
	player._heavy_reaction_protection_timer = 0.0
	_expect(player.receive_hit(4, null, 1.0), "玩家重受击被接受")
	_expect(_last_cue() == &"player_heavy_hurt", "玩家重受击播放 heavy hurt")
	player._invulnerability_timer = 0.0
	player._heavy_reaction_protection_timer = player.heavy_reaction_protection_time
	_expect(player.receive_hit(4, null, 1.0), "玩家保护期重击降级被接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "玩家保护期重击降级为普通反应")
	_expect(_event_exists(CombatAudioService.EVENT_HURT, &"player_normal_hurt"), "玩家保护期降级播放普通 hurt")
	var log_size := _audio_service.event_log.size()
	_expect(not player.receive_hit(1, null, 1.0), "玩家无敌期拒绝受击")
	_expect(_audio_service.event_log.size() == log_size, "玩家无敌期不播放音效")
	player._invulnerability_timer = 0.0
	player._health = 1
	_expect(player.receive_hit(99, null, 1.0), "玩家致死受击被接受")
	await process_frame
	_expect(_last_cue() == &"player_death", "玩家死亡播放 death")
	log_size = _audio_service.event_log.size()
	player._request_death_audio_deferred()
	await process_frame
	_expect(_audio_service.event_log.size() == log_size, "玩家死亡音效只请求一次")
	await _destroy_world()


func _test_enemy_release_hurt_death_reset_and_respawn_audio() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	_expect(await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.ACTIVE), "敌人生效阶段释放攻击音效")
	_expect(_event_exists(CombatAudioService.EVENT_RELEASE, &"grunt_release"), "敌人攻击 active 播放 release")
	enemy.receive_hit(1, player, -1.0)
	_expect(_last_cue() == &"grunt_hurt", "敌人受击播放 hurt")
	enemy.receive_hit(999, player, -1.0)
	await _wait_for_state(enemy, GroundedEnemyController.State.DEAD)
	await process_frame
	_expect(_event_exists(CombatAudioService.EVENT_DEATH, &"grunt_death"), "敌人延迟死亡播放 death")
	var death_count := _count_cue(&"grunt_death")
	enemy._request_death_audio_deferred()
	await process_frame
	_expect(_count_cue(&"grunt_death") == death_count, "敌人死亡音效只请求一次")
	enemy.reset()
	_expect(enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE, "敌人 reset 清理攻击阶段")
	_expect(enemy.current_state == GroundedEnemyController.State.IDLE, "敌人 reset 回到 IDLE")
	await _destroy_world()
	await _assert_enemy_respawn_audio_profile()


func _assert_enemy_respawn_audio_profile() -> void:
	_create_world(true)
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	_test_root.add_child(enemies)
	var manager := EncounterManager.new()
	manager.name = "EncounterManager"
	manager.enemy_scene = ENEMY_SCENE
	manager.target_path = NodePath("../Player")
	manager.enemies_container_path = NodePath("../Enemies")
	var spawn := EnemySpawnDefinition.new()
	spawn.enemy_definition = GRUNT_DEFINITION
	spawn.local_position = Vector2(0.0, FLOOR_Y)
	spawn.facing_direction = 1.0
	spawn.respawn_delay = 0.08
	var group := EnemyGroupDefinition.new()
	group.spawns = [spawn]
	var encounter := EncounterDefinition.new()
	encounter.groups = [group]
	manager.encounter_definition = encounter
	_test_root.add_child(manager)
	await _settle_player(player)
	_expect(await _wait_for_encounter_capacity(manager, 1), "遭遇生成敌人用于音频重生测试")
	var enemy := manager.get_owned_enemies()[0] as GroundedEnemyController
	enemy.receive_hit(999, player, -1.0)
	await _wait_for_state(enemy, GroundedEnemyController.State.DEAD)
	await process_frame
	_expect(_event_exists(CombatAudioService.EVENT_DEATH, &"grunt_death"), "遭遇敌人死亡播放死亡音效")
	_expect(await _wait_for_alive_count(manager, 1, 90), "遭遇敌人按配置重生")
	_audio_service.clear_event_log()
	enemy = manager.get_owned_enemies()[0] as GroundedEnemyController
	enemy.receive_hit(1, player, -1.0)
	_expect(_last_cue() == &"grunt_hurt", "重生敌人保留 hurt 音频 profile")
	await _destroy_world()


func _assert_attack_profile(profile: PlayerBasicAttackProfile, release_id: StringName, impact_id: StringName, critical_id: StringName, label: String) -> void:
	_expect(profile.audio_profile != null, "%s attack profile 绑定音频 profile" % label)
	_expect(profile.audio_profile.release_cue.cue_id == release_id, "%s release cue 绑定正确" % label)
	_expect(profile.audio_profile.impact_cue.cue_id == impact_id, "%s impact cue 绑定正确" % label)
	_expect(profile.audio_profile.cue_for_impact(true).cue_id == critical_id, "%s critical cue 绑定或回退正确" % label)


func _create_combat_world(definition: EnemyDefinition) -> Dictionary:
	_create_world(true)
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
	var enemy := _spawn_enemy(definition, 1.0)
	enemy.set_target(player)
	await _settle_player(player)
	await _wait_until_grounded(enemy)
	return {"player": player, "enemy": enemy}


func _create_world(test_mode := true) -> void:
	_release_inputs()
	_test_root = Node2D.new()
	root.add_child(_test_root)
	_audio_service = CombatAudioService.new()
	_audio_service.name = "CombatAudioService"
	_audio_service.test_mode = test_mode
	_audio_service.pool_size = 8
	_audio_service.add_to_group("combat_audio_service")
	_test_root.add_child(_audio_service)


func _spawn_player(position: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player"
	_test_root.add_child(player)
	player.global_position = position
	return player


func _spawn_enemy(definition: EnemyDefinition, facing := 1.0) -> GroundedEnemyController:
	var enemy := ENEMY_SCENE.instantiate() as GroundedEnemyController
	enemy.definition = definition
	enemy.global_position = Vector2(0.0, FLOOR_Y)
	enemy.start_facing_direction = facing
	enemy.target_path = NodePath()
	_test_root.add_child(enemy)
	return enemy


func _add_platform(position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_test_root.add_child(body)
	return body


func _settle_player(player: Player) -> void:
	await _wait_until_grounded(player)
	await _physics_frames(2)


func _wait_until_grounded(body: CharacterBody2D, maximum_frames := 120) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if is_instance_valid(body) and body.is_on_floor():
			return true
	_expect(false, "角色或敌人在预期时间内接触地面")
	return false


func _wait_for_phase(enemy: GroundedEnemyController, phase: int, maximum_frames := 160) -> bool:
	for _frame in maximum_frames:
		if enemy.get_attack_phase() == phase:
			return true
		await physics_frame
	_expect(false, "敌人在预期时间内进入攻击阶段 %d" % phase)
	return false


func _wait_for_state(enemy: GroundedEnemyController, state: int, maximum_frames := 180) -> bool:
	for _frame in maximum_frames:
		if enemy.current_state == state:
			return true
		await physics_frame
	_expect(false, "敌人在预期时间内进入状态 %d" % state)
	return false


func _wait_for_encounter_capacity(manager: EncounterManager, capacity: int, maximum_frames := 60) -> bool:
	for _frame in maximum_frames:
		if manager.get_capacity() == capacity:
			return true
		await process_frame
	return false


func _wait_for_alive_count(manager: EncounterManager, count: int, maximum_frames := 60) -> bool:
	for _frame in maximum_frames:
		if manager.get_alive_count() == count:
			return true
		await process_frame
	return false


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _destroy_world() -> void:
	_release_inputs()
	if _test_root != null and is_instance_valid(_test_root):
		_test_root.queue_free()
	await process_frame
	_test_root = null
	_audio_service = null


func _release_inputs() -> void:
	if Engine.has_singleton("Input"):
		for action in GameSession.GAMEPLAY_INPUT_ACTIONS:
			Input.action_release(action)
		Input.flush_buffered_events()


func _make_cue(cue_id: StringName, cooldown := 0.0, max_global := 4, max_owner := 1, extra_cooldown := -1.0) -> AudioCueDefinition:
	var cue := AudioCueDefinition.new()
	cue.cue_id = cue_id
	cue.streams = [AudioStreamWAV.new()]
	cue.cooldown_time = extra_cooldown if extra_cooldown >= 0.0 else cooldown
	cue.max_concurrent_global = max_global
	cue.max_concurrent_per_owner = max_owner
	return cue


func _attack_audio(release_cue: AudioCueDefinition, impact_cue: AudioCueDefinition) -> CombatAttackAudioProfile:
	var profile := CombatAttackAudioProfile.new()
	profile.release_cue = release_cue
	profile.impact_cue = impact_cue
	return profile


func _last_event() -> Dictionary:
	return _audio_service.event_log.back() as Dictionary if _audio_service != null and not _audio_service.event_log.is_empty() else {}


func _last_reason() -> String:
	return String(_last_event().get(&"reason", ""))


func _last_cue() -> StringName:
	var event := _last_event()
	if not bool(event.get(&"accepted", false)) and _audio_service != null and _audio_service.event_log.size() >= 2:
		event = _audio_service.event_log[_audio_service.event_log.size() - 2]
	return StringName(event.get(&"cue_id", &""))


func _count_events(event_type: StringName) -> int:
	var count := 0
	for entry in _audio_service.event_log:
		if entry.get(&"event") == event_type:
			count += 1
	return count


func _count_cue(cue_id: StringName) -> int:
	var count := 0
	for entry in _audio_service.event_log:
		if entry.get(&"cue_id") == cue_id:
			count += 1
	return count


func _event_exists(event_type: StringName, cue_id: StringName) -> bool:
	for entry in _audio_service.event_log:
		if entry.get(&"event") == event_type and entry.get(&"cue_id") == cue_id and bool(entry.get(&"accepted", false)):
			return true
	return false


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


class _AudioProfileSourceScript:
	extends Node
	var audio_profile: CombatAttackAudioProfile
	var source_owner: Node
	func get_audio_profile() -> CombatAttackAudioProfile:
		return audio_profile
	func get_source() -> Node:
		return source_owner
	func get_credit_owner() -> Node:
		return source_owner
