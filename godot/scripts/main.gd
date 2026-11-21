extends Node3D
## Snake War 3D: builds the scene, menu and HUD in code, drives SnakeLogic and draws it in 3D.

const W := SnakeLogic.W
const H := SnakeLogic.H
const SPEEDS := {"slow": 140.0, "normal": 105.0, "fast": 78.0}
const AI_NAMES := {"easy": "ง่าย", "medium": "กลาง", "hard": "ยาก"}
const P_MAIN := [Color("4cc9ff"), Color("ff5fa2")]
const P_DARK := [Color("1b5f86"), Color("8a2553")]
const GOLD := Color("ffd23f")
const SEG_Y := 0.42
const MAX_SEG := 1400

var logic := SnakeLogic.new()
var stages: Array = SnakeLogic.stage_defs()
var stage_idx := 0
var speed_key := "normal"
var win_target := 3
var vs_cpu := true
var ai_level := "medium"
var muted := false

var state := "menu"   # menu, countdown, playing, paused, roundover, matchover
var scores := [0, 0]
var round_n := 1
var acc := 0.0
var count_left := 0.0
var shake := 0.0
var t := 0.0

# scene
var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D
var cam_base: Transform3D
var board_root: Node3D
var fx_root: Node3D
var item_nodes := {}
var seg_mm: Array = []
var heads: Array = []
var daze: Array = []
var font_bold: FontFile
var mats := {}

# ui
var ui: Control
var hud: Control
var menu: Control
var overlay: PanelContainer
var ov_title: Label
var ov_body: Label
var ov_buttons: HBoxContainer
var big_label: Label
var p_name: Array = []
var p_info: Array = []
var p_status: Array = []
var stage_label: Label
var round_label: Label
var stage_desc: Label
var stage_buttons: Array = []
var seg_groups := {}
var ai_row: Control
var hint_label: Label

# audio
var players: Array = []
var sfx := {}

# dev: --autoplay / --shot=<png> for automated screenshots
var autoplay := false
var shot_path := ""
var shot_stage := -1


func _ready() -> void:
	randomize()
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--stage="):
			shot_stage = int(a.substr(8))
	font_bold = load("res://fonts/Mitr-SemiBold.ttf")
	_load_settings()
	_build_world()
	_build_audio()
	_build_ui()
	_show_board_preview()
	if shot_path != "" and not autoplay:
		await get_tree().create_timer(2.0).timeout
		_screenshot()
		get_tree().quit()
	if autoplay:
		if shot_stage >= 0:
			stage_idx = shot_stage
		_start_match()


# ---------------------------------------------------------------- settings
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") != OK:
		return
	stage_idx = clampi(cf.get_value("game", "stage", 0), 0, stages.size() - 1)
	speed_key = cf.get_value("game", "speed", "normal")
	win_target = cf.get_value("game", "wins", 3)
	vs_cpu = cf.get_value("game", "vs_cpu", true)
	ai_level = cf.get_value("game", "ai", "medium")
	muted = cf.get_value("game", "muted", false)
	if not SPEEDS.has(speed_key): speed_key = "normal"
	if not AI_NAMES.has(ai_level): ai_level = "medium"
	if not (win_target in [1, 3, 5]): win_target = 3


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "stage", stage_idx)
	cf.set_value("game", "speed", speed_key)
	cf.set_value("game", "wins", win_target)
	cf.set_value("game", "vs_cpu", vs_cpu)
	cf.set_value("game", "ai", ai_level)
	cf.set_value("game", "muted", muted)
	cf.save("user://settings.cfg")


# ---------------------------------------------------------------- world
func _mat(key: String, color: Color, rough := 0.6, metal := 0.0, emission := 0.0) -> StandardMaterial3D:
	var k := "%s_%s_%.2f_%.2f_%.2f" % [key, color.to_html(), rough, metal, emission]
	if mats.has(k):
		return mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	mats[k] = m
	return m


func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else board_root).add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return c


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func cell_pos(v: Vector2, y := 0.0) -> Vector3:
	return Vector3(v.x + 0.5, y, v.y + 0.5)


