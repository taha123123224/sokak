extends Node
## Online match glue: every client simulates its own player and streams its state; other players are
## puppets (bot.gd in puppet mode). The shooter detects hits ("favour the shooter") and sends them to the
## victim, who applies the damage and broadcasts the death, so kill feed, scores and medals stay in sync.

var mt          # match.gd
var puppets := {}   # net id -> bot node
var _send_t := 0.0
const RATE := 1.0 / 15.0

func setup(match_node) -> void:
	mt = match_node
	Net.message.connect(_on_msg)
	Net.member_joined.connect(_on_join)
	Net.member_left.connect(_on_left)
	Net.disconnected_room.connect(_on_drop)
	for id in Net.members.keys():
		if id != Net.my_id:
			_add_puppet(id, str(Net.members[id]["name"]))

func _exit_tree() -> void:
	for pair in [[Net.message, _on_msg], [Net.member_joined, _on_join], [Net.member_left, _on_left], [Net.disconnected_room, _on_drop]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])

func _team_of(id: String) -> String:
	if not mt.teams:
		return ""
	var tm: Dictionary = mt.cfg.get("teams_map", {})
	return str(tm.get(id, "b" if mt.player.team == "a" else "a"))

func _add_puppet(id: String, nm: String) -> void:
	if puppets.has(id):
		return
	var b := preload("res://scripts/bot.gd").new()
	b.match_node = mt
	b.puppet = true
	b.net_id = id
	mt.add_child(b)
	var team := _team_of(id)
	var pool: Array = GS.team_chars(team) if team != "" else GS.CHARACTERS.keys()
	var cid: String = pool[abs(id.hash()) % pool.size()]
	b.setup(GS.char_scene(cid), nm, team, 1, "ak47")
	b.global_position = Vector3(0, -200, 0)
	b.alive = false
	b.visible = false
	puppets[id] = b
	mt.combatants.append({"node": b, "name": nm, "team": team, "kills": 0, "deaths": 0, "score": 0, "head": 0, "is_player": false, "gg": 0, "lvl": 1, "net_id": id})

func _on_join(id: String, nm: String) -> void:
	_add_puppet(id, nm)
	mt.hud.center_msg("%s maça katıldı" % nm, UI.GREEN)

func _on_left(id: String) -> void:
	if not puppets.has(id):
		return
	var b = puppets[id]
	puppets.erase(id)
	for i in range(mt.combatants.size() - 1, -1, -1):
		if mt.combatants[i]["node"] == b:
			mt.combatants.remove_at(i)
	mt.hud.center_msg("%s maçtan ayrıldı" % b.display_name, UI.ACCENT2)
	b.queue_free()

func _on_drop(why: String) -> void:
	mt.hud.center_msg("Bağlantı koptu: " + why, UI.RED)

func _process(delta: float) -> void:
	_send_t -= delta
	if _send_t > 0 or mt.player == null:
		return
	_send_t = RATE
	var p = mt.player
	var gp: Vector3 = p.global_position
	Net.send({"t": "s", "p": [snappedf(gp.x, 0.01), snappedf(gp.y, 0.01), snappedf(gp.z, 0.01)], "v": [snappedf(p.velocity.x, 0.01), snappedf(p.velocity.z, 0.01)],
		"yw": snappedf(p.yaw, 0.001), "pt": snappedf(p.pitch, 0.001), "w": p.cur, "c": p.crouching, "a": p.alive, "r": p.reload_t > 0})

# ---------------------------------------------------------------- outgoing events
func send_fire(wid: String) -> void:
	Net.send({"t": "f", "w": wid})

func send_hit(victim, amount: float, pos: Vector3, head: bool, wid: String) -> void:
	Net.send_to(victim.net_id, {"t": "hit", "d": snappedf(amount, 0.1), "h": head, "w": wid, "o": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)]})

func send_death(killer, wid: String, head: bool) -> void:
	var kid := ""
	if killer == mt.player:
		kid = Net.my_id
	elif killer != null and is_instance_valid(killer) and "net_id" in killer:
		kid = killer.net_id
	Net.send({"t": "die", "k": kid, "w": wid, "h": head})

# ---------------------------------------------------------------- incoming
func _on_msg(d: Dictionary) -> void:
	var from := str(d.get("from", ""))
	match str(d.get("t", "")):
		"s":
			if not puppets.has(from):
				_add_puppet(from, str(Net.members.get(from, {}).get("name", "Oyuncu")))
			var b = puppets[from]
			b.visible = true
			b.net_state(d)
		"f":
			if puppets.has(from):
				puppets[from].net_fire(str(d.get("w", "ak47")))
		"hit":
			if mt.player and mt.player.alive and not mt.ended:
				var o: Array = d.get("o", [0, 0, 0])
				var attacker = puppets.get(from, null)
				mt.player.take_damage(float(d.get("d", 0)), attacker, Vector3(float(o[0]), float(o[1]), float(o[2])), bool(d.get("h", false)), str(d.get("w", "")))
		"die":
			if puppets.has(from):
				var kid := str(d.get("k", ""))
				var killer = mt.player if kid == Net.my_id else puppets.get(kid, null)
				puppets[from].net_die(killer, str(d.get("w", "")), bool(d.get("h", false)))
		"end":
			if not mt.ended:
				mt.end_match()
