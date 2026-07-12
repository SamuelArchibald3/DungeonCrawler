class_name Shopkeeper
extends Npc
## A Bopca merchant with rolled stock. A separate entity from saferooms —
## he sets up wherever foot traffic (and mortal peril) is best.

var stock: Array = []  # Array[ItemData]


static func make(pos: Vector2i, floor_num: int) -> Shopkeeper:
	var keeper := Shopkeeper.new()
	keeper.grid_pos = pos
	keeper.position = Vector2(pos * TILE)
	keeper.glyph = "B"
	keeper.color = Color(0.95, 0.8, 0.35)
	keeper.stock = LootGenerator.roll_shop_stock(floor_num)
	return keeper


func on_bumped() -> void:
	Events.msg(Flavor.shop_greeting(), &"system")
	dungeon.shop_requested.emit(self)