func _build_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	var center := Vector3(W / 2.0, 0, H / 2.0 - 0.4)
	cam.position = center + Vector3(0, 26.5, 17.0)
	cam.look_at(center, Vector3.UP)
	cam_base = cam.transform

	board_root = Node3D.new()
	add_child(board_root)
	fx_root = Node3D.new()
	add_child(fx_root)

	# snake bodies: one MultiMesh of spheres per snake, heads as separate nodes with eyes
	for p in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _sphere(0.4)
		mm.instance_count = MAX_SEG
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var bm := StandardMaterial3D.new()
		bm.vertex_color_use_as_albedo = true
		bm.roughness = 0.35
		bm.metallic = 0.1
		mmi.material_override = bm
		add_child(mmi)
		seg_mm.append(mm)

		var head := Node3D.new()
		add_child(head)
		_mesh(_sphere(0.5), _mat("head", P_MAIN[p], 0.3, 0.1), Vector3.ZERO, head)
		for sx in [-1, 1]:
			_mesh(_sphere(0.15), _mat("eye", Color.WHITE, 0.2), Vector3(0.2 * sx, 0.17, 0.33), head)
			_mesh(_sphere(0.075), _mat("pupil", Color("111111"), 0.2), Vector3(0.2 * sx, 0.19, 0.46), head)
		head.visible = false
		heads.append(head)

		var dz := Node3D.new()
		add_child(dz)
		for i in 3:
			_mesh(_sphere(0.09), _mat("daze", GOLD, 0.4, 0.0, 2.5), Vector3.ZERO, dz)
		dz.visible = false
		daze.append(dz)


func _clear_board() -> void:
	for c in board_root.get_children():
		c.queue_free()
	for k in item_nodes:
		item_nodes[k].queue_free()
	item_nodes.clear()
	for c in fx_root.get_children():
		c.queue_free()


func _build_board(st: Dictionary) -> void:
	_clear_board()
	env.background_color = st["sky"]
	env.ambient_light_color = st["sky"].lerp(Color.WHITE, 0.5)
	var space: bool = st["style"] == "rock"
	env.fog_enabled = false

	# ground around the board
	if not space:
		var g := PlaneMesh.new()
		g.size = Vector2(220, 220)
		_mesh(g, _mat("ground", st["ground"], 1.0), Vector3(W / 2.0, -1.2, H / 2.0))
	# board slab
	var slab_col: Color = st["bg"].darkened(0.45)
	_mesh(_box(Vector3(W + 1.0, 1.2, H + 1.0)), _mat("slab", slab_col, 0.8), Vector3(W / 2.0, -0.61, H / 2.0))
	# checker floor
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			img.set_pixel(x, y, st["bg"] if (x + y) % 2 == 0 else st["bg2"])
	var tex := ImageTexture.create_from_image(img)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = tex
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fm.roughness = 0.25 if st["style"] == "ice" else 0.9
	var fp := PlaneMesh.new()
	fp.size = Vector2(W, H)
	_mesh(fp, fm, Vector3(W / 2.0, 0.0, H / 2.0))

	if space:
		_build_stars()
	if st["style"] == "fence":
		_build_grass(st)

	for v in logic.build_obstacles(st):
		_build_wall(st, v)


func _build_wall(st: Dictionary, v: Vector2i) -> void:
	var c: Color = st["wall_col"]
	var edge: bool = v.x == 0 or v.y == 0 or v.x == W - 1 or v.y == H - 1
	var shade := 1.0 + (float((v.x * 7 + v.y * 13) % 5) - 2.0) * 0.04
	match st["style"]:
		"fence":
			_mesh(_box(Vector3(0.82, 0.9, 0.82)), _mat("fence", c * shade, 0.85), cell_pos(v, 0.45))
			_mesh(_box(Vector3(0.9, 0.12, 0.9)), _mat("fencecap", c.lightened(0.2), 0.8), cell_pos(v, 0.95))
		"brick":
			var bc := c * shade
			bc.a = 1.0
			_mesh(_box(Vector3(0.98, 1.0, 0.98)), _mat("brick", bc, 0.9), cell_pos(v, 0.5))
			_mesh(_box(Vector3(1.0, 0.06, 1.0)), _mat("mortar", Color("d8c8b8"), 0.9), cell_pos(v, 0.52))
		"cactus":
			if edge:
				_mesh(_box(Vector3(1.0, 0.5, 1.0)), _mat("dune", st["ground"].darkened(0.1), 1.0), cell_pos(v, 0.25))
			else:
				var green := _mat("cactus", c, 0.7)
				_mesh(_capsule(0.24, 1.3), green, cell_pos(v, 0.65))
				_mesh(_capsule(0.1, 0.5), green, cell_pos(v, 0.75) + Vector3(-0.3, 0, 0))
				_mesh(_capsule(0.1, 0.42), green, cell_pos(v, 0.95) + Vector3(0.3, 0, 0))
				var j1 := _mesh(_capsule(0.08, 0.3), green, cell_pos(v, 0.55) + Vector3(-0.2, 0, 0))
				j1.rotation_degrees.z = 90
				var j2 := _mesh(_capsule(0.08, 0.3), green, cell_pos(v, 0.75) + Vector3(0.2, 0, 0))
				j2.rotation_degrees.z = 90
		"ice":
			var im := StandardMaterial3D.new()
			im.albedo_color = Color(c.r, c.g, c.b, 0.82)
			im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			im.roughness = 0.08
			im.metallic = 0.2
			im.emission_enabled = true
			im.emission = c
			im.emission_energy_multiplier = 0.25
			_mesh(_box(Vector3(0.96, 1.2 + 0.15 * sin(v.x * 1.7 + v.y), 0.96)), im, cell_pos(v, 0.6))
		"rock":
			var r := _mesh(_sphere(0.55), _mat("rock", c * shade, 1.0), cell_pos(v, 0.4))
			r.scale = Vector3(1.0, 0.8, 1.0)
			r.rotation = Vector3(v.x, v.y, v.x + v.y)


