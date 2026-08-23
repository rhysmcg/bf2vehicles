# test_mesh_parser.gd
@tool
extends EditorScript

# This function is executed when you right-click the script and select "Run".
func _run():
	fix_dds_header("res://objects/staticobjects/common/roads/textures/cityroad_c.dds")
##   ERROR: Expected Image data size of 512x512x1 (DXT1 RGB8 with 9 mipmaps) = 174776 bytes, got 174080 bytes instead.

 
func fix_dds_header(filepath: String) -> bool:
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return false
	
	var data = file.get_buffer(file.get_length())
	file.close()
	
	# Check if it's a DDS file
	if data.slice(0, 4).get_string_from_ascii() != "DDS ":
		return false
	
	# Calculate correct size (total file size - 128 byte header)
	var correct_size = data.size() - 128
	
	# Write correct size to dwPitchOrLinearSize (bytes 20-23)
	var size_bytes = PackedByteArray()
	size_bytes.resize(4)
	size_bytes.encode_u32(0, correct_size)
	
	# Replace bytes 20-23 in the header
	for i in range(4):
		data[20 + i] = size_bytes[i]
	
	# Write back
	file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_buffer(data)
	file.close()
	
	print("Fixed: %s (set size to %d)" % [filepath, correct_size])
	return true
