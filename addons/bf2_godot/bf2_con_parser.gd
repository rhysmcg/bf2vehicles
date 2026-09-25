class_name BF2ConParser
extends RefCounted

static func parse_con(filepath: String) -> Dictionary:
	var file := FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return {}

	var template := {
		"name": "",
		"type": "",
		"geometry": "",
		"children": []
	}

	var current_child := {}

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("rem") or line.is_empty():
			continue

		var parts := line.split(" ", false)
		if parts.size() < 2:
			continue

		var cmd := parts[0].to_lower()
		match cmd:
			"objecttemplate.create":
				template["type"] = parts[1]
				template["name"] = parts[2] if parts.size() > 2 else ""
			"objecttemplate.geometry":
				template["geometry"] = parts[1]
			"objecttemplate.addtemplate":
				if not current_child.is_empty():
					template["children"].append(current_child)
				current_child = {"template": parts[1], "position": Vector3.ZERO, "rotation": Vector3.ZERO, "geom_part": 0}
			"objecttemplate.setposition":
				if not current_child.is_empty() and parts.size() >= 4:
					current_child["position"] = Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
			"objecttemplate.setrotation":
				if not current_child.is_empty() and parts.size() >= 4:
					current_child["rotation"] = Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
			"objecttemplate.setpartid":
				if not current_child.is_empty():
					current_child["geom_part"] = parts[1].to_int()

	if not current_child.is_empty():
		template["children"].append(current_child)

	file.close()
	return template