func _build_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _sphere(0.08)
	mm.instance_count = 420
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-40, 72), rng.randf_range(-30, -4), rng.randf_range(-40, 50))
		var s := rng.randf_range(0.5, 2.2)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat("star", Color("e8e4ff"), 1.0, 0.0, 4.0)
	board_root.add_child(mmi)


func _build_grass(st: Dictionary) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box(Vector3(0.05, 0.22, 0.05))
	mm.instance_count = 240
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(1.2, W - 1.2), 0.1, rng.randf_range(1.2, H - 1.2))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.FORWARD, rng.randf_range(-0.3, 0.3)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat("grass", st["bg"].lightened(0.25), 1.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board_root.add_child(mmi)


func _show_board_preview() -> void:
	_build_board(stages[stage_idx])
	for p in 2:
		heads[p].visible = false
		seg_mm[p].visible_instance_count = 0
		daze[p].visible = false


# ---------------------------------------------------------------- fruit
func _make_item(it: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var holder := Node3D.new()
	holder.name = "Fruit"
	n.add_child(holder)
	match it["type"]:
		"apple":
			var a := _mesh(_sphere(0.34), _mat("apple", Color("e2312a"), 0.28, 0.05), Vector3.ZERO, holder)
			a.scale = Vector3(1.05, 0.95, 1.05)
			_mesh(_cyl(0.035, 0.22), _mat("stem", Color("5a3a1c"), 0.8), Vector3(0, 0.38, 0), holder)
			var leaf := _mesh(_sphere(0.14), _mat("leaf", Color("5fbf4a"), 0.6), Vector3(0.12, 0.42, 0), holder)
			leaf.scale = Vector3(1.4, 0.3, 0.7)
		"cherry":
			var red := _mat("cherry", Color("b80f3c"), 0.2, 0.05)
			_mesh(_sphere(0.21), red, Vector3(-0.17, -0.05, 0.02), holder)
			_mesh(_sphere(0.21), red, Vector3(0.17, -0.08, -0.02), holder)
			var stem := _mat("cstem", Color("4f8a2e"), 0.7)
			var s1 := _mesh(_cyl(0.025, 0.5), stem, Vector3(-0.08, 0.32, 0), holder)
			s1.rotation_degrees.z = -22
			var s2 := _mesh(_cyl(0.025, 0.5), stem, Vector3(0.08, 0.32, 0), holder)
			s2.rotation_degrees.z = 22
			var leaf := _mesh(_sphere(0.12), _mat("leaf", Color("5fbf4a"), 0.6), Vector3(0.1, 0.56, 0), holder)
			leaf.scale = Vector3(1.4, 0.3, 0.7)
		"banana":
			var yel := _mat("banana", Color("f6cf2d"), 0.45)
			for i in 7:
				var a := lerpf(-1.1, 1.1, i / 6.0)
				var r := 0.13 - absf(a) * 0.035
				_mesh(_sphere(r), yel, Vector3(sin(a) * 0.38, cos(a) * 0.38 - 0.3, 0), holder)
			var tip := _mat("btip", Color("5a3a1c"), 0.8)
			_mesh(_sphere(0.05), tip, Vector3(sin(-1.25) * 0.38, cos(-1.25) * 0.38 - 0.3, 0), holder)
			_mesh(_sphere(0.05), tip, Vector3(sin(1.25) * 0.38, cos(1.25) * 0.38 - 0.3, 0), holder)
	if it["type"] != "apple":
		var ring := TorusMesh.new()
		ring.inner_radius = 0.42
		ring.outer_radius = 0.5
		var col := Color("ff4d7d") if it["type"] == "cherry" else GOLD
		var rm := _mesh(ring, _mat("ring", col, 0.5, 0.0, 2.0), Vector3(0, -0.36, 0), n)
		rm.name = "Ring"
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position = cell_pos(Vector2(it["pos"]), 0.45)
	return n


func _sync_items() -> void:
	var live := {}
	for it in logic.items:
		live[it["id"]] = it
		if not item_nodes.has(it["id"]):
			item_nodes[it["id"]] = _make_item(it)
			_pop(item_nodes[it["id"]])
	for id in item_nodes.keys():
		if not live.has(id):
			item_nodes[id].queue_free()
			item_nodes.erase(id)
	for id in item_nodes:
		var it: Dictionary = live[id]
		var n: Node3D = item_nodes[id]
		var fruit: Node3D = n.get_node("Fruit")
		fruit.position.y = sin(t * 3.0 + id) * 0.08
		fruit.rotation.y = t * 1.2 + id
		var left: float = it["expires"] - logic.game_time
		n.visible = not (left < 2000.0 and int(t * 7.0) % 2 == 0)
		if n.has_node("Ring"):
			var ring: Node3D = n.get_node("Ring")
			ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(t * 5.0))


func _pop(n: Node3D) -> void:
	n.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- effects
func _burst(v: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.explosiveness = 0.95
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = _box(Vector3(0.14, 0.14, 0.14))
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.8
	p.material_override = m
	p.position = cell_pos(v, 0.5)
	fx_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _float_text(v: Vector2, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font_bold
	l.font_size = 72
	l.pixel_size = 0.012
	l.outline_size = 18
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = cell_pos(v, 1.3)
	fx_root.add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 2.8, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------- snake drawing
func _draw_snakes(T: float) -> void:
	for p in 2:
		var mm: MultiMesh = seg_mm[p]
		if logic.snakes.is_empty():
			mm.visible_instance_count = 0
			heads[p].visible = false
			continue
		var s = logic.snakes[p]
		var period := T * (2.0 if logic.is_slowed(s) else 1.0)
		var elapsed: float = (logic.tick_n - s.moved_tick) * T + acc
		var alpha: float = 1.0
		if state == "playing" or state == "paused":
			alpha = clampf(elapsed / period, 0.0, 1.0)
		elif state == "countdown":
			alpha = 0.0
		var pts: Array = []
		var n: int = s.body.size()
		for i in n:
			var cur := Vector2(s.body[i])
			var prv := Vector2(s.prev[i] if i < s.prev.size() else s.prev.back())
			if cur.distance_to(prv) > 1.5:
				prv = cur
			pts.append(prv.lerp(cur, alpha))
		var blink: bool = (not s.alive) and int(t * 8.0) % 2 == 0
		var idx := 0
		for i in n:
			if idx >= MAX_SEG - 2:
				break
			var f := float(i) / maxi(1, n - 1)
			var col: Color = P_MAIN[p].lerp(P_DARK[p], f * 0.75)
			if not s.alive:
				col = col.lerp(Color(0.35, 0.35, 0.35), 0.5)
			var sc := lerpf(1.0, 0.72, f)
			if i > 0:
				mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * sc), cell_pos(pts[i], SEG_Y * sc)))
				mm.set_instance_color(idx, col)
				idx += 1
				var a: Vector2 = pts[i - 1]
				var b: Vector2 = pts[i]
				if a.distance_to(b) < 1.2:
					var sc2 := lerpf(1.0, 0.72, (i - 0.5) / maxi(1, n - 1))
					mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * sc2), cell_pos(a.lerp(b, 0.5), SEG_Y * sc2)))
					mm.set_instance_color(idx, col)
					idx += 1
		mm.visible_instance_count = 0 if blink else idx
		var head: Node3D = heads[p]
		head.visible = not blink
		head.position = cell_pos(pts[0], 0.48)
		var d: Vector2i = SnakeLogic.DIRS[s.dir]
		var target_rot := atan2(float(d.x), float(d.y))
		head.rotation.y = lerp_angle(head.rotation.y, target_rot, 0.35)
		var dz: Node3D = daze[p]
		dz.visible = logic.is_slowed(s)
		if dz.visible:
			dz.position = head.position + Vector3(0, 0.75, 0)
			var k := 0
			for c in dz.get_children():
				var ang := t * 5.0 + k * TAU / 3.0
				c.position = Vector3(cos(ang) * 0.45, sin(ang * 2.0) * 0.05, sin(ang) * 0.45)
				k += 1


