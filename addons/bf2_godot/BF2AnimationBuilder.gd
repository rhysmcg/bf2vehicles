# BF2AnimationBuilder.gd
# Shared logic: builds an AnimationLibrary + AnimationNodeStateMachine from a parsed
# BF2 AnimationSystemXp.inc file, against a given skeleton. The soldier body (at
# import time, via conParser2) and weapons (at runtime, when equipped) use the exact
# same .inc/.baf structure and clip/bundle rules, so this is shared rather than
# duplicated between them.
#
# Plain RefCounted (not @tool-only) - safe to use at runtime in a regular game script,
# not just from the editor importer.

extends RefCounted

# Returns {"library": AnimationLibrary, "state_machine": AnimationNodeStateMachine,
#          "clip_count": int, "bundle_count": int}.
# On failure (missing file), "library" and "state_machine" are both null.
func build(inc_path: String, skeleton: Skeleton3D) -> Dictionary:
	var result = {"library": null, "state_machine": null, "clip_count": 0, "bundle_count": 0}
	
	if not FileAccess.file_exists(inc_path):
		push_error("Animation system file not found: %s" % inc_path)
		return result
	
	var sys_parser = preload("res://addons/bf2_godot/BF2AnimationSystemParser.gd").new()
	var anim_system = sys_parser.parse(inc_path)
	
	var baf_parser = preload("res://addons/bf2_godot/BF2BafParser.gd").new()
	var lib := AnimationLibrary.new()
	var clip_animations: Dictionary = {}
	
	for anim_path in anim_system["animations"].keys():
		var full_path = "res://" + anim_path
		if not FileAccess.file_exists(full_path):
			print("    WARNING: .baf not found: %s" % full_path)
			continue
		
		var anim: Animation = baf_parser.import_animation(full_path, skeleton, NodePath(skeleton.name))
		if anim == null:
			continue
		
		var settings = anim_system["animations"][anim_path]
		anim.loop_mode = Animation.LOOP_LINEAR if settings["looping"] else Animation.LOOP_NONE
		if settings["length"] > 0.0:
			anim.length = settings["length"]
		
		var clip_name: String = anim_path.get_file().get_basename()
		anim.resource_name = clip_name
		clip_animations[anim_path] = anim
		lib.add_animation(clip_name, anim)
	
	result["clip_count"] = clip_animations.size()
	print("  Imported %d/%d individual animation clip(s) from %s" % [clip_animations.size(), anim_system["animations"].size(), inc_path.get_file()])
	
	# Build a node per bundle - alias for single-clip bundles, a merged sequential
	# composite for bundles with explicit setAnimationStartTime offsets (e.g. jump
	# start/loop/end), or an AnimationNodeBlendSpace2D for multi-clip bundles with
	# NO explicit timing (directional movement blends like "stand_run").
	var bundle_nodes: Dictionary = {}
	
	for bundle_name in anim_system["bundles"].keys():
		var bundle = anim_system["bundles"][bundle_name]
		if bundle["clips"].size() == 0:
			continue
		
		if bundle["clips"].size() == 1:
			var clip_path = bundle["clips"][0]["path"]
			if clip_animations.has(clip_path):
				var anim_node := AnimationNodeAnimation.new()
				anim_node.animation = clip_animations[clip_path].resource_name
				bundle_nodes[bundle_name] = anim_node
			continue
		
		var has_explicit_timing := false
		for clip_ref in bundle["clips"]:
			if clip_ref["start_time"] != 0.0:
				has_explicit_timing = true
				break
		
		if has_explicit_timing:
			var composite := Animation.new()
			composite.loop_mode = Animation.LOOP_LINEAR if bundle["is_looping"] else Animation.LOOP_NONE
			var max_end_time := 0.0
			
			for clip_ref in bundle["clips"]:
				if not clip_animations.has(clip_ref["path"]):
					continue
				var src: Animation = clip_animations[clip_ref["path"]]
				var offset: float = clip_ref["start_time"]
				
				for t in range(src.get_track_count()):
					var track_type = src.track_get_type(t)
					var track_path = src.track_get_path(t)
					
					var dest_track = composite.find_track(track_path, track_type)
					if dest_track < 0:
						dest_track = composite.add_track(track_type)
						composite.track_set_path(dest_track, track_path)
					
					for k in range(src.track_get_key_count(t)):
						var key_time: float = src.track_get_key_time(t, k) + offset
						var key_value = src.track_get_key_value(t, k)
						if track_type == Animation.TYPE_POSITION_3D:
							composite.position_track_insert_key(dest_track, key_time, key_value)
						elif track_type == Animation.TYPE_ROTATION_3D:
							composite.rotation_track_insert_key(dest_track, key_time, key_value)
						max_end_time = max(max_end_time, key_time)
			
			composite.length = max_end_time
			composite.resource_name = bundle_name
			lib.add_animation(bundle_name, composite)
			var anim_node := AnimationNodeAnimation.new()
			anim_node.animation = bundle_name
			bundle_nodes[bundle_name] = anim_node
		else:
			var blend_space := AnimationNodeBlendSpace2D.new()
			for clip_ref in bundle["clips"]:
				if not clip_animations.has(clip_ref["path"]):
					continue
				var clip_name: String = clip_animations[clip_ref["path"]].resource_name
				var point_node := AnimationNodeAnimation.new()
				point_node.animation = clip_name
				blend_space.add_blend_point(point_node, _direction_point_for_clip(clip_name))
			bundle_nodes[bundle_name] = blend_space
	
	result["bundle_count"] = bundle_nodes.size()
	print("  Built %d bundle node(s) from %s" % [bundle_nodes.size(), inc_path.get_file()])
	
	var state_machine := AnimationNodeStateMachine.new()
	var grid_col := 0
	var grid_row := 0
	const GRID_SPACING_X := 220.0
	const GRID_SPACING_Y := 160.0
	const GRID_COLUMNS := 5
	
	for bundle_name in bundle_nodes.keys():
		var pos := Vector2(grid_col * GRID_SPACING_X, grid_row * GRID_SPACING_Y)
		state_machine.add_node(bundle_name, bundle_nodes[bundle_name], pos)
		grid_col += 1
		if grid_col >= GRID_COLUMNS:
			grid_col = 0
			grid_row += 1
	
	result["library"] = lib
	result["state_machine"] = state_machine
	return result

# Infers a 2D blend-space direction for a clip based on its filename. x = left(-1)/
# right(+1), y = backward(-1)/forward(+1). Matches BF2's directional movement clip
# naming (e.g. 3p_runForward, 3p_m4_strafeLeft).
func _direction_point_for_clip(clip_name: String) -> Vector2:
	var n := clip_name.to_lower()
	if n.contains("forward"):
		return Vector2(0, 1)
	elif n.contains("backward"):
		return Vector2(0, -1)
	elif n.contains("strafeleft") or n.contains("walkleft"):
		return Vector2(-1, 0)
	elif n.contains("straferight") or n.contains("walkright"):
		return Vector2(1, 0)
	elif n.ends_with("left") and not n.contains("turn"):
		return Vector2(-1, 0)
	elif n.ends_with("right") and not n.contains("turn"):
		return Vector2(1, 0)
	return Vector2.ZERO
