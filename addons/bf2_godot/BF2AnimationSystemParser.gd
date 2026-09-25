# BF2AnimationSystemParser.gd
# Parses BF2 AnimationSystemXp.inc files (the soldier animation state-machine format)
# and ValueHolders.inc.
#
# Produces three structures from an .inc file:
#   - animations: individual .baf clips, keyed by normalized (lowercase) path, with
#     per-clip looping/length/fadeInTime overrides (default looping = true).
#   - bundles: named groups that sequence one or more clips, each with an optional
#     start_time offset (used to stitch e.g. jump start/loop/end into one timeline),
#     plus bundle-level fade/playback properties.
#   - triggers: the nested state-machine graph (addBundle/addChild/valueHolder) -
#     PARSED for completeness/future use, but NOT currently used to build any
#     runtime blend logic. That graph is driven by live gameplay input (movement
#     speed, turn rate, etc. via ValueHolders) which this importer has no source
#     for yet (no character controller) - wiring it up is a distinct future step.

extends RefCounted

func parse(filepath: String) -> Dictionary:
	var result = {
		"animations": {},  # normalized_path -> {looping, length, fade_in}
		"bundles": {},      # bundle_name -> {fade_in, fade_out, is_looping, play_backward,
							#                 abrupt_playback, jump_to_last, clips: [{path, start_time}]}
		"triggers": {}      # trigger_name -> {type, bundles: [], children: [], value_holder, params: {}}
	}
	
	if not FileAccess.file_exists(filepath):
		push_error("File not found: %s" % filepath)
		return result
	
	print("\n=== Parsing Animation System: %s ===" % filepath.get_file())
	
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("Error opening file: %s" % FileAccess.get_open_error())
		return result
	
	var current_animation_path: String = ""
	var current_bundle_name: String = ""
	var current_trigger_name: String = ""
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("rem") or line.begins_with("//"):
			continue
		
		var parts = line.split(' ')
		var cmd = parts[0]
		
		if cmd == "animationSystem.createAnimation":
			current_animation_path = parts[1].to_lower()
			result.animations[current_animation_path] = {
				"looping": true,
				"length": -1.0,
				"fade_in": 0.0
			}
			current_bundle_name = ""
			current_trigger_name = ""
		
		elif cmd == "animationManager.looping":
			if current_animation_path != "":
				result.animations[current_animation_path]["looping"] = (int(parts[1]) != 0)
		
		elif cmd == "animationManager.length":
			if current_animation_path != "":
				result.animations[current_animation_path]["length"] = float(parts[1])
		
		elif cmd == "animationManager.fadeInTime":
			if current_animation_path != "":
				result.animations[current_animation_path]["fade_in"] = float(parts[1])
		
		elif cmd == "animationSystem.createBundle":
			current_bundle_name = parts[1]
			result.bundles[current_bundle_name] = {
				"fade_in": 0.0,
				"fade_out": 0.0,
				"is_looping": true,
				"play_backward": false,
				"abrupt_playback": false,
				"jump_to_last": false,
				"clips": []
			}
			current_animation_path = ""
			current_trigger_name = ""
		
		elif cmd == "animationBundle.fadeInTime":
			if current_bundle_name != "":
				result.bundles[current_bundle_name]["fade_in"] = float(parts[1])
		
		elif cmd == "animationBundle.fadeOutTime":
			if current_bundle_name != "":
				result.bundles[current_bundle_name]["fade_out"] = float(parts[1])
		
		elif cmd == "animationBundle.isLooping":
			if current_bundle_name != "":
				result.bundles[current_bundle_name]["is_looping"] = (int(parts[1]) != 0)
		
		elif cmd == "animationBundle.playBackward":
			if current_bundle_name != "":
				result.bundles[current_bundle_name]["play_backward"] = (int(parts[1]) != 0)
		
		elif cmd == "animationBundle.abruptPlayback":
			if current_bundle_name != "":
				result.bundles[current_bundle_name]["abrupt_playback"] = (int(parts[1]) != 0)
		
		elif cmd == "animationBundle.jumpToLastAnimationAtStop":
			if current_bundle_name != "":
				result.bundles[current_bundle_name]["jump_to_last"] = (int(parts[1]) != 0)
		
		elif cmd == "animationBundle.addAnimation":
			if current_bundle_name != "":
				var anim_path = parts[1].to_lower()
				result.bundles[current_bundle_name]["clips"].append({"path": anim_path, "start_time": 0.0})
		
		elif cmd == "animationBundle.setAnimationStartTime":
			if current_bundle_name != "" and parts.size() >= 3:
				var anim_path = parts[1].to_lower()
				var start_time = float(parts[2])
				for clip in result.bundles[current_bundle_name]["clips"]:
					if clip["path"] == anim_path:
						clip["start_time"] = start_time
		
		elif cmd == "animationSystem.createTrigger":
			if parts.size() >= 3:
				var trigger_type = parts[1]
				current_trigger_name = parts[2]
				result.triggers[current_trigger_name] = {
					"type": trigger_type,
					"bundles": [],
					"children": [],
					"value_holder": "",
					"params": {}
				}
				current_animation_path = ""
				current_bundle_name = ""
		
		elif cmd == "animationTrigger.addBundle":
			if current_trigger_name != "":
				result.triggers[current_trigger_name]["bundles"].append(parts[1])
		
		elif cmd == "animationTrigger.addChild":
			if current_trigger_name != "":
				result.triggers[current_trigger_name]["children"].append(parts[1])
		
		elif cmd == "animationTrigger.valueHolder":
			if current_trigger_name != "":
				result.triggers[current_trigger_name]["value_holder"] = parts[1]
		
		elif cmd.begins_with("animationTrigger."):
			# Catch-all for other per-trigger params (fadeInTime, idleTime, message,
			# stopOnMessage, etc.) - stored raw, not consumed by any logic yet.
			if current_trigger_name != "" and parts.size() >= 2:
				var param_name = cmd.substr("animationTrigger.".length())
				result.triggers[current_trigger_name]["params"][param_name] = parts[1]
	
	file.close()
	
	print("Parsed: %d animation(s), %d bundle(s), %d trigger(s)\n" % [result.animations.size(), result.bundles.size(), result.triggers.size()])
	return result