# ---------------------------------------------------------------- game flow
func _start_match() -> void:
	scores = [0, 0]
	round_n = 1
	menu.visible = false
	hud.visible = true
	p_name[1].text = ("คอม (%s)" % AI_NAMES[ai_level]) if vs_cpu else "ผู้เล่น 2"
	hint_label.text = "ผู้เล่น: W A S D หรือลูกศร · Space หยุดพัก · Esc เมนู" if vs_cpu else "ผู้เล่น 1: W A S D · ผู้เล่น 2: ลูกศร · Space หยุดพัก · Esc เมนู"
	_build_board(stages[stage_idx])
	stage_label.text = stages[stage_idx]["name"]
	_start_round()


func _start_round() -> void:
	logic.start_round(stages[stage_idx], ai_level if (vs_cpu or autoplay) else "")
	if autoplay:
		logic.snakes[0].ai = "hard"
	for id in item_nodes:
		item_nodes[id].queue_free()
	item_nodes.clear()
	acc = 0.0
	count_left = 2.4
	state = "countdown"
	overlay.visible = false
	_update_hud()


func _to_menu() -> void:
	state = "menu"
	overlay.visible = false
	big_label.visible = false
	hud.visible = false
	menu.visible = true
	logic.snakes = []
	_show_board_preview()
	_refresh_menu()


