# dds_permissive_importer.gd
# Place this in addons/dds_permissive/dds_permissive_importer.gd
@tool
extends EditorImportPlugin

func _get_importer_name():
	return "dds_permissive"

func _get_visible_name():
	return "DDS Permissive"

func _get_recognized_extensions():
	return ["dds"]

func _get_save_extension():
	return "res"

func _get_resource_type():
	return "Texture2D"

func _get_preset_count():
	return 1

func _get_preset_name(preset_index):
	return "Default"

func _get_priority():
	return 10.0

func _get_import_order():
	return IMPORT_ORDER_SCENE

func _get_import_options(path, preset_index):
	return [
		{"name": "mipmaps/generate", "default_value": true}
	]

func _get_option_visibility(path, option_name, options):
	return true

func _import(source_file, save_path, options, platform_variants, gen_files):
	var file = FileAccess.open(source_file, FileAccess.READ)
	if not file:
		return ERR_FILE_CANT_OPEN
	
	var data = file.get_buffer(file.get_length())
	file.close()
	
	if data.size() < 128:
		push_error("DDS file too small")
		return ERR_FILE_CORRUPT
	
	# DDS 'magic' identifier is 4 bytes 'DDS '
	if data.slice(0, 4).get_string_from_ascii() != "DDS ":
		push_error("Not a valid DDS file")
		return ERR_FILE_CORRUPT
	
	print("\n=== DDS Import: %s ===" % source_file.get_file())
	
	# Parse header
	var height = data.decode_u32(12)
	var width = data.decode_u32(16)
	var pitch_or_linear_size = data.decode_u32(20)
	var mipmap_count = data.decode_u32(28)
	var pixelformat_flags = data.decode_u32(80)  # dwFlags in DDS_PIXELFORMAT
	
	# Read FourCC (might be null bytes or spaces)
	var fourcc_bytes = data.slice(84, 88)
	var fourcc = fourcc_bytes.get_string_from_ascii().strip_edges()
	
	# Also check raw bytes for DXT formats (DDS is little-endian)
	var fourcc_raw = data.decode_u32(84)
	if fourcc_raw == 0x31545844:  # "DXT1" in hex
		fourcc = "DXT1"
	elif fourcc_raw == 0x33545844:  # "DXT3" in hex
		fourcc = "DXT3"
	elif fourcc_raw == 0x35545844:  # "DXT5" in hex
		fourcc = "DXT5"
	
	var rgb_bit_count = data.decode_u32(88)
	var r_bitmask = data.decode_u32(92)
	var g_bitmask = data.decode_u32(96)
	var b_bitmask = data.decode_u32(100)
	var a_bitmask = data.decode_u32(104)
	
	print("Size: %dx%d, Mipmaps: %d" % [width, height, mipmap_count])
	print("Pixel Format Flags: 0x%X" % pixelformat_flags)
	print("FourCC: '%s' (raw: 0x%X)" % [fourcc, fourcc_raw])
	print("RGB Bit Count: %d" % rgb_bit_count)
	print("Bitmasks - R: 0x%X, G: 0x%X, B: 0x%X, A: 0x%X" % [r_bitmask, g_bitmask, b_bitmask, a_bitmask])
	
	var format = Image.FORMAT_RGBA8
	var is_compressed = false
	var bytes_per_pixel = 4
	var header_offset = 128
	
	# Determine format type
	var format_type = ""  # For debugging
	
	# Check if it's a compressed format
	if fourcc == "DXT1":
		format = Image.FORMAT_DXT1
		is_compressed = true
		format_type = "DXT1"
	elif fourcc == "DXT3":
		format = Image.FORMAT_DXT3
		is_compressed = true
		format_type = "DXT3"
	elif fourcc == "DXT5":
		format = Image.FORMAT_DXT5
		is_compressed = true
		format_type = "DXT5"
	# Check for uncompressed formats
	elif rgb_bit_count == 16:
		bytes_per_pixel = 2
		is_compressed = false
		
		if r_bitmask == 0xF800 and g_bitmask == 0x07E0 and b_bitmask == 0x001F:
			# RGB 565 format
			format_type = "RGB565"
			print("Detected RGB 5.6.5 format")
			
			#if 'tx' in source_file.get_basename():
				#print("DETAIL TEXTURE")
				#format = Image.FORMAT_DXT1
				#is_compressed = true
				#format_type = "DXT1"
			
		elif r_bitmask == 0x0F00 and g_bitmask == 0x00F0 and b_bitmask == 0x000F and a_bitmask == 0xF000:
			# ARGB 4444 format
			format_type = "ARGB4444"
			print("Detected A4R4G4B4 format")
		elif r_bitmask == 0x7C00 and g_bitmask == 0x03E0 and b_bitmask == 0x001F and a_bitmask == 0x8000:
			# ARGB 1555 format
			format_type = "ARGB1555"
			print("Detected A1R5G5B5 format")
		elif r_bitmask == 0x0000 and g_bitmask == 0x0000 and b_bitmask == 0x0000 and a_bitmask == 0x0000:
			# No bitmasks specified - assume common format based on context
			format_type = "RGB565_DEFAULT"
			print("16-bit format with no bitmasks, assuming RGB 5.6.5")
		else:
			push_error("Unknown 16-bit format - R:0x%X G:0x%X B:0x%X A:0x%X" % [r_bitmask, g_bitmask, b_bitmask, a_bitmask])
			return ERR_FILE_UNRECOGNIZED
	elif rgb_bit_count == 24:
		format_type = "RGB24"
		print("Detected RGB 24-bit format")
		bytes_per_pixel = 3
		is_compressed = false
	elif rgb_bit_count == 32:
		format_type = "RGBA32"
		print("Detected RGBA 32-bit format")
		bytes_per_pixel = 4
		is_compressed = false
	else:
		push_error("Unsupported DDS format - FourCC: '%s', Bit count: %d" % [fourcc, rgb_bit_count])
		return ERR_FILE_UNRECOGNIZED
	
	var image: Image
	
	if is_compressed:
		# Handle compressed formats (DXT1/3/5)
		var block_size = 16 if fourcc != "DXT1" else 8
		var blocks_x = max(1, (width + 3) / 4)
		var blocks_y = max(1, (height + 3) / 4)
		var base_size = blocks_x * blocks_y * block_size
		
		# Validate we have enough data
		if header_offset + base_size > data.size():
			push_error("DDS file truncated - expected %d bytes, got %d" % [header_offset + base_size, data.size()])
			return ERR_FILE_CORRUPT
		
		var compressed_data = data.slice(header_offset, header_offset + base_size)
		
		print("Compressed format, using %d bytes (blocks: %dx%d, block_size: %d)" % [compressed_data.size(), blocks_x, blocks_y, block_size])
		
		# Create temporary compressed image
		var temp_compressed_image = Image.create_from_data(width, height, false, format, compressed_data)
		
		if temp_compressed_image == null or temp_compressed_image.is_empty():
			push_error("Failed to create compressed image")
			return ERR_FILE_CORRUPT
		
		# Decompress to RGBA8
		var decompress_result = temp_compressed_image.decompress()
		if decompress_result != OK:
			push_error("Decompression failed: %d" % decompress_result)
			return decompress_result
		
		# Create NEW, clean uncompressed image from buffer to prevent state corruption
		var rgba_data = temp_compressed_image.get_data()
		image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba_data)
		
		print("Decompressed and re-created successfully to format=%d" % image.get_format())
	else:
		# Handle uncompressed formats (RGB565, RGB24, RGBA32)
		var base_size = width * height * bytes_per_pixel
		var image_data = data.slice(header_offset, header_offset + base_size)
		
		print("Uncompressed format, converting %d bytes" % image_data.size())
		
		# Convert to RGBA8
		var rgba_data = PackedByteArray()
		rgba_data.resize(width * height * 4)
		
		for i in range(width * height):
			var offset = i * bytes_per_pixel
			var r: int
			var g: int
			var b: int
			var a: int = 255
			
			if bytes_per_pixel == 2:
				var pixel = image_data.decode_u16(offset)
				
				if format_type == "RGB565" or format_type == "RGB565_DEFAULT":
					# RGB 565: RRRRRGGGGGGBBBBB
					r = ((pixel >> 11) & 0x1F) * 255 / 31
					g = ((pixel >> 5) & 0x3F) * 255 / 63
					b = (pixel & 0x1F) * 255 / 31
				elif format_type == "ARGB4444":
					# ARGB 4444: AAAARRRRGGGGBBBB
					a = ((pixel >> 12) & 0x0F) * 255 / 15
					r = ((pixel >> 8) & 0x0F) * 255 / 15
					g = ((pixel >> 4) & 0x0F) * 255 / 15
					b = (pixel & 0x0F) * 255 / 15
				elif format_type == "ARGB1555":
					# ARGB 1555: ARRRRRGGGGGBBBBB
					a = 255 if (pixel & 0x8000) else 0
					r = ((pixel >> 10) & 0x1F) * 255 / 31
					g = ((pixel >> 5) & 0x1F) * 255 / 31
					b = (pixel & 0x1F) * 255 / 31
			elif bytes_per_pixel == 3:  # RGB24 (typically BGR in DDS)
				b = image_data[offset]
				g = image_data[offset + 1]
				r = image_data[offset + 2]
			else:  # RGBA32 (typically BGRA in DDS)
				b = image_data[offset]
				g = image_data[offset + 1]
				r = image_data[offset + 2]
				a = image_data[offset + 3]
			
			var out_offset = i * 4
			rgba_data[out_offset] = r
			rgba_data[out_offset + 1] = g
			rgba_data[out_offset + 2] = b
			rgba_data[out_offset + 3] = a
		
		image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba_data)
		
		if image == null or image.is_empty():
			push_error("Failed to create uncompressed image")
			return ERR_FILE_CORRUPT
	
	print("Image created: %dx%d, format=%d" % [image.get_width(), image.get_height(), image.get_format()])
	
	# Verify image has data
	if image.is_empty():
		push_error("Image has no data after creation")
		return ERR_FILE_CORRUPT
	
	# --- FIX: REMOVE MANUAL MIPMAP GENERATION ---
	# The engine will handle mipmap generation based on import options after ResourceSaver.save().
	# Manually calling image.generate_mipmaps() here can sometimes corrupt the image's 
	# internal state for Godot's resource serialization, leading to the RID error.
	
	# Create ImageTexture
	print("Creating ImageTexture...")
	var texture = ImageTexture.new()
	texture.set_image(image)
	
	# Verify texture was created successfully
	if not texture or texture.get_width() == 0:
		push_error("Failed to create valid texture from image")
		return ERR_FILE_CORRUPT
	
	# Save the texture resource
	var filename = "%s.%s" % [save_path, _get_save_extension()]
	print("Saving Texture2D to: %s (size: %dx%d)" % [filename, texture.get_width(), texture.get_height()])
	
	var result = ResourceSaver.save(texture, filename)
	
	if result == OK:
		print("=== Import Complete! ===\n")
	else:
		push_error("Save failed: error %d" % result)
	
	return result
