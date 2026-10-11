class_name KgBoard
extends RefCounted
## Core board state and turn actions. All state lives in `ledger` (see
## KgLedger); this class only mutates it through the rules below and logs
## every action to the append-only action_log.
##
## Turn model: one action (move or attack) per turn. A crit grants the
## attacking piece exactly ONE free bonus action before the turn ends. A
## bonus action can never crit (no chains): a natural max on a bonus attack
## is a normal win with no push-back. A fumble on a bonus attack works as
## usual. Every move/attack log entry records "is_bonus_action".

## The live ledger Dictionary (shared, mutated in place).
var ledger: Dictionary
## Seedable RNG; its state is mirrored into game_state.rng_state after rolls.
var rng: RandomNumberGenerator


func _init(source_ledger: Dictionary) -> void:
	ledger = source_ledger
	rng = RandomNumberGenerator.new()
	var gs: Dictionary = ledger["game_state"]
	rng.seed = int(gs["rng_seed"])
	var saved_state: String = String(gs["rng_state"])
	if saved_state != "":
		rng.state = saved_state.to_int()


## Moves a piece to an empty tile using KgMovement geometry.
## Returns {"ok": bool, "reason": String}.
func move(piece_id: String, to: Vector2i) -> Dictionary:
	var reason: String = _check_actor(piece_id)
	if reason != "":
		return {"ok": false, "reason": reason}
	if not KgMovement.is_legal_move(ledger, piece_id, to):
		return {"ok": false, "reason": "illegal move"}
	var p: Dictionary = ledger["pieces"][piece_id]
	var from := Vector2i(int(p["tile_x"]), int(p["tile_y"]))
	var is_bonus: bool = _is_bonus_actor(piece_id)
	_set_tile(piece_id, to)
	KgLedger.append_action(ledger, "move", {"piece_id": piece_id, "from": _xy(from), "to": _xy(to),
		"is_bonus_action": is_bonus})
	_finish_action()
	return {"ok": true, "reason": ""}


## Attacks the enemy on `target` with random rolls from rng.
## Modifiers come from cards (e.g. Surge +2); die overrides from Promotion.
func attack(attacker_id: String, target: Vector2i, attacker_modifier: int = 0,
		defender_modifier: int = 0, attacker_die_override: int = 0, defender_die_override: int = 0) -> Dictionary:
	var check: Dictionary = _check_attack(attacker_id, target, attacker_die_override, defender_die_override)
	if not bool(check["ok"]):
		return check
	var a_nat: int = KgDice.roll(rng, int(check["attacker_sides"]))
	var d_nat: int = KgDice.roll(rng, int(check["defender_sides"]))
	ledger["game_state"]["rng_state"] = str(rng.state)
	return _apply_attack(attacker_id, target, check, a_nat, d_nat, attacker_modifier, defender_modifier)


## Same as attack() but with given natural rolls (replays, tests, add-ons).
func attack_with_rolls(attacker_id: String, target: Vector2i, attacker_natural: int,
		defender_natural: int, attacker_modifier: int = 0, defender_modifier: int = 0,
		attacker_die_override: int = 0, defender_die_override: int = 0) -> Dictionary:
	var check: Dictionary = _check_attack(attacker_id, target, attacker_die_override, defender_die_override)
	if not bool(check["ok"]):
		return check
	return _apply_attack(attacker_id, target, check, attacker_natural, defender_natural,
		attacker_modifier, defender_modifier)


