class_name SnakeLogic
extends RefCounted
## Pure game rules for Snake War: grid, snakes, fruit, collisions and the computer player.
## No nodes here, so the view (main.gd) only reads state and the `events` list after each tick.

const W := 32
const H := 20
const DIRS := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
const OPP := {"up": "down", "down": "up", "left": "right", "right": "left"}

const AI_CFG := {
	"easy": {"mistake": 0.07, "flood": false, "head_risk": false, "room": 0, "lazy": 0.35, "bonus": {"apple": 0, "cherry": 2, "banana": 2}},
	"medium": {"mistake": 0.015, "flood": true, "head_risk": false, "room": 4, "lazy": 0.0, "bonus": {"apple": 0, "cherry": 5, "banana": 5}},
	"hard": {"mistake": 0.0, "flood": true, "head_risk": true, "room": 10, "lazy": 0.0, "bonus": {"apple": 0, "cherry": 9, "banana": 8}},
}


class Snake:
	var p: int
	var body: Array = []        # Array of Vector2i, head first
	var prev: Array = []        # body before its last move (for smooth drawing)
	var moved_tick := 0
	var dir := "right"
	var queue: Array = []
	var grow := 0
	var alive := true
	var slow_until := 0.0
	var dead := ""
	var ai := ""


var stage: Dictionary
var obs := {}
var snakes: Array = []
var items: Array = []
var game_time := 0.0
var tick_n := 0
var next_cherry := 0.0
var next_banana := 0.0
var events: Array = []
var over := false
var dead_list: Array = []
var _item_id := 0


static func stage_defs() -> Array:
	return [
		{"id": "meadow", "name": "ทุ่งหญ้าโล่ง", "desc": "สนามเปิดโล่ง ล้อมด้วยรั้วไม้ เหมาะกับการเริ่มต้น", "wall": "รั้วไม้", "wrap": false, "style": "fence",
			"bg": Color("357036"), "bg2": Color("3b7a3c"), "wall_col": Color("8a6236"), "sky": Color("8fc7de"), "ground": Color("2f5a2f")},
		{"id": "fort", "name": "ป้อมอิฐ", "desc": "กำแพงอิฐกลางสนาม แบ่งเป็นช่องทางแคบ", "wall": "กำแพงอิฐ", "wrap": false, "style": "brick",
			"bg": Color("4a3f52"), "bg2": Color("524759"), "wall_col": Color("b4573d"), "sky": Color("2a2233"), "ground": Color("1e1924")},
		{"id": "desert", "name": "ทะเลทรายกระบองเพชร", "desc": "กระบองเพชรกระจายทั่วทราย เลี้ยวหลบให้ทัน", "wall": "กระบองเพชร", "wrap": false, "style": "cactus",
			"bg": Color("b98a48"), "bg2": Color("c09252"), "wall_col": Color("3f8a3a"), "sky": Color("f2c58c"), "ground": Color("c29350")},
		{"id": "ice", "name": "ถ้ำน้ำแข็ง", "desc": "กำแพงน้ำแข็งรูปกากบาท ต้องแย่งกันผ่านช่องกลาง", "wall": "กำแพงน้ำแข็ง", "wrap": false, "style": "ice",
			"bg": Color("8fb8cf"), "bg2": Color("9ac1d6"), "wall_col": Color("5fb4dd"), "sky": Color("16314a"), "ground": Color("1d3d57")},
		{"id": "space", "name": "อวกาศวาร์ป", "desc": "ไม่มีขอบสนาม ทะลุจอไปโผล่อีกฝั่งได้ แต่ระวังอุกกาบาต", "wall": "อุกกาบาต", "wrap": true, "style": "rock",
			"bg": Color("1a1a3a"), "bg2": Color("202045"), "wall_col": Color("615b78"), "sky": Color("05050f"), "ground": Color("05050f")},
	]


