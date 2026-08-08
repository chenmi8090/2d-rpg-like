class_name ActorAudioProfile
extends Resource

@export var normal_hurt_cue: AudioCueDefinition
@export var heavy_hurt_cue: AudioCueDefinition
@export var death_cue: AudioCueDefinition


func cue_for_hurt(heavy: bool) -> AudioCueDefinition:
	if heavy and heavy_hurt_cue != null:
		return heavy_hurt_cue
	return normal_hurt_cue
