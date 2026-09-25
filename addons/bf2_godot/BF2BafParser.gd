# BF2BafParser.gd
# Parses BF2 .baf skeletal animation files and builds a Godot Animation resource
# targeting Skeleton3D bone tracks. Based on bf2_animation.py (bf2-blender).
#
# .baf stores per-bone, per-channel (rotation x/y/z/w, position x/y/z) keyframe
# streams, RLE-compressed, as 16-bit fixed-point values. Bone IDs match the original
# .ske file's node index (same convention BF2SkeletonParser preserves as bone_idx),
# so bone names are resolved directly via skeleton.get_bone_name(bone_id).

extends RefCounted

# Converts a 16-bit fixed-point encoded value back to a float, given a bit precision.
# Mirrors float_16_to_32() from bf2_animation.py exactly.
func _float16_to_32(word: int, precision: int) -> float:
	var flt16_mult: float = 32767.0 / float(1 << (15 - precision))
	var w: int = word
	if w > 32767:
		w -= 0xFFFF
	return float(w) / flt16_mult

# --- MAIN PARSING FUNCTION ---

func parse_baf(filepath: String) -> Dictionary:
	var anim_data = {
		"frame_num": 0,
		"bones": {}  # bone_id (int) -> Array of {"pos": Vector3, "rot": Quaternion}, length frame_num
	}
	
	if not FileAccess.file_exists(filepath):
		push_error("File not found: %s" % filepath)
		return anim_data
	
	print("\n=== Parsing BF2 Animation: %s ===" % filepath.get_file())
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("Error opening file: %s" % FileAccess.get_open_error())
		return anim_data
	
	file.big_endian = false
	
	var version: int = file.get_32()
	if version != 4:
		push_error("Unsupported .baf version %d (expected 4)" % version)
		file.close()
		return anim_data
	
	var bone_num: int = file.get_16()
	var bone_ids: Array = []
	for i in range(bone_num):
		bone_ids.append(file.get_16())
	
	var frame_num: int = file.get_32()
	var precision: int = file.get_8()
	
	anim_data.frame_num = frame_num
	
	print("Bones: %d, Frames: %d, Precision: %d" % [bone_num, frame_num, precision])
	
	for bone_id in bone_ids:
		# Parallel per-channel arrays (avoids any ambiguity around mutating individual
		# Vector3/Quaternion components on a stored object property in GDScript).
		var rx := PackedFloat32Array(); rx.resize(frame_num)
		var ry := PackedFloat32Array(); ry.resize(frame_num)
		var rz := PackedFloat32Array(); rz.resize(frame_num)
		var rw := PackedFloat32Array(); rw.resize(frame_num)
		var px := PackedFloat32Array(); px.resize(frame_num)
		var py := PackedFloat32Array(); py.resize(frame_num)
		var pz := PackedFloat32Array(); pz.resize(frame_num)
		for idx in range(frame_num):
			rw[idx] = 1.0  # safe identity default in case a frame is never written
		
		var data_size: int = file.get_16()  # informational only, not needed for decode
		
		var corrupted := false
		for j in range(1, 8):
			var cur_frame: int = 0
			var data_left: int = file.get_16()
			
			while data_left > 0:
				var head: int = file.get_8()
				var rle_compression: bool = bool((head & 0x80) >> 7)
				var num_frames: int = head & 0x7F
				var next_header: int = file.get_8()
				
				var bone_frame_num: int = cur_frame + num_frames - 1
				if bone_frame_num >= frame_num:
					push_error("Corrupted .baf: frame number for bone %d (%d) exceeds max %d" % [bone_id, bone_frame_num, frame_num])
					corrupted = true
					break
				
				var value: int = 0
				if rle_compression:
					value = file.get_16()
				
				for n in range(num_frames):
					if not rle_compression:
						value = file.get_16()
					
					match j:
						1: rx[cur_frame] = -_float16_to_32(value, 15)
						2: ry[cur_frame] = -_float16_to_32(value, 15)
						3: rz[cur_frame] = -_float16_to_32(value, 15)
						4: rw[cur_frame] = _float16_to_32(value, 15)
						5: px[cur_frame] = _float16_to_32(value, precision)
						6: py[cur_frame] = _float16_to_32(value, precision)
						7: pz[cur_frame] = _float16_to_32(value, precision)
					
					cur_frame += 1
				
				data_left -= next_header
			
			if corrupted:
				break
		
		if corrupted:
			file.close()
			return anim_data
		
		var frames: Array = []
		for f in range(frame_num):
			var q := Quaternion(rx[f], ry[f], rz[f], rw[f])
			frames.append({"pos": Vector3(px[f], py[f], pz[f]), "rot": q.normalized()})
		
		anim_data.bones[bone_id] = frames
	
	if file.get_length() != file.get_position():
		push_warning("File pointer (%d) != file size (%d)" % [file.get_position(), file.get_length()])
	
	file.close()
	
	print("=== Parsing Complete: %d bone(s) animated, %d frames ===\n" % [anim_data.bones.size(), frame_num])
	return anim_data

# --- ANIMATION CONSTRUCTION ---

# Builds a Godot Animation resource with a position + rotation track per animated
# bone, using bone NAMES resolved from the given Skeleton3D (bone_idx == .baf's raw
# bone id, guaranteed by BF2SkeletonParser). skeleton_track_path is the NodePath to
# the Skeleton3D, relative to wherever the AnimationPlayer's root_node points -
# e.g. NodePath("Skeleton3D_3P") if the AnimationPlayer is a sibling of the skeleton.
func build_animation(anim_data: Dictionary, skeleton: Skeleton3D, skeleton_track_path: NodePath, fps: float = 30.0) -> Animation:
	var animation := Animation.new()
	animation.length = float(anim_data.frame_num) / fps
	
	for bone_id in anim_data.bones.keys():
		if bone_id < 0 or bone_id >= skeleton.get_bone_count():
			push_warning(".baf references bone id %d outside skeleton bone count (%d) - skipping" % [bone_id, skeleton.get_bone_count()])
			continue
		
		var bone_name: String = skeleton.get_bone_name(bone_id)
		var frames: Array = anim_data.bones[bone_id]
		
		var pos_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(pos_track, NodePath(str(skeleton_track_path) + ":" + bone_name))
		
		var rot_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rot_track, NodePath(str(skeleton_track_path) + ":" + bone_name))
		
		for f in range(frames.size()):
			var t: float = float(f) / fps
			animation.position_track_insert_key(pos_track, t, frames[f]["pos"])
			animation.rotation_track_insert_key(rot_track, t, frames[f]["rot"])
	
	print("Built Animation with %d bone track pair(s), length %.3fs @ %.1f fps" % [anim_data.bones.size(), animation.length, fps])
	return animation

# --- CONVENIENCE FUNCTION ---

func import_animation(baf_filepath: String, skeleton: Skeleton3D, skeleton_track_path: NodePath, fps: float = 30.0) -> Animation:
	var parsed := parse_baf(baf_filepath)
	if parsed.bones.size() == 0:
		return null
	var anim := build_animation(parsed, skeleton, skeleton_track_path, fps)
	anim.resource_name = baf_filepath.get_file().get_basename()
	return anim
