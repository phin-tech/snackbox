extends ScoreSandbox

# The promise the seeds make: same code, same board, for everyone.

const GAMES := ["shapes", "decant", "linkup", "gridlock"]


func before_each() -> void:
	use_sandbox()


func after_all() -> void:
	release_sandbox()


func fingerprint(game: Node) -> String:
	if game is Shapes:
		var out := ""
		for piece in game.solution:
			out += str(piece.rect)
		return out + str(game.clues)
	if game is Decant:
		return str(game.tubes)
	if game is Linkup:
		var out2 := ""
		for p in game.pairs:
			out2 += str(p.solution)
		return out2
	if game is Gridlock:
		return str(game.vehicles)
	return ""


func deal(scene: String, base: int) -> String:
	var game: Node = load("res://%s.tscn" % scene).instantiate()
	add_child_autofree(game)
	game.set_process(false)
	game.seeds.base = base
	game.level = 2
	game._start_level()
	return fingerprint(game)


func test_the_same_seed_deals_the_same_board() -> void:
	for scene in GAMES:
		assert_eq(deal(scene, 4242), deal(scene, 4242),
			"%s should deal one board per seed" % scene)


func test_a_different_seed_deals_a_different_board() -> void:
	for scene in GAMES:
		assert_ne(deal(scene, 4242), deal(scene, 9999),
			"%s should deal different boards for different seeds" % scene)


func test_a_fingerprint_actually_describes_the_board() -> void:
	# Guards the test itself: an empty fingerprint would make the two above pass
	# without checking anything.
	for scene in GAMES:
		assert_ne(deal(scene, 4242), "", "%s has no fingerprint to compare" % scene)
