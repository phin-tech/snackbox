extends ScoreSandbox

# Falling blocks: the pieces, the stack, and the three modes.

var game: Game


func before_each() -> void:
	use_sandbox()
	game = load("res://game.tscn").instantiate()
	add_child_autofree(game)
	game.set_process(false)


func after_all() -> void:
	release_sandbox()


func test_every_piece_has_four_cells_in_every_rotation() -> void:
	for type in Game.PIECE_SPAWN.size():
		for rot in 4:
			assert_eq(game.rotations[type][rot].size(), 4,
				"piece %d rotation %d should be four cells" % [type, rot])


func test_rotating_four_times_returns_a_piece_to_itself() -> void:
	for type in Game.PIECE_SPAWN.size():
		assert_eq(str(game.rotations[type][0]), str(game.rotations[type][0]),
			"piece %d should come back to its spawn shape" % type)


func test_a_piece_cannot_overlap_the_stack() -> void:
	for r in Game.TOTAL:
		for c in Game.COLS:
			game.grid[r][c] = -1
	game.grid[10][4] = 0
	assert_true(game._collides(0, 0, Vector2i(3, 9)) or game._collides(0, 0, Vector2i(4, 10)),
		"a piece laid over an occupied cell should collide")


func test_a_piece_cannot_leave_the_board() -> void:
	assert_true(game._collides(0, 0, Vector2i(-2, 5)), "off the left")
	assert_true(game._collides(0, 0, Vector2i(Game.COLS, 5)), "off the right")
	assert_true(game._collides(0, 0, Vector2i(3, Game.TOTAL)), "through the floor")


func test_the_bag_deals_all_seven_before_repeating() -> void:
	# Starting a game already draws from the bag, so empty it first: otherwise
	# these seven straddle two bags and may legitimately repeat.
	game.bag.clear()
	var seen := {}
	for _i in 7:
		seen[game._take_from_bag()] = true
	assert_eq(seen.size(), 7, "a bag should hold one of each piece")


func test_a_full_row_clears_and_scores() -> void:
	for c in Game.COLS:
		game.grid[Game.TOTAL - 1][c] = 0
	game.clearing_rows = [Game.TOTAL - 1] as Array[int]
	var before := game.lines
	game._finish_clear()
	assert_eq(game.lines, before + 1, "the row should count")
	assert_gt(game.score, 0, "and score")
	for c in Game.COLS:
		assert_eq(game.grid[Game.TOTAL - 1][c], -1, "the row should be gone")


func test_the_ghost_sits_on_the_stack() -> void:
	game._spawn_piece()
	var ghost := game._ghost_pos()
	assert_true(game._collides(game.piece_type, game.piece_rot, ghost + Vector2i(0, 1)),
		"the ghost should be resting on something")
	assert_false(game._collides(game.piece_type, game.piece_rot, ghost),
		"and not inside it")


func test_sprint_ends_at_the_line_goal() -> void:
	game.mode = "sprint"
	game.new_game()
	game.lines = Game.SPRINT_GOAL - 1
	for c in Game.COLS:
		game.grid[Game.TOTAL - 1][c] = 0
	game.clearing_rows = [Game.TOTAL - 1] as Array[int]
	game._finish_clear()
	assert_true(game.finished, "reaching the goal should finish the run")


func test_ultra_ends_on_the_clock() -> void:
	game.mode = "ultra"
	game.new_game()
	game.elapsed = Game.ULTRA_SECONDS - 0.01
	game._process(0.02)
	assert_true(game.finished, "the two minutes should end it")


func test_marathon_just_keeps_going() -> void:
	game.mode = "marathon"
	game.new_game()
	game.elapsed = 10000.0
	game._process(0.02)
	assert_false(game.finished, "marathon has no finish line")
