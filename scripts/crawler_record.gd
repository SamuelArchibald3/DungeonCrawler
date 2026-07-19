class_name CrawlerRecord
extends RefCounted
## The permanent identity of one crawler in the cohort — player or NPC.
## The CharacterData sheet is the single source of truth for hp/stats/loot
## in BOTH simulation tiers; the Entity node and controller are transient
## attachments that exist only while the crawler is REAL (near the player).
## Future battle royale: swap the controller for player/network input.

enum Disposition { WARY, FRIENDLY, HOSTILE }
enum Tier { ABSTRACT, REAL }
enum Goal { EXPLORE, FIGHT, LOOT, FLEE, TO_STAIRS, HIDE_SAFE }

var id := 0
var sheet: CharacterData
var disposition := Disposition.WARY
var tier := Tier.ABSTRACT
var pos := Vector2i.ZERO       # truth while ABSTRACT; mirrored from entity while REAL
var room := -1                 # room index for abstract pathing
var alive := true
var descended := false
var is_player := false
var entity: Entity             # null while ABSTRACT
var controller = null          # CrawlerController; null while ABSTRACT
var goal := Goal.EXPLORE
var goal_data := {}
var kills := 0
var color := Color.WHITE       # stable per-id hue for glyph/map/feed


static func make(id_: int, sheet_: CharacterData) -> CrawlerRecord:
	var cr := CrawlerRecord.new()
	cr.id = id_
	cr.sheet = sheet_
	cr.color = Color.from_hsv(fmod(id_ * 0.6180339887, 1.0), 0.55, 0.95)
	return cr