## Pushes one piece one tile in `direction`. If the tile behind is occupied
## (friend or foe) or off the board, the piece is crushed and captured.
## Returns {"piece_id", "from", "to", "crushed"} and logs nothing (callers log).
func push_piece(piece_id: String, direction: Vector2i, cause: String) -> Dictionary:
	var p: Dictionary = ledger["pieces"][piece_id]
	var from := Vector2i(int(p["tile_x"]), int(p["tile_y"]))
	var to: Vector2i = from + direction
	var blocked: bool = not KgLedger.in_bounds(ledger, to.x, to.y) \
		or KgLedger.piece_id_at(ledger, to.x, to.y) != ""
	if blocked:
		_capture(piece_id, cause)
		return {"piece_id": piece_id, "from": _xy(from), "to": _xy(to), "crushed": true}
	_set_tile(piece_id, to)
	return {"piece_id": piece_id, "from": _xy(from), "to": _xy(to), "crushed": false}


## Crit push: every enemy of `attacker_side` in the 8 tiles around `center`
## is pushed one tile directly away from `center`. Destinations are judged on
## the board as it stood before the push; with radial pushes no two pushed
## pieces can target the same tile or each other's origin, so order is moot.
func crit_push(center: Vector2i, attacker_side: String) -> Array:
	var targets: Array = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var t: Vector2i = center + Vector2i(dx, dy)
			if not KgLedger.in_bounds(ledger, t.x, t.y):
				continue
			var other: String = KgLedger.piece_id_at(ledger, t.x, t.y)
			if other != "" and String(ledger["pieces"][other]["side"]) != attacker_side:
				targets.append([other, Vector2i(dx, dy)])
	var blocked: Dictionary = {}
	for entry in targets:
		var pid: String = entry[0]
		var dest: Vector2i = Vector2i(int(ledger["pieces"][pid]["tile_x"]), int(ledger["pieces"][pid]["tile_y"])) + entry[1]
		blocked[pid] = not KgLedger.in_bounds(ledger, dest.x, dest.y) \
			or KgLedger.piece_id_at(ledger, dest.x, dest.y) != ""
	var results: Array = []
	for entry in targets:
		var pid: String = entry[0]
		var p: Dictionary = ledger["pieces"][pid]
		var from := Vector2i(int(p["tile_x"]), int(p["tile_y"]))
		var to: Vector2i = from + entry[1]
		if bool(blocked[pid]):
			_capture(pid, "crushed")
			results.append({"piece_id": pid, "from": _xy(from), "to": _xy(to), "crushed": true})
		else:
			_set_tile(pid, to)
			results.append({"piece_id": pid, "from": _xy(from), "to": _xy(to), "crushed": false})
	return results


## Ends the active side's turn (also forfeits an unused crit bonus action).
func end_turn() -> void:
	var gs: Dictionary = ledger["game_state"]
	KgLedger.append_action(ledger, "end_turn", {"side": gs["active_side"],
		"forfeited_bonus_piece_id": gs["pending_bonus_piece_id"]})
	gs["pending_bonus_piece_id"] = ""
	gs["active_side"] = KgLedger.opponent_of(String(gs["active_side"]))
	gs["turn_number"] = int(gs["turn_number"]) + 1


## Pieces of a side currently on the board.
func pieces_of(side: String) -> Array:
	var out: Array = []
	for pid in ledger["pieces"]:
		if String(ledger["pieces"][pid]["side"]) == side:
			out.append(String(pid))
	return out


func _check_actor(piece_id: String) -> String:
	if not ledger["pieces"].has(piece_id):
		return "no such piece"
	var gs: Dictionary = ledger["game_state"]
	if String(ledger["pieces"][piece_id]["side"]) != String(gs["active_side"]):
		return "not this side's turn"
	var bonus: String = gs["pending_bonus_piece_id"]
	if bonus != "" and bonus != piece_id:
		return "bonus action belongs to %s" % bonus
	return ""


