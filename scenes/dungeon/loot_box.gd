class_name LootBox
extends Node2D
## A loot box occupying a grid tile. Bump it to open; contents go straight
## to inventory.

const TILE := Entity.TILE

var tier := 0
var grid_pos: Vector2i
var dungeon: Dungeon


static func make(tier_: int, pos: Vector2i) -> LootBox:
	var box := LootBox.new()
	box.tier = tier_
	box.grid_pos = pos
	box.position = Vector2(pos * TILE)
	return box


func _ready() -> void:
	var rect := ColorRect.new()
	rect.color = Color(LootGenerator.TIER_COLORS[tier])
	rect.position = Vector2(3, 4)
	rect.size = Vector2(TILE - 6, TILE - 7)
	add_child(rect)
	var lid := ColorRect.new()
	lid.color = Color(LootGenerator.TIER_COLORS[tier]).darkened(0.3)
	lid.position = Vector2(2, 2)
	lid.size = Vector2(TILE - 4, 3)
	add_child(lid)


## Bump interaction entry point (turn_manager calls on_bumped on interactables).
func on_bumped() -> void:
	open_box()


## An NPC crawler looting this box: contents to their sheet, no player
## signals, no log spam.
func open_for_npc(cr: CrawlerRecord) -> void:
	cr.sheet.gold += (tier + 1) * (5 + GameState.rng.randi_range(0, 10))
	cr.sheet.inventory.append(
		LootGenerator.roll_item(GameState.floor_number, LootGenerator.roll_rarity(tier, GameState.floor_number)))
	if dungeon != null:
		dungeon.grid.remove_entity(grid_pos)
	queue_free()


func open_box() -> void:
	var tier_name: String = LootGenerator.TIER_NAMES[tier]
	Events.msg("[color=%s]%s Box[/color] opened. %s" % [
		LootGenerator.TIER_COLORS[tier], tier_name, Flavor.box_quip()], &"loot")

	var items: Array = LootGenerator.open_box(tier, GameState.floor_number)
	var c: CharacterData = GameState.character
	for item: ItemData in items:
		c.inventory.append(item)
		Events.msg("  %s acquired." % item.colored_name(), &"loot")
		if not item.is_consumable() and item.rarity > GameState.best_item_rarity:
			GameState.best_item_rarity = item.rarity
			GameState.best_item_name = item.display_name()
	GameState.boxes_opened += 1
	Events.box_opened.emit(tier)

	var gold := (tier + 1) * (5 + GameState.rng.randi_range(0, 10))
	c.gold += gold
	Events.msg("  +%d gold." % gold, &"loot")

	if dungeon != null:
		dungeon.grid.remove_entity(grid_pos)
	queue_free()