# Parses ValueHolders.inc. Each entry has 3 float values whose exact semantics are
# unconfirmed - plausibly (blend_start, blend_full, scale_or_cap) mapped against a
# live gameplay parameter (movement speed, turn rate) by the Trigger graph. Not
# currently consumed by any blend logic - parsed for completeness/future use.
func parse_value_holders(filepath: String) -> Dictionary:
	var result = {}  # name -> {"values": [a,b,c], "stop_on_message": int, "pass_on_message": int}
	
	if not FileAccess.file_exists(filepath):
		push_error("File not found: %s" % filepath)
		return result
	
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("Error opening file: %s" % FileAccess.get_open_error())
		return result
	
	var current_name: String = ""
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("rem"):
			continue
		var parts = line.split(' ')
		var cmd = parts[0]
		
		if cmd == "AnimationSystem.createValueHolder":
			current_name = parts[1]
			result[current_name] = {"values": [0.0, 0.0, 0.0], "stop_on_message": -1, "pass_on_message": -1}
		elif cmd == "AnimationValueHolder.values":
			if current_name != "" and parts.size() >= 4:
				result[current_name]["values"] = [float(parts[1]), float(parts[2]), float(parts[3])]
		elif cmd == "AnimationValueHolder.stopOnMessage":
			if current_name != "":
				result[current_name]["stop_on_message"] = int(parts[1])
		elif cmd == "AnimationValueHolder.passOnMessage":
			if current_name != "":
				result[current_name]["pass_on_message"] = int(parts[1])
	
	file.close()
	return result