func _toggle_pause() -> void:
	if state == "playing":
		state = "paused"
		_show_overlay("หยุดพัก", "กด Space เพื่อเล่นต่อ", [["เล่นต่อ", _toggle_pause], ["ออกไปเมนู", _to_menu]])
	elif state == "paused":
		state = "playing"
		overlay.visible = false


func _player_name(p: int) -> String:
	if p == 1 and vs_cpu:
		return "คอม"
	return "ผู้เล่น %d" % (p + 1)


func _reason(code: String) -> String:
	match code:
		"wall": return "ชน" + stages[stage_idx]["wall"]
		"self": return "ชนตัวเอง"
		"other": return "ชนตัวอีกฝ่าย"
		"headon": return "หัวชนหัว"
	return ""


func _handle_events() -> void:
	for e in logic.events:
		match e["t"]:
			"apple":
				_play("apple")
				_burst(Vector2(e["pos"]), Color("e2312a"), 14)
				_float_text(Vector2(e["pos"]), "+3", P_MAIN[e["p"]])
			"cherry":
				_play("cherry")
				_float_text(Vector2(e["pos"]), "เชอร์รี่!", Color("ff6b8e"))
				_float_text(Vector2(e["tpos"]), ("หด -%d" % e["n"]) if e["n"] > 0 else "สั้นสุดแล้ว", P_MAIN[e["target"]])
				for c in e["cut"]:
					_burst(Vector2(c), P_MAIN[e["target"]], 8)
			"banana":
				_play("banana")
				_float_text(Vector2(e["pos"]), "กล้วย!", GOLD)
				_float_text(Vector2(e["tpos"]), "ช้าลง!", GOLD)
			"crash":
				_play("crash")
				shake = 0.6
				for s in e["snakes"]:
					_burst(Vector2(s.body[0]), P_MAIN[s.p], 40)
	logic.events.clear()


func _end_round() -> void:
	state = "roundover"
	var dead: Array = logic.dead_list
	var winner := -1
	if dead.size() == 1:
		winner = 1 - dead[0].p
		scores[winner] += 1
	_update_hud()
	var champ: bool = winner >= 0 and scores[winner] >= win_target
	await get_tree().create_timer(0.9).timeout
	if state != "roundover":
		return
	var score_txt := "สกอร์ %d : %d" % [scores[0], scores[1]]
	if champ:
		state = "matchover"
		_play("win")
		_show_overlay("%s เป็นแชมป์!" % _player_name(winner), score_txt + " ในฉาก" + stages[stage_idx]["name"],
			[["เล่นอีกครั้ง (Enter)", _start_match], ["เปลี่ยนฉาก", _to_menu]], P_MAIN[winner])
	else:
		var why := ""
		for s in dead:
			why += ("" if why == "" else " และ ") + _player_name(s.p) + " " + _reason(s.dead)
		var head: String = "เสมอ!" if winner < 0 else "%s ได้แต้ม" % _player_name(winner)
		_show_overlay(head, why + "\n" + score_txt, [["รอบต่อไป (Enter)", _next_round], ["เมนู", _to_menu]],
			Color.WHITE if winner < 0 else P_MAIN[winner])
	if autoplay and shot_path != "":
		await get_tree().create_timer(0.3).timeout
		_screenshot()
		get_tree().quit()


func _next_round() -> void:
	round_n += 1
	_start_round()


