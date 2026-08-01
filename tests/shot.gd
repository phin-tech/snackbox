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
		"menu":
			return load("res://menu.tscn").instantiate()
		"marathon", "sprint", "ultra":
			var g: Game = load("res://game.tscn").instantiate()
			g.mode = id
			return g
		_:
			return load("res://%s.tscn" % id).instantiate()


func _demo(node: Node2D) -> void:
	if node is Game:
		_demo_blocks(node)
	elif node is Pills:
		_demo_pills(node)
	elif node is Landgrab:
		_demo_landgrab(node)
	elif node is Snake:
		_demo_snake(node)
	elif node is Doubles:
		_demo_doubles(node)


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


func _demo_landgrab(g: Landgrab) -> void:
	# Carve a couple of pockets so the shot shows claimed territory.
	var moves := [
		[Vector2i(0, 1), 20], [Vector2i(1, 0), 14], [Vector2i(0, -1), 20],
		[Vector2i(1, 0), 6], [Vector2i(0, 1), 26], [Vector2i(1, 0), 10],
		[Vector2i(0, -1), 26],
	]
	for m in moves:
		for _i in m[1]:
			if g.state != Landgrab.PLAYING:
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


func _demo_doubles(g: Doubles) -> void:
	var dirs := [Doubles.LEFT, Doubles.DOWN, Doubles.RIGHT, Doubles.DOWN]
	for i in 60:
		g._move(dirs[i % dirs.size()])
		if g.dead:
			return
