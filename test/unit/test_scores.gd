extends GutTest

# The score file: tables, the name attached to them, and where you got to.

const TEST_PATH := "user://gut_scores.cfg"


func before_each() -> void:
	Scores.path = TEST_PATH
	Scores.reload()
	Scores.clear()


func after_all() -> void:
	Scores.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Scores.path = Scores.DEFAULT_PATH
	Scores.reload()


func test_a_new_table_is_empty() -> void:
	assert_eq(Scores.table("t").size(), 0)
	assert_true(Scores.qualifies("t", 1.0), "an empty table should take anything")


func test_scores_are_listed_best_first() -> void:
	Scores.submit_entry("t", "ADA", 100.0)
	Scores.submit_entry("t", "GRACE", 300.0)
	Scores.submit_entry("t", "ALAN", 200.0)

	var rows := Scores.table("t")
	assert_eq(rows.size(), 3)
	assert_eq(str(rows[0].name), "GRACE", "the best score should be first")
	assert_eq(str(rows[2].name), "ADA", "the worst should be last")


func test_a_placing_comes_back() -> void:
	Scores.submit_entry("t", "ADA", 100.0)
	Scores.submit_entry("t", "GRACE", 300.0)
	assert_eq(Scores.submit_entry("t", "BOB", 200.0), 2, "should report second place")


func test_the_seed_is_kept_with_the_score() -> void:
	Scores.submit_entry("t", "ADA", 100.0, "A7K2")
	assert_eq(str(Scores.table("t")[0].seed), "A7K2",
		"a score means nothing without the board it was set on")


func test_the_table_is_capped_and_sheds_the_worst() -> void:
	for i in Scores.TABLE_SIZE + 4:
		Scores.submit_entry("t", "N%d" % i, float(100 + i))
	var rows := Scores.table("t")
	assert_eq(rows.size(), Scores.TABLE_SIZE, "the table should not grow forever")
	for row in rows:
		assert_gt(float(row.score), 103.0, "the low scores should have fallen off")
	assert_false(Scores.qualifies("t", 5.0), "a full table should turn away a poor score")


func test_times_rank_the_other_way() -> void:
	Scores.submit_entry("time", "ADA", 30.0, "", true)
	Scores.submit_entry("time", "ALAN", 20.0, "", true)
	assert_eq(str(Scores.table("time")[0].name), "ALAN", "faster should come first")
	assert_true(Scores.qualifies("time", 10.0, true), "a faster time should qualify")


func test_a_blank_name_still_records() -> void:
	Scores.submit_entry("anon", "   ", 5.0)
	assert_eq(Scores.table("anon").size(), 1, "the score should not vanish with the name")


func test_the_last_name_is_offered_back() -> void:
	Scores.remember_name("ADA")
	assert_eq(Scores.last_name(), "ADA")


func test_everything_survives_a_reload() -> void:
	# Regression: saving one section used to wipe the others, so recording a
	# name destroyed the tables.
	Scores.submit_entry("t", "ADA", 100.0, "A7K2")
	Scores.remember_name("ADA")

	Scores.reload()
	assert_eq(Scores.table("t").size(), 1, "the table should still be there")
	assert_eq(Scores.last_name(), "ADA", "the name should still be there")
	assert_eq(Scores.table("t").size(), 1, "and still only the one row")


func test_a_game_records_its_own_best_as_well() -> void:
	assert_true(Scores.submit_high("marathon", 500.0), "a first score is a best")
	assert_false(Scores.submit_high("marathon", 100.0), "a worse one is not")
	assert_eq(Scores.get_best("marathon"), 500.0)
	assert_true(Scores.submit_low("sprint", 60.0), "a first time is a best")
	assert_false(Scores.submit_low("sprint", 90.0), "a slower one is not")