func _process(delta: float) -> void:
	t += delta
	var T: float = SPEEDS[speed_key]
	match state:
		"countdown":
			count_left -= delta
			var n := int(ceil(count_left / 0.8))
			if n != int(big_label.get_meta("n", -1)) and n > 0:
				big_label.set_meta("n", n)
				_play("count")
				_punch_big(str(n))
			if count_left <= 0.0:
				state = "playing"
				_play("go")
				_punch_big("ไป!")
				get_tree().create_timer(0.6).timeout.connect(_hide_big)
		"playing":
			var ms := delta * 1000.0
			logic.game_time += ms
			acc += ms
			while acc >= T and state == "playing":
				acc -= T
				logic.tick()
				_handle_events()
				if logic.over:
					_end_round()
					break
			if state == "playing":
				logic.update_items()
			_update_hud()
	if state != "menu":
		_sync_items()
		_draw_snakes(T)
	# camera: slow idle drift in the menu, shake on crashes
	var tr := cam_base
	if state == "menu":
		var c := Vector3(W / 2.0, 0, H / 2.0)
		var off := cam_base.origin - c
		tr.origin = c + off.rotated(Vector3.UP, sin(t * 0.25) * 0.18)
		tr = tr.looking_at(c, Vector3.UP)
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		tr.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.6
	cam.transform = tr
	if autoplay and shot_path != "" and state == "playing" and logic.game_time > 9000 and not has_meta("shot_done"):
		set_meta("shot_done", true)
		_screenshot("_mid")


func _hide_big() -> void:
	if state != "countdown":
		big_label.visible = false


func _screenshot(suffix := "") -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path.replace(".png", suffix + ".png"))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: InputEventKey = event
	var pk := k.physical_keycode
	var dir_map := {KEY_W: [0, "up"], KEY_A: [0, "left"], KEY_S: [0, "down"], KEY_D: [0, "right"],
		KEY_UP: [1, "up"], KEY_LEFT: [1, "left"], KEY_DOWN: [1, "down"], KEY_RIGHT: [1, "right"]}
	if dir_map.has(pk):
		if state == "playing" or state == "countdown":
			var m: Array = dir_map[pk]
			logic.queue_dir(0 if vs_cpu else m[0], m[1])
		get_viewport().set_input_as_handled()
		return
	match pk:
		KEY_ENTER, KEY_KP_ENTER:
			match state:
				"menu": _start_match()
				"roundover":
					if overlay.visible:
						_next_round()
				"matchover": _start_match()
				"paused": _toggle_pause()
		KEY_SPACE, KEY_P:
			if state == "playing" or state == "paused":
				_toggle_pause()
		KEY_ESCAPE:
			if state == "playing":
				_toggle_pause()
			elif state != "menu":
				_to_menu()
		KEY_M:
			muted = not muted
			_save_settings()


