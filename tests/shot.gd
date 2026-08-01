extends Node

# Renders one screen to a PNG so the README can show real gameplay rather than
# empty boards. Each game is driven with a fixed timestep and a seeded set of
# moves first, so the same command always produces the same picture.
#
#   task shot ID=pills OUT=docs/pills.png
#   task shots                              (renders them all)

const DT := 1.0 / 60.0

var id := "menu"
var out := "/tmp/snackbox.png"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--id="):
			id = a.trim_prefix("--id=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")

	seed(7)
	var node := _build()
	# Landscape screens report their own size; match it or the frame is cropped.
	if node.has_method("design_size"):
		var design: Vector2 = node.design_size()
		get_window().content_scale_size = Vector2i(design)
		get_window().size = Vector2i(design)
		await get_tree().process_frame
	add_child(node)
	node.set_process(false)
	_demo(node)

	# Hand control back so the node draws itself, then grab the frame.
	node.set_process(true)
	node.queue_redraw()
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	if err != OK:
		push_error("could not save %s (error %d)" % [out, err])
		get_tree().quit(1)
		return
	print("saved ", out, " ", img.get_width(), "x", img.get_height())
	get_tree().quit(0)


func _build() -> Node2D:
	match id:
		"menu", "menu.sub":
			return load("res://menu.tscn").instantiate()
		"marathon", "sprint", "ultra":
			var g: Game = load("res://game.tscn").instantiate()
			g.mode = id
			return g
		_:
			return load("res://%s.tscn" % id).instantiate()


func _demo(node: Node2D) -> void:
	if node is Menu:
		if id == "menu.sub":
			node.path = [1] as Array[int]      # Puzzles
			node.index = 0
		return
	if node is Game:
		_demo_blocks(node)
	elif node is Pills:
		_demo_pills(node)
	elif node is Mondrian:
		_demo_mondrian(node)
	elif node is Snake:
		_demo_snake(node)
	elif node is Doubles:
		_demo_doubles(node)
	elif node is Pyramid:
		_demo_pyramid(node)
	elif node is Decant:
		_demo_decant(node)
	elif node is Fence:
		_demo_fence(node)
	elif node is Linkup:
		_demo_linkup(node)
	elif node is Gridlock:
		_demo_gridlock(node)
	elif node is Shapes:
		_demo_shapes(node)


func _demo_blocks(g: Game) -> void:
	for i in 900:
		g._process(DT)
		if g._stopped() or g.piece_type == -1:
			continue
		match randi() % 5:
			0: g._try_move(-1, 0)
			1: g._try_move(1, 0)
			2: g._try_rotate(1)
			_:
				if i % 40 == 0 and i > 0:
					g._hard_drop()


func _demo_pills(p: Pills) -> void:
	for i in 1500:
		p._process(DT)
		if p.state != Pills.FALLING:
			continue
		match randi() % 5:
			0: p._try_move(-1, 0)
			1: p._try_move(1, 0)
			2: p._try_rotate(1)
			_:
				if i % 60 == 0 and i > 0:
					p.pill_pos.y += p._drop_distance()
					p._lock_pill()


func _demo_mondrian(g: Mondrian) -> void:
	# Carve a couple of pockets so the shot shows claimed territory.
	var moves := [
		[Vector2i(0, 1), 20], [Vector2i(1, 0), 14], [Vector2i(0, -1), 20],
		[Vector2i(1, 0), 6], [Vector2i(0, 1), 26], [Vector2i(1, 0), 10],
		[Vector2i(0, -1), 26],
	]
	for m in moves:
		for _i in m[1]:
			if g.state != Mondrian.PLAYING:
				return
			g._step_player(m[0])
		g._move_enemies(DT)


func _demo_snake(g: Snake) -> void:
	# Feed it a few times so the snake has some length on screen.
	for _i in 8:
		g.body.insert(0, g.body[0] + g.dir)
		g.score += 10

	# Steer around walls and its own body - a screenshot of the death banner
	# isn't much of an advert.
	for i in 46:
		var options := [g.dir, Vector2i(-g.dir.y, g.dir.x), Vector2i(g.dir.y, -g.dir.x)]
		if i % 9 == 8:
			options.reverse()
		for d in options:
			var head: Vector2i = g.body[0] + d
			var inside := head.x >= 1 and head.x < Snake.COLS - 1 and head.y >= 1 and head.y < Snake.ROWS - 1
			if inside and not g.body.has(head):
				g.dir = d
				break
		g._step()
		if g.dead:
			return


func _demo_linkup(g: Linkup) -> void:
	# Lay down all but the last route, so the shot shows a board in progress.
	g.level = 3
	g._start_level()
	for i in g.pairs.size() - 1:
		var run: Array = g.pairs[i].solution
		g.grab(run[0])
		for j in range(1, run.size()):
			g.extend(run[j])
		g.release()
	g.cursor = g.pairs[g.pairs.size() - 1].a


func _demo_gridlock(g: Gridlock) -> void:
	g.level = 4
	g._start_level()
	# Shuffle a few cars so the board looks played rather than freshly dealt.
	for _i in 6:
		var idx := randi() % g.vehicles.size()
		g.move_vehicle(idx, 1 if randi() % 2 == 0 else -1)
	g.selected = 0
	g.cursor = g.vehicles[0].pos


func _demo_shapes(g: Shapes) -> void:
	# Lay down most of the tiling so the shot shows a board part-carved.
	g.level = 3
	g._start_level()
	var keep: int = maxi(g.solution.size() - 3, 1)
	for i in keep:
		g.place(g.solution[i].rect)
	g.cursor = g.solution[g.solution.size() - 1].rect.position


func _demo_pyramid(g: Pyramid) -> void:
	# Take a few obvious pairs so the shot shows a pyramid part-cleared.
	for _pass in 4:
		for i in Pyramid.SLOTS:
			if not g.available(i):
				continue
			if g.value_of(g.pyramid[i]) == 13:
				g.take_pyramid(i)
				continue
			for j in Pyramid.SLOTS:
				if i == j or not g.available(j):
					continue
				if g.value_of(g.pyramid[i]) + g.value_of(g.pyramid[j]) == 13:
					g.picked = -1
					g.take_pyramid(i)
					g.take_pyramid(j)
					break
	for _i in 3:
		g.deal()


func _demo_decant(g: Decant) -> void:
	g.level = 3
	g._start_level()
	# A couple of sensible pours, so it doesn't look freshly dealt.
	for _i in 3:
		for from in g.tubes.size():
			for to in g.tubes.size():
				if g.can_pour(from, to) and not g.tubes[to].is_empty():
					g.pour(from, to)
					break


func _demo_fence(g: Fence) -> void:
	# Draw most of a loop, so the shot shows a fence being laid rather than a
	# finished one.
	g.level = 3
	g._start_level()
	var corners: Array[Vector2i] = [
		Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3),
		Vector2i(6, 4), Vector2i(6, 5), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7),
		Vector2i(6, 7), Vector2i(5, 7), Vector2i(4, 7), Vector2i(3, 7), Vector2i(2, 7),
		Vector2i(2, 6), Vector2i(2, 5),
	]
	g.start_at(corners[0])
	for i in range(1, corners.size()):
		g.step_to(corners[i])


func _demo_doubles(g: Doubles) -> void:
	var dirs := [Doubles.LEFT, Doubles.DOWN, Doubles.RIGHT, Doubles.DOWN]
	for i in 60:
		g._move(dirs[i % dirs.size()])
		if g.dead:
			return
