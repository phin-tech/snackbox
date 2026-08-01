extends ScoreSandbox

# Mondrian: sealing pockets, and the painting it makes of them.

var game: Mondrian


func before_each() -> void:
	use_sandbox()
	game = load("res://mondrian.tscn").instantiate()
	add_child_autofree(game)
	game.set_process(false)


func after_all() -> void:
	release_sandbox()


func test_the_border_starts_claimed() -> void:
	assert_eq(game.grid[0][0], Mondrian.FILLED, "the frame is solid ground")
	assert_eq(game.grid[Mondrian.ROWS / 2][Mondrian.COLS / 2], Mondrian.EMPTY,
		"the middle is not")


func test_cutting_leaves_a_trail() -> void:
	# The border is two cells thick, so a cut has to start from its inner edge:
	# from the very corner, the step down is still solid ground.
	game.player = Vector2i(4, 1)
	game._step_player(Vector2i(0, 1))
	game._step_player(Vector2i(0, 1))
	assert_true(game.drawing, "stepping into open space starts a cut")
	assert_gt(game.trail.size(), 0, "and leaves a trail behind")


func test_sealing_a_pocket_claims_it() -> void:
	# Cut straight down from the top border to the bottom one: everything to
	# the left of the cut is sealed off.
	game.enemies = [{"pos": Vector2(Mondrian.COLS * 0.8, Mondrian.ROWS * 0.5), "vel": Vector2.ZERO}]
	game.player = Vector2i(4, 1)
	var before := game.claimed_percent
	for _i in Mondrian.ROWS:
		game._step_player(Vector2i(0, 1))
	assert_false(game.drawing, "reaching the far side should close the cut")
	assert_gt(game.claimed_percent, before, "and claim what it cut off")


func test_every_claimed_cell_belongs_to_a_painted_region() -> void:
	game.enemies = [{"pos": Vector2(Mondrian.COLS * 0.8, Mondrian.ROWS * 0.5), "vel": Vector2.ZERO}]
	game.player = Vector2i(4, 1)
	for _i in Mondrian.ROWS:
		game._step_player(Vector2i(0, 1))

	for r in Mondrian.ROWS:
		for c in Mondrian.COLS:
			if game.grid[r][c] != Mondrian.FILLED:
				continue
			var id: int = game.region_of[r][c]
			assert_between(id, 0, game.regions.size() - 1,
				"claimed cell %d,%d has no colour" % [c, r])


func test_dying_gives_the_trail_back() -> void:
	game.player = Vector2i(4, 1)
	for _i in 4:
		game._step_player(Vector2i(0, 1))
	var laid := game.trail.duplicate()
	assert_gt(laid.size(), 0)
	game._die()
	assert_eq(game.trail.size(), 0, "the trail should be gone")
	for cell in laid:
		assert_eq(game.grid[cell.y][cell.x], Mondrian.EMPTY,
			"and the ground it covered given back")


func test_a_drifter_stays_on_the_board() -> void:
	for _i in 200:
		game._move_enemies(1.0 / 60.0)
		for e in game.enemies:
			assert_between(e.pos.x, -1.0, float(Mondrian.COLS), "drifter left sideways")
			assert_between(e.pos.y, -1.0, float(Mondrian.ROWS), "drifter left endways")
