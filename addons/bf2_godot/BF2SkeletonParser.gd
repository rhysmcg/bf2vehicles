# BF2SkeletonParser.gd
# Parses BF2 .ske skeleton files and builds a Godot Skeleton3D.
# Based on bf2_skeleton.py (bf2-blender) - but simplified for Godot:
# Skeleton3D.set_bone_rest() takes a PARENT-RELATIVE transform, so unlike the Blender
# importer we do NOT need to accumulate armature-space matrices or do any bone-direction
# fixing (that was only needed for Blender's head/tail/roll edit-bone representation).

extends RefCounted

class SkeletonNode:
	var index: int = -1
	var name: String = ""
	var pos: Vector3 = Vector3.ZERO
	var rot: Quaternion = Quaternion.IDENTITY  # parent-relative
	var parent_index: int = -1
	var parent: SkeletonNode = null
	var children: Array = []  # Array of SkeletonNode

# --- MAIN PARSING FUNCTION ---

func parse_skeleton(filepath: String) -> Dictionary:
	var ske_data = {
		"name": filepath.get_file().get_basename(),
		"nodes": [],       # Array of SkeletonNode, indexed EXACTLY by file order (node.index)
		"roots": [],        # Array of SkeletonNode with no parent
		"version": 0
	}
	
	if not FileAccess.file_exists(filepath):
		push_error("File not found: %s" % filepath)
		return ske_data
	
	print("\n=== Parsing BF2 Skeleton: %s ===" % filepath.get_file())
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("Error opening file: %s" % FileAccess.get_open_error())
		return ske_data
	
	file.big_endian = false
	
	var version: int = file.get_32()
	if version != 2:
		push_error("Unsupported .ske version %d (expected 2)" % version)
		file.close()
		return ske_data
	
	ske_data.version = version
	
	var node_count: int = file.get_32()
	print("Node Count: %d" % node_count)
	
	var nodes: Array = []
	var parent_indices: Array = []
	
	for i in range(node_count):
		var node = SkeletonNode.new()
		node.index = i
		
		var name_char_count: int = file.get_16()
		var name_bytes := PackedByteArray()
		for c in range(name_char_count):
			name_bytes.append(file.get_8())
		var node_name := name_bytes.get_string_from_ascii()
		if node_name.ends_with("\\x00"):
			node_name = node_name.substr(0, node_name.length() - 1)
		node.name = node_name
		
		# Signed 16-bit parent index (-1 = root)
		var raw_parent: int = file.get_16()
		var parent_index: int = raw_parent
		if parent_index >= 32768:
			parent_index -= 65536
		node.parent_index = parent_index
		
		# Quaternion (x, y, z, w), then INVERTED (conjugate) per BF2 convention
		var qx: float = file.get_float()
		var qy: float = file.get_float()
		var qz: float = file.get_float()
		var qw: float = file.get_float()
		node.rot = Quaternion(-qx, -qy, -qz, qw)  # conjugate = inverse for unit quats
		
		# Position (relative to parent)
		var px: float = file.get_float()
		var py: float = file.get_float()
		var pz: float = file.get_float()
		node.pos = Vector3(px, py, pz)
		
		nodes.append(node)
		parent_indices.append(parent_index)
		
		print("  [%d] '%s' parent=%d pos=%s" % [i, node.name, parent_index, node.pos])
	
	# Link parent/child relationships
	for i in range(node_count):
		var node: SkeletonNode = nodes[i]
		var parent_index: int = parent_indices[i]
		if parent_index == -1:
			ske_data.roots.append(node)
		elif parent_index >= 0 and parent_index < node_count:
			node.parent = nodes[parent_index]
			nodes[parent_index].children.append(node)
		else:
			push_error("Invalid .ske file: bad parent index %d for node %d" % [parent_index, i])
	
	if ske_data.roots.size() == 0:
		push_error("Invalid .ske file: no root node found")
	
	ske_data.nodes = nodes
	
	if file.get_length() != file.get_position():
		push_warning("File pointer (%d) != file size (%d)" % [file.get_position(), file.get_length()])
	
	file.close()
	
	print("=== Parsing Complete: %d nodes, %d root(s) ===\n" % [node_count, ske_data.roots.size()])
	return ske_data

# --- SKELETON3D CONSTRUCTION ---

# Builds a Godot Skeleton3D from parsed .ske data.
#
# IMPORTANT: bones are added in TWO passes, both strictly in original file-index order,
# so that Skeleton3D bone_idx == node.index for every bone. This matters because mesh
# skin data (rigs: Array of {"id", "matrix"}) reference bones by their ORIGINAL file
# index - if we reordered bones (e.g. via BFS) that correspondence would be lost and
# we'd need a separate id -> bone_idx lookup table. Adding all bones first (pass 1)
# then linking parents (pass 2) avoids needing "parent already added" ordering, since
# set_bone_parent() just needs both bone indices to already exist, not any particular
# insertion order.
func build_skeleton3d(parsed_data: Dictionary) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = parsed_data.name
	
	var nodes: Array = parsed_data.nodes
	if nodes.size() == 0:
		push_error("No skeleton nodes to build from")
		return skeleton
	
	# Pass 1: add every bone, in file order.
	for node in nodes:
		var bone_idx: int = skeleton.add_bone(node.name)
		if bone_idx != node.index:
			push_warning("Bone index mismatch: added '%s' at %d, expected %d - skin binding will break!" % [node.name, bone_idx, node.index])
	
	# Pass 2: link parents + set rest/pose now that every bone exists.
	for node in nodes:
		if node.parent != null:
			skeleton.set_bone_parent(node.index, node.parent.index)
		
		var rest := Transform3D(Basis(node.rot), node.pos)
		skeleton.set_bone_rest(node.index, rest)
		skeleton.set_bone_pose_position(node.index, node.pos)
		skeleton.set_bone_pose_rotation(node.index, node.rot)
	
	print("Built Skeleton3D '%s' with %d bones (bone_idx == original .ske node index)" % [skeleton.name, skeleton.get_bone_count()])
	return skeleton

# --- CONVENIENCE FUNCTION ---

func import_skeleton(filepath: String) -> Skeleton3D:
	var parsed_data = parse_skeleton(filepath)
	if parsed_data.nodes.size() == 0:
		return null
	return build_skeleton3d(parsed_data)