static func _rect(s: Dictionary, x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			s[Vector2i(x, y)] = true


static func _border(s: Dictionary) -> void:
	_rect(s, 0, 0, W - 1, 0)
	_rect(s, 0, H - 1, W - 1, H - 1)
	_rect(s, 0, 0, 0, H - 1)
	_rect(s, W - 1, 0, W - 1, H - 1)


static func _in_lane(x: int, y: int) -> bool:
	return (y >= 3 and y <= 5 and x <= 15) or (y >= 14 and y <= 16 and x >= 16)


static func build_obstacles(st: Dictionary) -> Dictionary:
	var s := {}
	match st["id"]:
		"meadow":
			_border(s)
		"fort":
			_border(s)
			_rect(s, 9, 7, 10, 12); _rect(s, 21, 7, 22, 12); _rect(s, 13, 9, 18, 10)
			_rect(s, 13, 2, 18, 2); _rect(s, 13, 17, 18, 17)
		"desert":
			_border(s)
			var seed := 11
			var n := 0
			while n < 26:
				seed = (seed * 16807) % 2147483647
				var x := 2 + int(float(seed) / 2147483647.0 * (W - 4))
				seed = (seed * 16807) % 2147483647
				var y := 2 + int(float(seed) / 2147483647.0 * (H - 4))
				if _in_lane(x, y) or s.has(Vector2i(x, y)):
					continue
				s[Vector2i(x, y)] = true
				n += 1
		"ice":
			_border(s)
			_rect(s, 4, 9, 12, 10); _rect(s, 19, 9, 27, 10); _rect(s, 15, 2, 16, 6); _rect(s, 15, 13, 16, 17)
		"space":
			_rect(s, 7, 9, 8, 10); _rect(s, 23, 9, 24, 10); _rect(s, 15, 3, 16, 4); _rect(s, 15, 15, 16, 16)
	# keep both starting lanes clear
	for x in range(1, 15):
		s.erase(Vector2i(x, 4))
	for x in range(17, 31):
		s.erase(Vector2i(x, 15))
	return s


func _make_snake(p: int, head: Vector2i, dir: String) -> Snake:
	var s := Snake.new()
	s.p = p
	s.dir = dir
	var back: Vector2i = -DIRS[dir]
	for i in 4:
		s.body.append(head + back * i)
	s.prev = s.body.duplicate()
	return s


func start_round(st: Dictionary, ai_level: String) -> void:
	stage = st
	obs = build_obstacles(st)
	snakes = [_make_snake(0, Vector2i(6, 4), "right"), _make_snake(1, Vector2i(25, 15), "left")]
	snakes[1].ai = ai_level
	items.clear()
	events.clear()
	dead_list.clear()
	over = false
	game_time = 0.0
	tick_n = 0
	spawn("apple")
	spawn("apple")
	next_cherry = randf_range(3000, 6000)
	next_banana = randf_range(5000, 9000)


func is_slowed(s: Snake) -> bool:
	return s.alive and s.slow_until > game_time


func wrap_pos(v: Vector2i) -> Vector2i:
	if stage.get("wrap", false):
		return Vector2i(posmod(v.x, W), posmod(v.y, H))
	return v


func _in_bounds(v: Vector2i) -> bool:
	return v.x >= 0 and v.y >= 0 and v.x < W and v.y < H


func _occupied(v: Vector2i) -> bool:
	if obs.has(v):
		return true
	for s in snakes:
		if v in s.body:
			return true
	for it in items:
		if it["pos"] == v:
			return true
	return false


func spawn(type: String) -> void:
	for _tries in 500:
		var v := Vector2i(randi() % W, randi() % H)
		if _occupied(v):
			continue
		var near := false
		for s in snakes:
			var h: Vector2i = s.body[0]
			if absi(h.x - v.x) + absi(h.y - v.y) < 3:
				near = true
		if near:
			continue
		_item_id += 1
		items.append({"id": _item_id, "type": type, "pos": v, "born": game_time,
			"expires": INF if type == "apple" else game_time + 9000.0})
		return


func queue_dir(p: int, d: String) -> void:
	var s: Snake = snakes[p]
	if not s.alive:
		return
	var last: String = s.queue.back() if s.queue.size() > 0 else s.dir
	if d == last or d == OPP[last]:
		return
	if s.queue.size() < 3:
		s.queue.append(d)


func tick() -> void:
	tick_n += 1
	var movers: Array = []
	for s in snakes:
		if s.alive and (not is_slowed(s) or tick_n % 2 == 0):
			movers.append(s)
	if movers.is_empty():
		return
	for s in movers:
		if s.ai != "":
			_ai_think(s)
	var nh := {}
	for s in movers:
		if s.queue.size() > 0:
			var d: String = s.queue.pop_front()
			if d != OPP[s.dir]:
				s.dir = d
		nh[s] = wrap_pos(s.body[0] + DIRS[s.dir])
	# collisions
	for s in movers:
		var h: Vector2i = nh[s]
		if not _in_bounds(h) or obs.has(h):
			s.dead = "wall"
			continue
		for o in snakes:
			var moving: bool = nh.has(o) and o.grow == 0
			var cells: Array = o.body.slice(0, o.body.size() - 1) if moving else o.body
			if h in cells:
				s.dead = "self" if o == s else "other"
				break
	if movers.size() == 2:
		var a: Snake = movers[0]
		var b: Snake = movers[1]
		var same: bool = nh[a] == nh[b]
		var swap: bool = nh[a] == b.body[0] and nh[b] == a.body[0]
		if same or swap:
			a.dead = "headon"
			b.dead = "headon"
	var dead: Array = movers.filter(func(x): return x.dead != "")
	if dead.size() > 0:
		for s in dead:
			s.alive = false
		over = true
		dead_list = dead
		events.append({"t": "crash", "snakes": dead})
		return
	for s in movers:
		s.prev = s.body.duplicate()
		s.moved_tick = tick_n
		s.body.push_front(nh[s])
		if s.grow > 0:
			s.grow -= 1
		else:
			s.body.pop_back()
	# fruit
	for s in movers:
		var h: Vector2i = s.body[0]
		var idx := -1
		for i in items.size():
			if items[i]["pos"] == h:
				idx = i
				break
		if idx < 0:
			continue
		var it: Dictionary = items[idx]
		items.remove_at(idx)
		var o: Snake = snakes[1 - s.p]
		match it["type"]:
			"apple":
				s.grow += 3
				events.append({"t": "apple", "p": s.p, "pos": h})
				spawn("apple")
			"cherry":
				var n: int = clampi(o.body.size() - 3, 0, 3)
				var cut: Array = o.body.slice(o.body.size() - n)
				o.body.resize(o.body.size() - n)
				o.grow = 0
				events.append({"t": "cherry", "p": s.p, "pos": h, "target": o.p, "tpos": o.body[0], "n": n, "cut": cut})
				next_cherry = game_time + randf_range(4000, 8000)
			"banana":
				o.slow_until = game_time + 5000.0
				events.append({"t": "banana", "p": s.p, "pos": h, "target": o.p, "tpos": o.body[0]})
				next_banana = game_time + randf_range(6000, 10000)


func update_items() -> void:
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if it["expires"] <= game_time:
			items.remove_at(i)
			if it["type"] == "cherry":
				next_cherry = game_time + randf_range(3000, 6000)
			elif it["type"] == "banana":
				next_banana = game_time + randf_range(4000, 8000)
	if not _has_item("cherry") and game_time >= next_cherry:
		spawn("cherry")
		next_cherry = INF
	if not _has_item("banana") and game_time >= next_banana:
		spawn("banana")
		next_banana = INF


func _has_item(type: String) -> bool:
	for it in items:
		if it["type"] == type:
			return true
	return false


# ---------- computer player ----------
# Scores each possible turn: never step into a crash, avoid pockets smaller than its body,
# head for the best fruit (cherry/banana count extra), and on hard keep away from the rival's next move.

func _step(v: Vector2i, d: String) -> Variant:
	var n := wrap_pos(v + DIRS[d])
	return n if _in_bounds(n) else null


func _ai_think(s: Snake) -> void:
	var cfg: Dictionary = AI_CFG[s.ai]
	var o: Snake = snakes[1 - s.p]
	var h: Vector2i = s.body[0]
	var blocked := obs.duplicate()
	for sn in snakes:
		var cells: Array = sn.body.slice(0, sn.body.size() - 1) if (sn == s and s.grow == 0) else sn.body
		for c in cells:
			blocked[c] = true
	var rival_next := {}
	if o.alive:
		for d in DIRS:
			if d == OPP[o.dir]:
				continue
			var n = _step(o.body[0], d)
			if n != null:
				rival_next[n] = true
	var opts: Array = DIRS.keys().filter(func(d): return d != OPP[s.dir])
	var safe: Array = []
	for d in opts:
		var n = _step(h, d)
		if n != null and not blocked.has(n):
			safe.append(d)
	if cfg["lazy"] > 0 and s.dir in safe and randf() < cfg["lazy"]:
		s.queue.clear()
		return
	if cfg["mistake"] > 0 and safe.size() > 0 and randf() < cfg["mistake"]:
		s.queue = [safe.pick_random()]
		return
	var item_at := {}
	for it in items:
		item_at[it["pos"]] = it["type"]
	var best := s.dir
	var best_score := -INF
	for d in opts:
		var n = _step(h, d)
		var score := 0.0
		if n == null or blocked.has(n):
			score = -1e6
		else:
			var seen := {n: true}
			var q: Array = [[n, 0]]
			var target := INF
			var i := 0
			while i < q.size():
				var cur: Vector2i = q[i][0]
				var dist: int = q[i][1]
				i += 1
				if item_at.has(cur):
					target = minf(target, dist - cfg["bonus"][item_at[cur]])
				for dd in DIRS:
					var m = _step(cur, dd)
					if m == null or seen.has(m) or blocked.has(m):
						continue
					seen[m] = true
					q.append([m, dist + 1])
			var space := q.size()
			var need := s.body.size() + s.grow
			if cfg["flood"] and space < need + 2:
				score -= 5e4 - space * 100
			if cfg["room"] > 0:
				score += mini(space, need * 3) * cfg["room"]
			if cfg["head_risk"] and rival_next.has(n):
				score -= 2e4
			score -= (40.0 if target == INF else target) * 10.0
			if d == s.dir:
				score += 1
			score += randf()
		if score > best_score:
			best_score = score
			best = d
	s.queue = [best]
