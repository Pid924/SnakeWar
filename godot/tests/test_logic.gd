extends SceneTree
## Headless rule checks: godot --headless --path godot -s res://tests/test_logic.gd

var fails := 0


func check(cond: bool, label: String) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		fails += 1


func _init() -> void:
	var st: Dictionary = SnakeLogic.stage_defs()[0]

	# 1) closing a loop of your own body around the rival's head wins at once
	var g := SnakeLogic.new()
	g.start_round(st, "")
	g.items.clear()
	var a = g.snakes[0]
	var b = g.snakes[1]
	var ring: Array = []
	for x in range(13, 17): ring.append(Vector2i(x, 8))
	for y in range(9, 13): ring.append(Vector2i(16, y))
	for x in range(15, 11, -1): ring.append(Vector2i(x, 12))
	for y in range(11, 8, -1): ring.append(Vector2i(12, y))
	ring.reverse()
	a.body = ring
	a.prev = ring.duplicate()
	a.dir = "up"
	a.grow = 2
	b.body = [Vector2i(14, 10), Vector2i(15, 10)]
	b.prev = b.body.duplicate()
	b.dir = "left"
	g.tick()
	check(g.over and b.dead == "enclosed" and a.alive, "enclosed rival is out at once")

	# 2) hitting a wall only gets you stuck; out after 3 s
	g = SnakeLogic.new()
	g.start_round(st, "")
	g.items.clear()
	a = g.snakes[0]
	a.body = [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)]
	a.dir = "left"
	g.tick()
	check(a.alive and a.stuck_since >= 0.0, "wall makes the snake stuck, not dead")
	g.game_time += 3100.0
	g.tick()
	check(not a.alive and a.dead == "wall", "stuck for 3 s is out")

	# 3) banana is held, used on demand; a second one while holding fires at once
	g = SnakeLogic.new()
	g.start_round(st, "")
	g.items.clear()
	a = g.snakes[0]
	b = g.snakes[1]
	var h: Vector2i = a.body[0]
	g.items.append({"id": 900, "type": "banana", "pos": h + Vector2i(1, 0), "expires": INF})
	g.tick()
	check(a.banana == 1 and b.slow_until <= g.game_time, "first banana is held, rival not slowed yet")
	g.items.append({"id": 901, "type": "banana", "pos": a.body[0] + Vector2i(1, 0), "expires": INF})
	g.tick()
	check(a.banana == 1 and b.slow_until > g.game_time, "second banana while holding slows rival at once")
	g.game_time += 6000.0
	g.use_banana(0)
	check(a.banana == 0 and b.slow_until > g.game_time, "using the held banana slows the rival")

	print("FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
