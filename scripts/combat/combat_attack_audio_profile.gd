class_name CombatAttackAudioProfile
extends Resource

@export var release_cue: AudioCueDefinition
@export var impact_cue: AudioCueDefinition
@export var critical_impact_cue: AudioCueDefinition


func cue_for_impact(is_critical: bool) -> AudioCueDefinition:
	if is_critical and critical_impact_cue != null:
		return critical_impact_cue
	return impact_cue
