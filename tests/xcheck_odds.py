"""Independent Python cross-check of KgCombat.exact_odds (same rules, separate code)."""
from fractions import Fraction
SIDES = [4, 6, 8, 10, 12]
def resolve(A, D, a, d):
    if A >= 8 and a == 1: return "fumble"
    if A >= 8 and a == A: return "crit"
    return "attacker_win" if a > d else "defender_win"
for A in SIDES:
    for D in SIDES:
        c = {"crit": 0, "attacker_win": 0, "defender_win": 0, "fumble": 0}
        ties = 0
        for a in range(1, A + 1):
            for d in range(1, D + 1):
                r = resolve(A, D, a, d); c[r] += 1
                if r == "defender_win" and a == d: ties += 1
        cap = c["crit"] + c["attacker_win"]
        plain = sum(1 for a in range(1, A+1) for d in range(1, D+1) if a > d)
        print(f"d{A:<2} vs d{D:<2} capture={cap}/{A*D} ({cap/(A*D):.4f}) crit={c['crit']} fumble={c['fumble']} "
              f"plain_win={c['attacker_win']} def_win={c['defender_win']} ties={ties} | plain-higher-wins={plain/(A*D):.4f}")
