extends Node
## v4.4 split packs: the game ships as a small SOKAK.pck (code, scenes, settings) plus content-addressed
## shard packs in <game>/veri/ (textures, models, sounds). The list of installed shards is veri/yuklu.json,
## written by the launcher / in-game updater only after every shard is complete. This autoload is FIRST in the
## list so the shards are mounted before any other script or resource is loaded.

var dir := ""
var loaded: Array[String] = []
var missing: Array[String] = []
var state := {}

func _init() -> void:
	dir = OS.get_environment("SOKAK_DIR") if OS.has_environment("SOKAK_DIR") else OS.get_executable_path().get_base_dir()
	var lp := dir.path_join("veri/yuklu.json")
	if not FileAccess.file_exists(lp):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(lp))
	if not (d is Dictionary):
		return
	state = d
	for f in d.get("packs", []):
		var p := dir.path_join(str(f))
		if str(f) == "SOKAK.pck":
			continue
		if FileAccess.file_exists(p) and ProjectSettings.load_resource_pack(p, true):
			loaded.append(str(f))
		else:
			missing.append(str(f))
	if not missing.is_empty():
		push_warning("SOKAK: missing packs %s" % str(missing))

func installed_build() -> int:
	return int(state.get("build", 0))
