class_name KgMovement
extends RefCounted
## Movement geometry. The doc says "chess-style board play" but does not
## define movement, so this uses standard chess movement shapes (no castling,
## en passant, check, or pawn promotion-on-last-rank). Reads only the ledger.
## Player pawns move toward y = 0, rival pawns toward the max y.

const KNIGHT_STEPS: Array = [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]
const ORTHOGONAL: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAGONAL: Array = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


## Pawn forward y-direction for a side.
static func pawn_forward(side: String) -> int:
	return -1 if side == KgLedger.SIDE_PLAYER else 1


## Empty tiles the piece may move to.
static func move_targets(ledger: Dictionary, piece_id: String) -> Array:
	return _scan(ledger, piece_id)["moves"]


## Enemy-occupied tiles the piece may attack.
static func attack_targets(ledger: Dictionary, piece_id: String) -> Array:
	return _scan(ledger, piece_id)["attacks"]


static func is_legal_move(ledger: Dictionary, piece_id: String, to: Vector2i) -> bool:
	return move_targets(ledger, piece_id).has(to)


static func is_legal_attack(ledger: Dictionary, piece_id: String, to: Vector2i) -> bool:
	return attack_targets(ledger, piece_id).has(to)


static func _scan(ledger: Dictionary, piece_id: String) -> Dictionary:
	var moves: Array = []
	var attacks: Array = []
	if not ledger["pieces"].has(piece_id):
		return {"moves": moves, "attacks": attacks}
	var p: Dictionary = ledger["pieces"][piece_id]
	var origin := Vector2i(int(p["tile_x"]), int(p["tile_y"]))
	var side: String = p["side"]
	match String(p["piece_type"]):
		"pawn":
			var fwd := Vector2i(0, pawn_forward(side))
			var one: Vector2i = origin + fwd
			if _is_empty(ledger, one):
				moves.append(one)
				var two: Vector2i = one + fwd
				if not bool(p["has_moved"]) and _is_empty(ledger, two):
					moves.append(two)
			for dx in [-1, 1]:
				var diag: Vector2i = origin + Vector2i(dx, fwd.y)
				if _is_enemy(ledger, diag, side):
					attacks.append(diag)
		"knight":
			_steps(ledger, origin, side, KNIGHT_STEPS, moves, attacks)
		"king":
			_steps(ledger, origin, side, ORTHOGONAL + DIAGONAL, moves, attacks)
		"rook":
			_slides(ledger, origin, side, ORTHOGONAL, moves, attacks)
		"bishop":
			_slides(ledger, origin, side, DIAGONAL, moves, attacks)
		"queen":
			_slides(ledger, origin, side, ORTHOGONAL + DIAGONAL, moves, attacks)
	return {"moves": moves, "attacks": attacks}


static func _steps(ledger: Dictionary, origin: Vector2i, side: String, steps: Array,
		moves: Array, attacks: Array) -> void:
	for s in steps:
		var t: Vector2i = origin + s
		if _is_empty(ledger, t):
			moves.append(t)
		elif _is_enemy(ledger, t, side):
			attacks.append(t)


static func _slides(ledger: Dictionary, origin: Vector2i, side: String, dirs: Array,
		moves: Array, attacks: Array) -> void:
	for d in dirs:
		var t: Vector2i = origin + d
		while KgLedger.in_bounds(ledger, t.x, t.y):
			if _is_empty(ledger, t):
				moves.append(t)
			else:
				if _is_enemy(ledger, t, side):
					attacks.append(t)
				break
			t += d


static func _is_empty(ledger: Dictionary, t: Vector2i) -> bool:
	return KgLedger.in_bounds(ledger, t.x, t.y) and KgLedger.piece_id_at(ledger, t.x, t.y) == ""


static func _is_enemy(ledger: Dictionary, t: Vector2i, side: String) -> bool:
	if not KgLedger.in_bounds(ledger, t.x, t.y):
		return false
	var other: String = KgLedger.piece_id_at(ledger, t.x, t.y)
	return other != "" and String(ledger["pieces"][other]["side"]) != side