func _check_attack(attacker_id: String, target: Vector2i, a_override: int, d_override: int) -> Dictionary:
	var reason: String = _check_actor(attacker_id)
	if reason != "":
		return {"ok": false, "reason": reason}
	if not KgMovement.is_legal_attack(ledger, attacker_id, target):
		return {"ok": false, "reason": "illegal attack"}
	var defender_id: String = KgLedger.piece_id_at(ledger, target.x, target.y)
	var a_sides: int = a_override if a_override > 0 else KgLedger.die_sides_for(ledger, attacker_id)
	var d_sides: int = d_override if d_override > 0 else KgLedger.die_sides_for(ledger, defender_id)
	if not KgDice.is_valid_die(a_sides) or not KgDice.is_valid_die(d_sides):
		return {"ok": false, "reason": "invalid die override"}
	return {"ok": true, "reason": "", "defender_id": defender_id,
		"attacker_sides": a_sides, "defender_sides": d_sides}


func _apply_attack(attacker_id: String, target: Vector2i, check: Dictionary, a_nat: int, d_nat: int,
		a_mod: int, d_mod: int) -> Dictionary:
	var defender_id: String = check["defender_id"]
	var defender: Dictionary = ledger["pieces"][defender_id]
	var pending_penalty: int = int(defender["next_defense_modifier"])
	var is_bonus: bool = _is_bonus_actor(attacker_id)
	var outcome: Dictionary = KgCombat.resolve(int(check["attacker_sides"]), int(check["defender_sides"]),
		a_nat, d_nat, a_mod, d_mod + pending_penalty, not is_bonus)
	if outcome.is_empty():
		return {"ok": false, "reason": "invalid roll"}
	defender["next_defense_modifier"] = 0
	var attacker: Dictionary = ledger["pieces"][attacker_id]
	var from := Vector2i(int(attacker["tile_x"]), int(attacker["tile_y"]))
	var pushes: Array = []
	var result: String = outcome["result"]
	match result:
		KgCombat.RESULT_FUMBLE:
			attacker["next_defense_modifier"] = -1
		KgCombat.RESULT_DEFENDER_WIN:
			_capture(attacker_id, "lost_attack")
		KgCombat.RESULT_ATTACKER_WIN, KgCombat.RESULT_CRIT:
			_capture(defender_id, "lost_defense")
			_set_tile(attacker_id, target)
			if result == KgCombat.RESULT_CRIT:
				pushes = crit_push(target, String(attacker["side"]))
	KgLedger.append_action(ledger, "attack", {
		"attacker_id": attacker_id, "defender_id": defender_id,
		"attacker_from": _xy(from), "target": _xy(target),
		"defense_penalty_applied": pending_penalty, "outcome": outcome, "pushes": pushes,
		"is_bonus_action": is_bonus,
	})
	var gs: Dictionary = ledger["game_state"]
	if result == KgCombat.RESULT_CRIT:
		gs["pending_bonus_piece_id"] = attacker_id
		KgLedger.append_action(ledger, "bonus_action_granted", {"piece_id": attacker_id})
	else:
		_finish_action()
	return {"ok": true, "reason": "", "outcome": outcome, "pushes": pushes, "is_bonus_action": is_bonus}


## True if this piece is taking the pending crit bonus action.
func _is_bonus_actor(piece_id: String) -> bool:
	var bonus: String = ledger["game_state"]["pending_bonus_piece_id"]
	return bonus != "" and bonus == piece_id


## Normal end of an action: a used bonus is consumed, then the turn passes.
func _finish_action() -> void:
	ledger["game_state"]["pending_bonus_piece_id"] = ""
	end_turn()


func _set_tile(piece_id: String, to: Vector2i) -> void:
	var p: Dictionary = ledger["pieces"][piece_id]
	p["tile_x"] = to.x
	p["tile_y"] = to.y
	p["has_moved"] = true


func _capture(piece_id: String, cause: String) -> void:
	var p: Dictionary = ledger["pieces"][piece_id].duplicate(true)
	p["captured_turn"] = int(ledger["game_state"]["turn_number"])
	p["capture_cause"] = cause
	ledger["captured_pieces"].append(p)
	ledger["pieces"].erase(piece_id)


static func _xy(v: Vector2i) -> Array:
	return [v.x, v.y]
