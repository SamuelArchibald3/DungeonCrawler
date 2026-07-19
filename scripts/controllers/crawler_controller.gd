class_name CrawlerController
extends RefCounted
## A crawler's brain. AIController drives NPCs today; a future
## LocalInputController / RemoteController slots in here for battle royale.
## Stateless by design: the crawler is passed per call (avoids RefCounted
## reference cycles with CrawlerRecord).


func think(_cr: CrawlerRecord, _dungeon: Dungeon, _tm: TurnManager) -> void:
	pass
