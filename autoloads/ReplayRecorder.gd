extends Node

# Stub. Phase 3 wires this up to actually write JSONL. CommandBus already
# calls into us, so the stub keeps the recording path null-safe until then.

var is_recording: bool = false
var is_playing: bool = false


func record_command(_kind: String, _actor, _args: Dictionary, _src: String) -> void:
	# Phase 3: append to JSONL.
	pass