# ---------------------------------------------------------------- audio
func _tone(parts: Array, wave := "square", vol := 0.35) -> AudioStreamWAV:
	# parts: [[f1, f2, dur], ...] played back to back
	var rate := 22050
	var data := PackedByteArray()
	var phase := 0.0
	for prt in parts:
		var f1: float = prt[0]
		var f2: float = prt[1]
		var dur: float = prt[2]
		var n := int(rate * dur)
		var start := data.size()
		data.resize(start + n * 2)
		for i in n:
			var k := float(i) / n
			var f := f1 * pow(f2 / f1, k)
			phase += f / rate
			var s: float
			match wave:
				"square": s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
				"triangle": s = 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
				_: s = 2.0 * fmod(phase, 1.0) - 1.0
			var env_v := (1.0 - k) * minf(1.0, i / 80.0)
			data.encode_s16(start + i * 2, int(s * env_v * vol * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _build_audio() -> void:
	sfx["apple"] = _tone([[620, 980, 0.12]])
	sfx["cherry"] = _tone([[700, 500, 0.09], [420, 220, 0.16]])
	sfx["banana"] = _tone([[330, 140, 0.3]], "triangle", 0.5)
	sfx["crash"] = _tone([[220, 50, 0.45]], "saw", 0.4)
	sfx["count"] = _tone([[440, 440, 0.1]])
	sfx["go"] = _tone([[880, 880, 0.18]])
	sfx["win"] = _tone([[523, 523, 0.12], [659, 659, 0.12], [784, 784, 0.12], [1046, 1046, 0.3]])
	for i in 6:
		var ap := AudioStreamPlayer.new()
		ap.volume_db = -6.0
		add_child(ap)
		players.append(ap)


func _play(key: String) -> void:
	if muted or not sfx.has(key):
		return
	for ap in players:
		if not ap.playing:
			ap.stream = sfx[key]
			ap.play()
			return


# ---------------------------------------------------------------- UI
func _panel_style(bg: Color, radius := 16, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb


func _label(text: String, size := 22, color := Color("f1ecf8"), bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	return l


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var normal := _panel_style(GOLD if primary else Color("2a2338"), 999, Color("4a3f60"), 0 if primary else 1)
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.12)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color("f1ecf8") if not primary else GOLD.darkened(0.1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	var fc := Color("2a1e00") if primary else Color("f1ecf8")
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", Color("15121d"))
	b.add_theme_color_override("font_hover_pressed_color", Color("15121d"))
	b.pressed.connect(cb)
	return b


func _seg_row(title: String, key: String, opts: Array) -> HBoxContainer:
	# opts: [[label, value], ...]; a row of toggle buttons sharing one ButtonGroup
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _label(title, 18, Color("aaa0bd"))
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var group := ButtonGroup.new()
	var btns: Array = []
	for o in opts:
		var b := _button(o[0], _on_seg.bind(key, o[1]))
		b.toggle_mode = true
		b.button_group = group
		row.add_child(b)
		btns.append([b, o[1]])
	seg_groups[key] = btns
	return row


func _on_seg(key: String, value: Variant) -> void:
	match key:
		"mode": vs_cpu = value
		"ai": ai_level = value
		"speed": speed_key = value
		"wins": win_target = value
	_save_settings()
	_refresh_menu()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# ---- HUD
	hud = MarginContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right", "top"]:
		hud.add_theme_constant_override("margin_" + side, 16)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	hud.add_child(bar)
	for p in 2:
		var pc := PanelContainer.new()
		var hs := _panel_style(Color(0.08, 0.07, 0.11, 0.78), 14, P_MAIN[p], 2)
		hs.content_margin_top = 4
		hs.content_margin_bottom = 4
		pc.add_theme_stylebox_override("panel", hs)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		pc.add_child(vb)
		var nm := _label("ผู้เล่น %d" % (p + 1), 21, P_MAIN[p], true)
		var info := _label("", 16)
		var st := _label("", 14, GOLD)
		for l in [nm, info, st]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if p == 1 else HORIZONTAL_ALIGNMENT_LEFT
			vb.add_child(l)
		p_name.append(nm)
		p_info.append(info)
		p_status.append(st)
		if p == 0:
			bar.add_child(pc)
			var mid := VBoxContainer.new()
			mid.alignment = BoxContainer.ALIGNMENT_CENTER
			mid.custom_minimum_size.x = 260
			stage_label = _label("", 24, Color.WHITE, true)
			round_label = _label("", 16, Color("d8d0e6"))
			for l in [stage_label, round_label]:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.add_theme_constant_override("outline_size", 6)
				l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
				mid.add_child(l)
			bar.add_child(mid)
		else:
			bar.add_child(pc)
	hud.visible = false

	hint_label = _label("", 15, Color(1, 1, 1, 0.75))
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_label.position.y -= 12
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(hint_label)

	# ---- countdown
	big_label = _label("", 150, GOLD, true)
	big_label.add_theme_constant_override("outline_size", 28)
	big_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	big_label.set_anchors_preset(Control.PRESET_CENTER)
	big_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	big_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_label.visible = false
	ui.add_child(big_label)

	# ---- menu
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(center)
	menu = center
	var mp := PanelContainer.new()
	var mps := _panel_style(Color(0.08, 0.07, 0.11, 0.86), 22, Color("3a3150"), 1)
	mps.content_margin_left = 30
	mps.content_margin_right = 30
	mps.content_margin_top = 22
	mps.content_margin_bottom = 24
	mp.add_theme_stylebox_override("panel", mps)
	center.add_child(mp)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	mp.add_child(mv)
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_font_override("normal_font", font_bold)
	title.add_theme_font_size_override("normal_font_size", 64)
	title.text = "[color=#4cc9ff]สงคราม[/color][color=#ff5fa2]งู[/color] [color=#ffd23f][font_size=34]3D[/font_size][/color]"
	mv.add_child(title)
	mv.add_child(_label("ดวลงูกับคอม หรือเล่น 2 คนบนคีย์บอร์ดเดียวกัน ใครชนก่อนแพ้", 18, Color("aaa0bd")))

	mv.add_child(_label("เลือกฉาก", 20, Color.WHITE, true))
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 8)
	mv.add_child(sr)
	var sg := ButtonGroup.new()
	for i in stages.size():
		var b := _button(stages[i]["name"], _on_stage.bind(i))
		b.toggle_mode = true
		b.button_group = sg
		sr.add_child(b)
		stage_buttons.append(b)
	stage_desc = _label("", 17, Color("d8d0e6"))
	mv.add_child(stage_desc)

	mv.add_child(_seg_row("ผู้เล่น", "mode", [["เล่นกับคอม", true], ["2 คน", false]]))
	ai_row = _seg_row("ความเก่งของคอม", "ai", [["ง่าย", "easy"], ["กลาง", "medium"], ["ยาก", "hard"]])
	mv.add_child(ai_row)
	mv.add_child(_seg_row("ความเร็ว", "speed", [["ช้า", "slow"], ["ปกติ", "normal"], ["เร็ว", "fast"]]))
	mv.add_child(_seg_row("ชนะกี่รอบได้แชมป์", "wins", [["1", 1], ["3", 3], ["5", 5]]))

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 22)
	legend.add_child(_label("แอปเปิ้ล: ตัวเรายาว +3", 16, Color("ff7a6e")))
	legend.add_child(_label("เชอร์รี่: ศัตรูหด -3", 16, Color("ff6b8e")))
	legend.add_child(_label("กล้วย: ศัตรูช้าลง 5 วิ", 16, GOLD))
	mv.add_child(legend)

	var start_row := HBoxContainer.new()
	start_row.add_theme_constant_override("separation", 14)
	var sb := _button("เริ่มเกม", _start_match, true)
	sb.add_theme_font_size_override("font_size", 24)
	start_row.add_child(sb)
	start_row.add_child(_label("หรือกด Enter · ระหว่างเล่นกด Space หยุดพัก · M ปิดเสียง", 16, Color("aaa0bd")))
	mv.add_child(start_row)

	# ---- overlay
	var oc := CenterContainer.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	oc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(oc)
	overlay = PanelContainer.new()
	var ops := _panel_style(Color(0.08, 0.07, 0.11, 0.9), 18, Color("3a3150"), 1)
	ops.content_margin_left = 32
	ops.content_margin_right = 32
	ops.content_margin_top = 20
	ops.content_margin_bottom = 22
	overlay.add_theme_stylebox_override("panel", ops)
	oc.add_child(overlay)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	overlay.add_child(ov)
	ov_title = _label("", 36, Color.WHITE, true)
	ov_body = _label("", 19, Color("d8d0e6"))
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.add_child(ov_title)
	ov.add_child(ov_body)
	ov_buttons = HBoxContainer.new()
	ov_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	ov_buttons.add_theme_constant_override("separation", 10)
	ov.add_child(ov_buttons)
	overlay.visible = false

	_refresh_menu()


func _on_stage(i: int) -> void:
	stage_idx = i
	_save_settings()
	_refresh_menu()
	_show_board_preview()


func _refresh_menu() -> void:
	for i in stage_buttons.size():
		stage_buttons[i].set_pressed_no_signal(i == stage_idx)
	stage_desc.text = stages[stage_idx]["desc"]
	var cur := {"mode": vs_cpu, "ai": ai_level, "speed": speed_key, "wins": win_target}
	for key in seg_groups:
		for pair in seg_groups[key]:
			pair[0].set_pressed_no_signal(pair[1] == cur[key])
	ai_row.visible = vs_cpu


func _show_overlay(title: String, body: String, buttons: Array, color := Color.WHITE) -> void:
	ov_title.text = title
	ov_title.add_theme_color_override("font_color", color)
	ov_body.text = body
	for c in ov_buttons.get_children():
		c.queue_free()
	var first := true
	for b in buttons:
		ov_buttons.add_child(_button(b[0], b[1], first))
		first = false
	overlay.visible = true


func _punch_big(text: String) -> void:
	big_label.text = text
	big_label.visible = true
	big_label.pivot_offset = big_label.size / 2.0
	big_label.scale = Vector2.ONE * 1.6
	big_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(big_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_hud() -> void:
	if logic.snakes.is_empty():
		return
	for p in 2:
		var s = logic.snakes[p]
		var pips := "แต้ม %d/%d" % [scores[p], win_target]
		var len_txt := "ยาว %d" % (s.body.size() + s.grow)
		p_info[p].text = (pips + "  " + len_txt) if p == 0 else (len_txt + "  " + pips)
		var left: float = s.slow_until - logic.game_time
		p_status[p].text = ("กินกล้วย ช้าลง %.1f วิ" % (left / 1000.0)) if (left > 0 and s.alive) else " "
	round_label.text = "รอบที่ %d · ชนะ %d รอบได้แชมป์" % [round_n, win_target]
