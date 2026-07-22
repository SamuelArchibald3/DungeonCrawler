class_name CrawlerSim
extends RefCounted
## The abstract tier: distant crawlers advance via statistical macro-steps
## instead of real entities. Pure — no autoload access — so headless tests
## can drive whole floors deterministically. Callers dispatch the returned
## events (deaths, descents, pool consumption) to game systems.

const SIM_PERIOD := 8  # world ticks between one crawler's macro-steps


## ctx: fd, pools {zone: {enemies, boxes}}, routing, zone_room_counts,
## records (for PvP), floor_num, rng, turns_left, rich_loot (bool).
static func build_context(fd: FloorGenerator.FloorData, floor_num: int,
		rng: RandomNumberGenerator, records: Array, turns_left: int) -> Dictionary:
	var pools := {}
	var zone_room_counts := {}
	for zone in fd.zones.size():
		pools[zone] = { "enemies": 0, "boxes": 0 }
		zone_room_counts[zone] = maxi(fd.zones[zone]["rooms"].size(), 1)
	for pos in fd.enemy_spawns:
		var zone: int = fd.zone_of.get(pos, -1)
		if pools.has(zone):
			pools[zone]["enemies"] += 1
	for spawn in fd.box_spawns:
		var zone: int = fd.zone_of.get(spawn["pos"], -1)
		if pools.has(zone):
			pools[zone]["boxes"] += 1
	return {
		"fd": fd,
		"pools": pools,
		"zone_room_counts": zone_room_counts,
		"routing": build_routing(fd),
		"records": records,
		"floor_num": floor_num,
		"rng": rng,
		"turns_left": turns_left,
		"rich_loot": false,
	}


## BFS over the room graph from the public stairwell: next-hop + distance.
static func build_routing(fd: FloorGenerator.FloorData) -> Dictionary:
	var stairs_tile := fd.stairs_free if fd.stairs_free != Vector2i(-1, -1) else fd.stairs
	var stairs_room: int = fd.room_of.get(stairs_tile, 0)
	var next := {}
	var dist := { stairs_room: 0 }
	var queue := [stairs_room]
	while not queue.is_empty():
		var room: int = queue.pop_front()
		for neighbor in fd.room_graph.get(room, []):
			if not dist.has(neighbor):
				dist[neighbor] = dist[room] + 1
				next[neighbor] = room  # hop toward the stairs
				queue.append(neighbor)
	return { "stairs_room": stairs_room, "next": next, "dist": dist }


## One macro-step for one abstract crawler. Mutates sheet hp/xp/gold and
## room/pos; returns events for the caller to apply (died / pvp / descended
## / enemy_killed / looted). Does NOT set alive/descended flags itself.
static func macro_step(cr: CrawlerRecord, ctx: Dictionary) -> Array:
	var events: Array = []
	if not cr.alive or cr.descended or cr.is_player or cr.tier == CrawlerRecord.Tier.REAL:
		return events
	var rng: RandomNumberGenerator = ctx["rng"]
	var fd: FloorGenerator.FloorData = ctx["fd"]
	var routing: Dictionary = ctx["routing"]
	var sheet: CharacterData = cr.sheet

	# Stairs urgency: leave enough time to hop the remaining rooms
	var hops: int = routing["dist"].get(cr.room, 99)
	if int(ctx["turns_left"]) < hops * SIM_PERIOD * 2 + 60:
		cr.goal = CrawlerRecord.Goal.TO_STAIRS

	if cr.goal == CrawlerRecord.Goal.TO_STAIRS:
		if cr.room == routing["stairs_room"]:
			events.append({ "kind": &"descended", "cr": cr })
			return events
		cr.room = routing["next"].get(cr.room, cr.room)
		cr.pos = fd.rooms[cr.room].get_center()
		return events

	var zone: int = fd.zone_of.get(fd.rooms[cr.room].get_center(), -1)
	var pool: Dictionary = ctx["pools"].get(zone, { "enemies": 0, "boxes": 0 })

	# Encounter: fight a local monster, statistically
	var zone_rooms: int = ctx["zone_room_counts"].get(zone, 1)
	var encounter_p := clampf(0.35 * float(pool["enemies"]) / float(zone_rooms), 0.05, 0.5)
	if pool["enemies"] > 0 and rng.randf() < encounter_p:
		var floor_num: int = ctx["floor_num"]
		var enemy_hp := 8 + floor_num * 4
		var enemy_attack := 2 + floor_num
		var dps := maxi(sheet.get_weapon_damage() + floori((sheet.get_stat(&"STR") - 8) / 2.0), 1)
		var rounds := ceili(float(enemy_hp) / float(dps))
		var per_round := maxi(enemy_attack - sheet.get_defense(), 1)
		var variance := 0.7 + rng.randf() * 0.6
		var damage_taken := int(round(rounds * per_round * variance))
		sheet.hp = maxi(sheet.hp - damage_taken, 0)
		if sheet.hp <= 0:
			events.append({ "kind": &"died", "cr": cr, "cause": "the local wildlife" })
			return events
		pool["enemies"] -= 1
		sheet.gain_xp(3 + floor_num * 2)
		sheet.gold += 2 + rng.randi_range(0, 4) + floor_num
		cr.kills += 1
		events.append({ "kind": &"enemy_killed", "cr": cr, "zone": zone })
		return events

	# Loot: crack a box somewhere in the zone
	if pool["boxes"] > 0 and rng.randf() < 0.1:
		pool["boxes"] -= 1
		sheet.gold += 5 + rng.randi_range(0, 15)
		events.append({ "kind": &"looted", "cr": cr, "zone": zone })
		return events

	# Abstract PvP: hostiles jump a roommate
	if cr.disposition == CrawlerRecord.Disposition.HOSTILE:
		for other: CrawlerRecord in ctx["records"]:
			if other == cr or other.is_player or not other.alive or other.descended \
					or other.tier == CrawlerRecord.Tier.REAL or other.room != cr.room:
				continue
			var my_score := _pvp_score(sheet, rng)
			var their_score := _pvp_score(other.sheet, rng)
			var loser := other if my_score >= their_score else cr
			var winner := cr if loser == other else other
			events.append({ "kind": &"pvp", "cr": loser, "killer": winner })
			return events

	# Wander: hop to a random adjacent room
	var neighbors: Array = fd.room_graph.get(cr.room, [])
	if not neighbors.is_empty():
		cr.room = neighbors[rng.randi_range(0, neighbors.size() - 1)]
		cr.pos = fd.rooms[cr.room].get_center()
	return events


static func _pvp_score(sheet: CharacterData, rng: RandomNumberGenerator) -> int:
	return sheet.hp + (sheet.get_weapon_damage() + sheet.get_stat(&"STR")) * 3 + rng.randi_range(0, 20)


## Naive gear upgrade for NPC loot: equip if strictly better, else pocket it.
static func auto_equip(sheet: CharacterData, item: ItemData) -> void:
	if item.is_consumable():
		sheet.inventory.append(item)
		return
	var slot: StringName = item.base.slot
	var current = sheet.equipment[slot]
	var new_score: int = item.get_damage() * 2 + item.get_defense() * 2 + item.rarity
	var current_score: int = -1 if current == null \
		else current.get_damage() * 2 + current.get_defense() * 2 + current.rarity
	if new_score > current_score:
		if current != null:
			sheet.inventory.append(current)
		sheet.equipment[slot] = item
		sheet.recompute_max_hp()
	else:
		sheet.inventory.append(item)
