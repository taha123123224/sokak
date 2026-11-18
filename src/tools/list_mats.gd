extends SceneTree
## usage: godot --headless --path . -s tools/list_mats.gd -- <map_id>
## prints every material of a map model with how much surface (triangle area, m2) uses it and its texture
func _init() -> void:
	var id: String = OS.get_cmdline_user_args()[0]
	var ps: PackedScene = load("res://assets/maps/%s.glb" % id)
	var root := ps.instantiate()
	var area := {}
	var texn := {}
	var up := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = m3
		while n:
			if n is Node3D: xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for si in m3.mesh.get_surface_count():
			var mt := m3.get_active_material(si)
			var key := str(mt.resource_name) if mt else "<none>"
			var arr := m3.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			var a := 0.0; var ua := 0.0
			var cnt: int = ix.size() if ix else v.size()
			for t in range(0, cnt, 3):
				var p0 := xf * v[ix[t] if ix else t]; var p1 := xf * v[ix[t + 1] if ix else t + 1]; var p2 := xf * v[ix[t + 2] if ix else t + 2]
				var cr := (p1 - p0).cross(p2 - p0)
				a += cr.length() * 0.5
				if cr.normalized().y > 0.8: ua += cr.length() * 0.5
			area[key] = area.get(key, 0.0) + a
			up[key] = up.get(key, 0.0) + ua
			if mt is StandardMaterial3D and (mt as StandardMaterial3D).albedo_texture:
				texn[key] = (mt as StandardMaterial3D).albedo_texture.resource_path.get_file()
	var ks := area.keys()
	ks.sort_custom(func(a, b): return area[a] > area[b])
	for k in ks.slice(0, 40):
		print("MAT %-40s area %8.0f up %8.0f  %s" % [k, area[k], up[k], texn.get(k, "")])
	quit()
