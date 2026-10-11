extends SceneTree
## Headless test runner for dice math, ledger round-trip and board push/crush.
## Run: godot --headless --path <project> --script res://tests/scr_test_dice.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_dice_basics()
	_test_resolve_cases()
	_test_exact_odds()
	_test_monte_carlo()
	_test_ledger_round_trip()
	_test_crit_push_and_crush()
	_test_normal_win_tie_and_fumble()
	_test_bonus_crit_does_not_chain()
	_test_bonus_fumble()
	print("\nRESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		_failed += 1
		print("  FAIL ", name, ("  " + detail) if detail != "" else "")


func _test_dice_basics() -> void:
	print("\n[dice basics]")
	_check("d4/d6 cannot crit or fumble", not KgDice.can_crit(4) and not KgDice.can_crit(6)
		and not KgDice.can_fumble(4) and not KgDice.can_fumble(6))
	_check("d8/d10/d12 can crit and fumble", KgDice.can_crit(8) and KgDice.can_crit(10)
		and KgDice.can_crit(12) and KgDice.can_fumble(8))
	_check("step_up d4->d6, d12->d12", KgDice.step_up(4) == 6 and KgDice.step_up(12) == 12)
	var r1 := KgDice.make_rng(42)
	var r2 := KgDice.make_rng(42)
	var same: bool = true
	var in_range: bool = true
	var seen: Dictionary = {}
	for i in range(2000):
		var a: int = KgDice.roll(r1, 12)
		if a != KgDice.roll(r2, 12):
			same = false
		if a < 1 or a > 12:
			in_range = false
		seen[a] = true
	_check("seeded rolls reproducible", same)
	_check("d12 rolls in 1..12 and all faces seen", in_range and seen.size() == 12)


func _test_resolve_cases() -> void:
	print("\n[resolve cases]")
	_check("d4 4 vs d12 4 -> tie, defender wins",
		KgCombat.resolve(4, 12, 4, 4)["result"] == KgCombat.RESULT_DEFENDER_WIN and KgCombat.resolve(4, 12, 4, 4)["is_tie"])
	_check("d8 8 vs d12 12 -> crit beats higher roll", KgCombat.resolve(8, 12, 8, 12)["result"] == KgCombat.RESULT_CRIT)
	_check("d8 natural 1 -> fumble", KgCombat.resolve(8, 4, 1, 1)["result"] == KgCombat.RESULT_FUMBLE)
	_check("d8 natural 1 +2 Surge still fumble", KgCombat.resolve(8, 4, 1, 1, 2, 0)["result"] == KgCombat.RESULT_FUMBLE)
	_check("d6 natural 1 is a normal miss", KgCombat.resolve(6, 4, 1, 1)["result"] == KgCombat.RESULT_DEFENDER_WIN)
	_check("d6 natural 6 is not a crit", KgCombat.resolve(6, 8, 6, 7)["result"] == KgCombat.RESULT_DEFENDER_WIN)
	_check("d12 max is crit", KgCombat.resolve(12, 4, 12, 1)["is_crit"])
	_check("defense -1 flips a tie", KgCombat.resolve(6, 6, 3, 3, 0, -1)["result"] == KgCombat.RESULT_ATTACKER_WIN)


func _fmt(o: Dictionary) -> String:
	var c: Dictionary = o["counts"]
	return "capture=%d/%d (%.4f) crit=%d fumble=%d plain_win=%d def_win=%d ties=%d" % [
		int(o["attacker_capture_count"]), int(o["total_outcomes"]), float(o["p_attacker_capture"]),
		int(c["crit"]), int(c["fumble"]), int(c["attacker_win"]), int(c["defender_win"]), int(c["tie"])]


func _test_exact_odds() -> void:
	print("\n[exact odds, all pairs: attacker row vs defender]")
	for a in KgDice.VALID_SIDES:
		for d in KgDice.VALID_SIDES:
			print("    d%-2d vs d%-2d  %s" % [a, d, _fmt(KgCombat.exact_odds(a, d))])
	var o: Dictionary = KgCombat.exact_odds(10, 4)
	_check("d10 vs d4 capture = 30/40", int(o["attacker_capture_count"]) == 30, _fmt(o))
	_check("d10 vs d4 crit 4, fumble 4, def_win 6, ties 3",
		int(o["counts"]["crit"]) == 4 and int(o["counts"]["fumble"]) == 4
		and int(o["counts"]["defender_win"]) == 6 and int(o["counts"]["tie"]) == 3)
	var pp: Dictionary = KgCombat.exact_odds(4, 4)
	_check("d4 vs d4 capture = 6/16, no crit/fumble", int(pp["attacker_capture_count"]) == 6
		and int(pp["counts"]["crit"]) == 0 and int(pp["counts"]["fumble"]) == 0, _fmt(pp))
	var kk: Dictionary = KgCombat.exact_odds(12, 12)
	# crit: 12 outcomes; plain win a in 2..11 with a>d: sum(a-1)=1+..+10=55; total 67/144
	_check("d12 vs d12 capture = 67/144", int(kk["attacker_capture_count"]) == 67, _fmt(kk))
	var probs_sum: float = float(o["p_crit"]) + float(o["p_attacker_win_plain"]) + float(o["p_defender_win"]) + float(o["p_fumble"])
	_check("probabilities sum to 1", absf(probs_sum - 1.0) < 1e-9)
	var bonus_odds: Dictionary = KgCombat.exact_odds(8, 12, 0, 0, false)
	_check("bonus-action odds d8 vs d12: no crits, capture 28/96", int(bonus_odds["counts"]["crit"]) == 0
		and int(bonus_odds["attacker_capture_count"]) == 28 and int(bonus_odds["counts"]["fumble"]) == 12, _fmt(bonus_odds))
	var surge: Dictionary = KgCombat.exact_odds(4, 4, 2, 0)
	print("    d4+2 (Surge) vs d4  %s" % _fmt(surge))


func _test_monte_carlo() -> void:
	print("\n[monte carlo, seed 12345, 200000 trials]")
	var rng := KgDice.make_rng(12345)
	for pair in [[10, 4], [4, 10], [8, 8], [12, 6]]:
		var ex: Dictionary = KgCombat.exact_odds(pair[0], pair[1])
		var mc: Dictionary = KgCombat.monte_carlo(rng, pair[0], pair[1], 200000)
		var diff: float = absf(float(mc["p_attacker_capture"]) - float(ex["p_attacker_capture"]))
		_check("MC d%d vs d%d within 0.01 of exact" % [pair[0], pair[1]], diff < 0.01,
			"exact=%.4f mc=%.4f crit_mc=%.4f fumble_mc=%.4f" % [float(ex["p_attacker_capture"]),
			float(mc["p_attacker_capture"]), float(mc["p_crit"]), float(mc["p_fumble"])])


func _test_ledger_round_trip() -> void:
	print("\n[ledger round trip]")
	var ledger: Dictionary = KgLedger.new_standard_ledger(777)
	var board := KgBoard.new(ledger)
	# A few real actions so the log and rng_state are non-trivial.
	var pawn: String = KgLedger.piece_id_at(ledger, 4, 6)
	_check("player pawn double-step", bool(board.move(pawn, Vector2i(4, 4))["ok"]))
	var rpawn: String = KgLedger.piece_id_at(ledger, 3, 1)
	_check("rival pawn double-step", bool(board.move(rpawn, Vector2i(3, 3))["ok"]))
	_check("wrong-side move rejected", not bool(board.move(rpawn, Vector2i(3, 4))["ok"]))
	var atk: Dictionary = board.attack(pawn, Vector2i(3, 3))
	_check("random pawn attack resolved", bool(atk["ok"]), "result=%s" % atk.get("outcome", {}).get("result", "?"))
	var path: String = "res://data/test_ledger_roundtrip.json"
	_check("save ok", KgLedger.save_ledger(ledger, path) == OK)
	var loaded: Dictionary = KgLedger.load_ledger(path)
	_check("load ok and valid", not loaded.is_empty() and KgLedger.validate(loaded).is_empty())
	_check("JSON identical after round trip", KgLedger.to_json_text(loaded) == KgLedger.to_json_text(ledger))
	_check("ints stay ints after load", typeof(loaded["game_state"]["turn_number"]) == TYPE_INT)
	_check("action_log length kept", loaded["action_log"].size() == ledger["action_log"].size(),
		"entries=%d" % ledger["action_log"].size())
	# RNG continuity: a reloaded board must produce the same next rolls.
	var b_live := KgBoard.new(ledger)
	var b_loaded := KgBoard.new(loaded)
	var same: bool = true
	for i in range(50):
		if KgDice.roll(b_live.rng, 12) != KgDice.roll(b_loaded.rng, 12):
			same = false
	_check("rng continues identically after reload", same)
	var bad: Dictionary = loaded.duplicate(true)
	bad["action_log"][0]["action_index"] = 5
	_check("tampered (non-sequential) log rejected", not KgLedger.validate(bad).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_crit_push_and_crush() -> void:
	print("\n[crit push-back / crush]")
	var L: Dictionary = KgLedger.new_empty_ledger(8, 8, 1)
	var rook: String = KgLedger.add_piece(L, "rook", "player", 1, 7)
	var target: String = KgLedger.add_piece(L, "pawn", "rival", 1, 3)
	var e_edge: String = KgLedger.add_piece(L, "pawn", "rival", 0, 3)    # pushed off west edge
	var e_free: String = KgLedger.add_piece(L, "knight", "rival", 2, 2)  # pushed NE to empty (3,1)
	var e_friend: String = KgLedger.add_piece(L, "pawn", "rival", 1, 2)  # behind it (1,1) is own side
	var e_behind: String = KgLedger.add_piece(L, "pawn", "rival", 1, 1)  # not adjacent, stays
	var e_foe: String = KgLedger.add_piece(L, "bishop", "rival", 2, 3)   # behind it (3,3) is player
	var f_adj: String = KgLedger.add_piece(L, "pawn", "player", 2, 4)    # friendly, never pushed
	var f_block: String = KgLedger.add_piece(L, "pawn", "player", 3, 3)
	var board := KgBoard.new(L)
	var r: Dictionary = board.attack_with_rolls(rook, Vector2i(1, 3), 8, 4)
	_check("attack ok and is crit", bool(r["ok"]) and r["outcome"]["result"] == KgCombat.RESULT_CRIT)
	var P: Dictionary = L["pieces"]
	_check("target captured", not P.has(target))
	_check("rook moved into (1,3)", int(P[rook]["tile_x"]) == 1 and int(P[rook]["tile_y"]) == 3)
	_check("edge push -> crushed", not P.has(e_edge))
	_check("push into empty -> moved to (3,1)", P.has(e_free) and int(P[e_free]["tile_x"]) == 3 and int(P[e_free]["tile_y"]) == 1)
	_check("push into own-side piece -> crushed", not P.has(e_friend))
	_check("push into enemy piece -> crushed", not P.has(e_foe))
	_check("non-adjacent piece untouched", P.has(e_behind) and int(P[e_behind]["tile_y"]) == 1)
	_check("attacker's friends untouched", P.has(f_adj) and P.has(f_block) and int(P[f_adj]["tile_x"]) == 2)
	_check("4 pushes recorded", r["pushes"].size() == 4, str(r["pushes"]))
	var gs: Dictionary = L["game_state"]
	_check("bonus action pending, turn not passed", gs["pending_bonus_piece_id"] == rook and gs["active_side"] == "player")
	_check("other piece cannot use bonus", not bool(board.move(f_adj, Vector2i(2, 3))["ok"]))
	_check("rook uses bonus move", bool(board.move(rook, Vector2i(1, 4))["ok"]))
	_check("turn passed after bonus", gs["active_side"] == "rival" and gs["pending_bonus_piece_id"] == "")
	_check("captured_pieces has 4", L["captured_pieces"].size() == 4)
	var log_a: Array = L["action_log"]
	_check("crit attack logged is_bonus_action=false", log_a[0]["action_type"] == "attack"
		and log_a[0]["details"]["is_bonus_action"] == false)
	_check("bonus move logged is_bonus_action=true", log_a[2]["action_type"] == "move"
		and log_a[2]["details"]["is_bonus_action"] == true)


func _test_normal_win_tie_and_fumble() -> void:
	print("\n[normal win / tie / fumble debuff]")
	var L: Dictionary = KgLedger.new_empty_ledger(8, 8, 2)
	var q: String = KgLedger.add_piece(L, "queen", "player", 0, 7)
	var rk: String = KgLedger.add_piece(L, "rook", "rival", 0, 0)
	var board := KgBoard.new(L)
	var r: Dictionary = board.attack_with_rolls(q, Vector2i(0, 0), 1, 3)
	_check("queen natural 1 -> fumble, both survive", r["outcome"]["result"] == KgCombat.RESULT_FUMBLE
		and L["pieces"].has(q) and L["pieces"].has(rk))
	_check("fumble: -1 defense stored, turn ended", int(L["pieces"][q]["next_defense_modifier"]) == -1
		and L["game_state"]["active_side"] == "rival")
	r = board.attack_with_rolls(rk, Vector2i(0, 7), 5, 5)
	_check("rook 5 vs queen 5-1=4 -> rook wins via debuff", r["outcome"]["result"] == KgCombat.RESULT_ATTACKER_WIN
		and int(r["outcome"]["defender_total"]) == 4 and not L["pieces"].has(q))
	var L2: Dictionary = KgLedger.new_empty_ledger(8, 8, 3)
	var p1: String = KgLedger.add_piece(L2, "pawn", "player", 3, 4)
	var p2: String = KgLedger.add_piece(L2, "pawn", "rival", 4, 3)
	var b2 := KgBoard.new(L2)
	r = b2.attack_with_rolls(p1, Vector2i(4, 3), 3, 3)
	_check("pawn tie -> attacker removed, defender stays", r["outcome"]["is_tie"] and not L2["pieces"].has(p1)
		and L2["pieces"].has(p2) and int(L2["pieces"][p2]["tile_x"]) == 4)


func _test_bonus_crit_does_not_chain() -> void:
	print("\n[bonus action: max roll is NOT a crit, no chain, no push]")
	var L: Dictionary = KgLedger.new_empty_ledger(8, 8, 4)
	var rook: String = KgLedger.add_piece(L, "rook", "player", 1, 7)
	var t1: String = KgLedger.add_piece(L, "pawn", "rival", 1, 3)
	var t2: String = KgLedger.add_piece(L, "pawn", "rival", 1, 1)
	var edge_n: String = KgLedger.add_piece(L, "pawn", "rival", 0, 1)   # would be crushed off edge by a push
	var free_n: String = KgLedger.add_piece(L, "pawn", "rival", 2, 1)   # would be pushed to (3,1) by a push
	KgLedger.add_piece(L, "king", "rival", 7, 0)
	var board := KgBoard.new(L)
	var r1: Dictionary = board.attack_with_rolls(rook, Vector2i(1, 3), 8, 1)
	_check("first attack is a real crit", bool(r1["ok"]) and r1["outcome"]["result"] == KgCombat.RESULT_CRIT
		and not bool(r1["is_bonus_action"]))
	_check("bonus granted to rook", L["game_state"]["pending_bonus_piece_id"] == rook)
	var r2: Dictionary = board.attack_with_rolls(rook, Vector2i(1, 1), 8, 1)
	var o2: Dictionary = r2["outcome"]
	_check("bonus attack natural 8 -> attacker_win, not crit", bool(r2["ok"])
		and o2["result"] == KgCombat.RESULT_ATTACKER_WIN and not bool(o2["is_crit"]) and bool(o2["crit_suppressed"]))
	_check("bonus attack: defender removed, rook moved in", not L["pieces"].has(t2)
		and int(L["pieces"][rook]["tile_x"]) == 1 and int(L["pieces"][rook]["tile_y"]) == 1)
	_check("bonus attack: no pushes", r2["pushes"].is_empty())
	_check("bonus attack: adjacent enemies untouched", L["pieces"].has(edge_n) and L["pieces"].has(free_n)
		and int(L["pieces"][edge_n]["tile_x"]) == 0 and int(L["pieces"][free_n]["tile_x"]) == 2)
	var gs: Dictionary = L["game_state"]
	_check("no further bonus, turn passed", gs["pending_bonus_piece_id"] == "" and gs["active_side"] == "rival"
		and int(gs["turn_number"]) == 2)
	var grants: int = 0
	var attacks: Array = []
	for e in L["action_log"]:
		if e["action_type"] == "bonus_action_granted":
			grants += 1
		if e["action_type"] == "attack":
			attacks.append(e)
	_check("exactly one bonus_action_granted in log", grants == 1)
	_check("log: attack1 is_bonus_action=false, attack2 true", attacks.size() == 2
		and attacks[0]["details"]["is_bonus_action"] == false and attacks[1]["details"]["is_bonus_action"] == true)
	_check("rook cannot act again this turn", not bool(board.move(rook, Vector2i(1, 2))["ok"]))
	_check("t1 captured", not L["pieces"].has(t1))


func _test_bonus_fumble() -> void:
	print("\n[bonus action: fumble still applies]")
	var L: Dictionary = KgLedger.new_empty_ledger(8, 8, 5)
	var q: String = KgLedger.add_piece(L, "queen", "player", 3, 7)
	var t1: String = KgLedger.add_piece(L, "pawn", "rival", 3, 4)
	var t2: String = KgLedger.add_piece(L, "rook", "rival", 3, 1)
	var board := KgBoard.new(L)
	var r1: Dictionary = board.attack_with_rolls(q, Vector2i(3, 4), 10, 1)
	_check("queen crit grants bonus", r1["outcome"]["result"] == KgCombat.RESULT_CRIT
		and L["game_state"]["pending_bonus_piece_id"] == q)
	L["pieces"][q]["next_defense_modifier"] = -1  # pre-existing debuff, must not stack
	var r2: Dictionary = board.attack_with_rolls(q, Vector2i(3, 1), 1, 8, 2, 0)
	_check("bonus attack natural 1 (+2 Surge) -> fumble", r2["outcome"]["result"] == KgCombat.RESULT_FUMBLE
		and bool(r2["is_bonus_action"]))
	_check("fumble on bonus: nobody removed, queen stays", L["pieces"].has(q) and L["pieces"].has(t2)
		and int(L["pieces"][q]["tile_y"]) == 4)
	_check("fumble -1 does not stack", int(L["pieces"][q]["next_defense_modifier"]) == -1)
	_check("fumble on bonus: turn passed", L["game_state"]["active_side"] == "rival"
		and L["game_state"]["pending_bonus_piece_id"] == "")
	_check("t1 captured by first crit", not L["pieces"].has(t1))
