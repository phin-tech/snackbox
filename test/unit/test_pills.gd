extends ScoreSandbox

# Pill Doctor: matching, chains, and the links between pill halves.

var game: Pills


func before_each() -> void:
	use_sandbox()
	game = load("res://pills.tscn").instantiate()
	add_child_autofree(game)
	game.set_process(false)
	for r in Pills.ROWS:
		for c in Pills.COLS:
			game.kind[r][c] = Pills.EMPTY
			game.color[r][c] = -1
	game.viruses_left = 0
	game.chain = 0
	game.pending.clear()
	game.state = Pills.FALLING


func after_all() -> void:
	release_sandbox()


func put(c: int, r: int, colour: int, kind := Pills.SINGLE) -> void:
	game.kind[r][c] = kind
	game.color[r][c] = colour
	if kind == Pills.VIRUS:
		game.viruses_left += 1


func settle(max_frames := 600) -> int:
	var best := 0
	for _i in max_frames:
		if game.state in [Pills.FALLING, Pills.WON, Pills.LOST]:
			break
		game._process(1.0 / 60.0)
		best = max(best, game.chain)
	return max(best, game.chain)


func test_four_in_a_row_clears() -> void:
	var bottom := Pills.ROWS - 1
	for c in 3:
		put(c, bottom, 0)
	put(3, bottom, 0, Pills.VIRUS)
	game._resolve()
	settle()
	assert_eq(game.viruses_left, 0, "the virus in the run should go")
	assert_eq(game.kind[bottom][0], Pills.EMPTY, "and the pill halves with it")


func test_three_in_a_row_does_not() -> void:
	var bottom := Pills.ROWS - 1
	for c in 3:
		put(c, bottom, 0)
	game._resolve()
	assert_eq(game.kind[bottom][0], Pills.SINGLE, "three is not a match")


func test_four_in_a_column_clears() -> void:
	var bottom := Pills.ROWS - 1
	for i in 3:
		put(2, bottom - i, 1)
	put(2, bottom - 3, 1, Pills.VIRUS)
	game._resolve()
	settle()
	assert_eq(game.viruses_left, 0)


func test_clearing_the_last_virus_wins() -> void:
	var bottom := Pills.ROWS - 1
	for c in 3:
		put(c, bottom, 0)
	put(3, bottom, 0, Pills.VIRUS)
	game._resolve()
	settle()
	assert_eq(game.state, Pills.WON)


func test_what_falls_can_chain() -> void:
	var bottom := Pills.ROWS - 1
	for c in 4:
		put(c, bottom, 0)
	for c in 3:
		put(c, bottom - 1, 1)
	put(3, bottom - 3, 1)
	put(7, bottom, 2, Pills.VIRUS)      # keeps the level from ending
	game._resolve()
	assert_gte(settle(), 2, "the second match should count as a chain")


func test_a_half_left_behind_becomes_a_single() -> void:
	var bottom := Pills.ROWS - 1
	# A horizontal pill whose left half is part of a clearing run.
	for c in 3:
		put(c, bottom, 0)
	put(3, bottom, 0, Pills.LINK_RIGHT)
	put(4, bottom, 1, Pills.LINK_LEFT)
	game._resolve()
	settle()
	assert_eq(game.kind[bottom][4], Pills.SINGLE,
		"the surviving half should be freed, not left pointing at nothing")
