extends Node
# Route Defense - random maps from PMD tilesets (ported from the HTML version's map.js)
# Autoload "MG". Same random numbers as the HTML version, so a seed makes the same map in both.

const TZ := 24
const NB := [[0, 1], [1, 1], [1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1]]   # S SE E NE N NW W SW (PMD bit order)

# mulberry32, bit for bit as the HTML version (32-bit maths done in 64-bit ints)
class Rng:
	var a: int
	func _init(seed: int) -> void: a = seed & 0xFFFFFFFF
	static func imul(x: int, y: int) -> int: return (x * y) & 0xFFFFFFFF
	func next() -> float:
		a = (a + 0x6D2B79F5) & 0xFFFFFFFF
		var t := imul(a ^ (a >> 15), 1 | a)
		t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

static func _k(c) -> String: return "%d,%d" % [c[0], c[1]]

# path through a grid of 5x5-tile cells, left edge to right edge, never touching itself
func cell_path(cw: int, ch: int, R: Rng, min_f: float, max_f: float) -> Variant:
	var N := 28
	var minL: int = max(cw + 1, int(floor(N * min_f))); var maxL: int = max(cw + 3, int(floor(N * max_f)))   # path length as on a 7x4 map, whatever the screen shape
	var best = null
	for tries in 4000:
		var p := [[0, int(floor(R.next() * ch))]]; var seen := {_k(p[0]): 1}
		while true:
			var x: int = p[-1][0]; var y: int = p[-1][1]
			if x == cw - 1 and p.size() >= minL: break
			var opts := []
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var a: int = x + d[0]; var b: int = y + d[1]
				if a >= 0 and b >= 0 and a < cw and b < ch and not seen.has("%d,%d" % [a, b]) and (a < cw - 1 or p.size() + 1 >= minL - 1): opts.append([a, b])
			if opts.is_empty(): break
			# a little bias toward vertical moves keeps paths winding
			var w := []; var tot := 0.0
			for o in opts:
				var v: float = (1.6 if o[1] != y else 1.0) * (1.1 if o[0] > x else (0.8 if o[0] < x else 1.0))
				w.append(v); tot += v
			var r := R.next() * tot; var k := 0
			r -= w[k]
			while r > 0: k += 1; r -= w[k]
			p.append(opts[k]); seen[_k(opts[k])] = 1
			if p.size() > maxL: break
		var ex: int = p[-1][0]
		if ex == cw - 1 and p.size() >= minL and p.size() <= maxL:
			if best == null or p.size() > best.size(): best = p
			if R.next() < 0.35: break
	return best

# random walk through free cells from start to any cell satisfying goal, avoiding used cells
func cell_route(cw: int, ch: int, R: Rng, start: Array, goal: Callable, used: Dictionary, min_len: int, max_len: int) -> Variant:
	for tries in 600:
		var p := [start]; var seen := {_k(start): 1}
		while p.size() <= max_len:
			var x: int = p[-1][0]; var y: int = p[-1][1]
			var nb := []
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var a: int = x + d[0]; var b: int = y + d[1]
				if a >= 0 and b >= 0 and a < cw and b < ch and not seen.has("%d,%d" % [a, b]): nb.append([a, b])
			var fin := []
			for c in nb: if goal.call(c) and p.size() >= min_len: fin.append(c)
			if fin.size(): p.append(fin[0]); return p
			var free := []
			for c in nb: if not used.has(_k(c)): free.append(c)
			if free.is_empty(): break
			var c2 = free[int(floor(R.next() * free.size()))]; p.append(c2); seen[_k(c2)] = 1
	return null

# aspect = long side / short side of the play area: the map is made in that shape so it fills it.
# the path is laid out in 5-tile blocks; map_extra adds plain columns (same tileset) at the exit end so the shape matches to one tile
func map_cols(aspect: float) -> int: return clampi(int(floor((aspect * 21 - 2) / 5.0)), 5, 10)
func map_extra(aspect: float, cw: int) -> int: return clampi(int(round(aspect * 21)) - (cw * 5 + 2), 0, 6)
static func _idx(cp: Array, c) -> int:
	for j in cp.size(): if cp[j][0] == c[0] and cp[j][1] == c[1]: return j
	return -1

func gen_map(set_idx: int, portrait: bool, seed: int, kind = null, aspect := 1.76, tier := 1) -> Dictionary:
	var grp: int = C.map_group(set_idx); var md := grp / 3.0                                  # later maps are harder by nature
	var hard := clampf((tier - 4) / 16.0, 0, 1) * 0.6 + md * 0.4                             # tier gives up to 60%, the map's group the other 40%
	var eff_tier := tier * 0.75 + grp * 4; var len_k := 1 - 0.3 * md                         # third entrances: late tiers on later maps; paths up to 30% shorter
	var R := Rng.new(seed); var S: Dictionary = C.DB.ts[set_idx]
	var CS := 5; var ch := 4; var cw := map_cols(aspect); var W := cw * CS + 2 + map_extra(aspect, cw); var H := 21; var ox := 1; var oy := 0   # the path's last straight runs on to the far edge
	var t := []
	for y in H:
		var row := PackedInt32Array(); row.resize(W); t.append(row)
	if kind == null:
		var p_plain := 0.45 * (1 - hard); var p_three := 0.4 * clampf((eff_tier - 12) / 15.0, 0, 1) if eff_tier >= 13 else 0.0
		var rest := (1 - p_plain - p_three) / 2; var r := R.next()
		kind = "plain" if r < p_plain else ("split" if r < p_plain + rest else ("two" if r < p_plain + 2 * rest else "three"))
	var cp: Array = cell_path(cw, ch, R, 0.55 * len_k, 0.85 * len_k) if kind == "plain" else cell_path(cw, ch, R, 0.42 * len_k, 0.62 * len_k)
	var used := {}
	for c in cp: used[_k(c)] = 1
	var ctr := func(c) -> Array: return [ox + c[0] * CS + 2, oy + c[1] * CS + 3]               # corner point shared by the 2x2 path block
	var carve := func(ax: int, ay: int, bx: int, by: int) -> void:                             # 2-wide corridor between two centre points
		for y in range(min(ay, by) - 1, max(ay, by) + 1):
			for x in range(min(ax, bx) - 1, max(ax, bx) + 1):
				if y >= 0 and y < H and x >= 0 and x < W: t[y][x] = 1
	var carve_cells := func(cells: Array) -> void:
		for i in range(1, cells.size()):
			var a = ctr.call(cells[i - 1]); var b = ctr.call(cells[i]); carve.call(a[0], a[1], b[0], b[1])
	var first = ctr.call(cp[0]); var last = ctr.call(cp[-1])
	carve.call(0, first[1], first[0], first[1]); carve_cells.call(cp); carve.call(last[0], last[1], W, last[1])
	var px := func(cells: Array) -> Array:
		var o := []
		for c in cells:
			var q = ctr.call(c); o.append(Vector2(q[0] * TZ, q[1] * TZ))
		return o
	var main_line: Array = [Vector2(-TZ * 1.5, first[1] * TZ)] + px.call(cp) + [Vector2(W * TZ + TZ * 1.5, last[1] * TZ)]
	var lines := [main_line]
	if kind == "split":
		var ok := false; var tr := 0
		while tr < 40 and not ok:
			tr += 1
			var i := int(floor(R.next() * (cp.size() - 4)))
			var br = cell_route(cw, ch, R, cp[i], func(c): return _idx(cp, c) > i + 2, used, 3, 9)
			if br == null: continue
			var j := _idx(cp, br[-1])
			carve_cells.call(br)
			for c in br.slice(1, br.size() - 1): used[_k(c)] = 1
			lines.append([main_line[0]] + px.call(cp.slice(0, i)) + px.call(br) + px.call(cp.slice(j + 1)) + [main_line[-1]])
			ok = true
		if not ok: kind = "plain"
	elif kind == "two" or kind == "three":
		# extra entrances from the top or bottom edge that merge into the main path (a third one comes from the other edge)
		var sides := [R.next() < 0.5]
		if kind == "three": sides.append(not sides[0])
		var made := 0
		for top in sides:
			var ok := false; var tr := 0
			while tr < 40 and not ok:
				tr += 1
				var sy := 0 if top else ch - 1; var sx := 1 + int(floor(R.next() * (cw - 2))); var st := [sx, sy]
				if used.has(_k(st)): continue
				var br = cell_route(cw, ch, R, st, func(c): return _idx(cp, c) >= 3 and _idx(cp, c) < cp.size() - 2, used, 2, 10)
				if br == null: continue
				var j := _idx(cp, br[-1])
				var e = ctr.call(st); carve.call(e[0], e[1], e[0], 0 if top else H); carve_cells.call(br)
				for c in br.slice(0, br.size() - 1): used[_k(c)] = 1
				var edge := Vector2(e[0] * TZ, -TZ * 1.5 if top else H * TZ + TZ * 1.5)
				lines.append([edge] + px.call(br) + px.call(cp.slice(j + 1)) + [main_line[-1]])
				ok = true; made += 1
		kind = "plain" if made == 0 else ("two" if made == 1 else "three")
	# ponds (water, or lava in volcanic settings), kept off the path
	var near_path := func(x: int, y: int, d: int) -> bool:
		for j in range(-d, d + 1):
			for i in range(-d, d + 1):
				var a := x + i; var b := y + j
				if a >= 0 and b >= 0 and a < W and b < H and t[b][a] == 1: return true
		return false
	var np := 1 + int(floor(R.next() * 3)) + int(round(hard * 5))   # more ponds / lava pools on harder fights: fewer good spots
	for k in np:
		for tr in 60:
			var sx := 1 + int(floor(R.next() * (W - 3))); var sy := 1 + int(floor(R.next() * (H - 3)))
			if near_path.call(sx, sy, 2) or near_path.call(sx + 1, sy + 1, 2): continue
			var blob := [[sx, sy], [sx + 1, sy], [sx, sy + 1], [sx + 1, sy + 1]]
			var size := 6 + int(floor(R.next() * 10)) + int(round(hard * 14 * R.next()))
			var g := 0
			while g < 200 and blob.size() < size:
				g += 1
				var bc = blob[int(floor(R.next() * blob.size()))]; var dd = NB[[0, 2, 4, 6][int(floor(R.next() * 4))]]
				var a: int = bc[0] + dd[0]; var b: int = bc[1] + dd[1]
				if a < 1 or b < 1 or a >= W - 1 or b >= H - 1 or near_path.call(a, b, 1): continue
				var dup := false
				for q in blob: if q[0] == a and q[1] == b: dup = true; break
				if dup: continue
				blob.append([a, b])
			for q in blob: t[q[1]][q[0]] = 2
			break
	for pss in 3:   # PMD's liquid tiles need 2x2 bodies to look right
		for y in H:
			for x in W:
				if t[y][x] != 2: continue
				var ok := false
				for o in [[0, 0], [-1, 0], [0, -1], [-1, -1]]:
					var all := true
					for q in [[0, 0], [1, 0], [0, 1], [1, 1]]:
						var a: int = x + o[0] + q[0]; var b: int = y + o[1] + q[1]
						if not (a >= 0 and b >= 0 and a < W and b < H and t[b][a] == 2): all = false; break
					if all: ok = true
				if not ok: t[y][x] = 0
	var M := {"set": set_idx, "seed": seed, "W": W, "H": H, "t": t, "lines": lines, "kind": kind, "liq": S.get("liq", 0)}
	if portrait: M = transpose(M)
	M.routes = []
	for l in M.lines:
		var r := mk_route(l); r.air = mk_route(air_line(l)); M.routes.append(r)   # flyers cut the corners
	M.line = M.lines[0]; M.len = M.routes[0].len; M.seg = M.routes[0].seg
	M.vr = []
	for y in M.H:
		var row := PackedInt32Array(); row.resize(M.W)
		for x in M.W: row[x] = int(floor(R.next() * 3))
		M.vr.append(row)
	M.tex = render_map(M)
	return M

func mk_route(line: Array) -> Dictionary:
	var seg := []; var l := 0.0
	for i in range(1, line.size()):
		var s: float = line[i].distance_to(line[i - 1]); seg.append(s); l += s
	return {"line": line, "seg": seg, "len": l}
func air_line(line: Array) -> Array:
	var out := [line[0]]
	var i := 2
	while i < line.size() - 1: out.append(line[i]); i += 2
	out.append(line[-1])
	return out
func transpose(M: Dictionary) -> Dictionary:
	var t := []
	for y in M.W:
		var row := PackedInt32Array(); row.resize(M.H)
		for x in M.H: row[x] = M.t[x][y]
		t.append(row)
	var lines := []
	for l in M.lines:
		var nl := []
		for v in l: nl.append(Vector2(v.y, v.x))
		lines.append(nl)
	var o := M.duplicate(); o.W = M.H; o.H = M.W; o.t = t; o.lines = lines
	return o
func tile_at(M: Dictionary, x: int, y: int) -> int: return M.t[clampi(y, 0, M.H - 1)][clampi(x, 0, M.W - 1)]

var _ts_img := {}
func render_map(M: Dictionary) -> ImageTexture:
	var S: Dictionary = C.DB.ts[M.set]; var cols: int = S.get("cols", 10)
	if not _ts_img.has(S.ts):
		var tx: Texture2D = C.tex("img/ts/%s.png" % S.ts)
		var im: Image = tx.get_image() if tx else null
		if im and im.is_compressed(): im.decompress()
		if im: im.convert(Image.FORMAT_RGBA8)
		_ts_img[S.ts] = im
	var src: Image = _ts_img[S.ts]
	var out := Image.create(M.W * TZ, M.H * TZ, false, Image.FORMAT_RGBA8)
	if src == null: return ImageTexture.create_from_image(out)
	var rules: Array = S.rules
	for y in M.H:
		for x in M.W:
			var v: int = M.t[y][x]; var mask := 0
			for i in 8:
				var n := tile_at(M, x + NB[i][0], y + NB[i][1])
				if (n == 0 if v == 0 else (n != 0 if v == 1 else n == v)): mask |= 1 << i
			var key := mask + (512 if v == 1 else (256 if v == 2 else 0))
			var ri: int = M.vr[y][x] + key * 3
			if ri >= rules.size(): continue
			var b = rules[ri]
			if b == null or b < 0: continue
			out.blit_rect(src, Rect2i((b % cols) * TZ, (b / cols) * TZ, TZ, TZ), Vector2i(x * TZ, y * TZ))
	return ImageTexture.create_from_image(out)

# position + facing along a route at distance d
func path_at(M, d: float, route = null) -> Array:
	var r: Dictionary = route if route != null else M.routes[0]
	var i := 0
	while i < r.seg.size() - 1 and d > r.seg[i]: d -= r.seg[i]; i += 1
	var a: Vector2 = r.line[i]; var b: Vector2 = r.line[i + 1]
	var f: float = clampf(d / r.seg[i], 0, 1) if r.seg[i] else 0.0
	return [a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, atan2(b.y - a.y, b.x - a.x)]
func nearest_d(r: Dictionary, x: float, y: float) -> float:
	var best := 0.0; var bd := 1e9; var d := 0.0
	while d <= r.len:
		var p := path_at(null, d, r); var k := Vector2(p[0], p[1]).distance_to(Vector2(x, y))
		if k < bd: bd = k; best = d
		d += 6
	return best
func dist_to_path(M: Dictionary, x: float, y: float) -> float:
	var best := 1e9
	for line in M.lines:
		for i in range(1, line.size()):
			var a: Vector2 = line[i - 1]; var b: Vector2 = line[i]; var dv := b - a; var l := dv.length_squared()
			var f := clampf(((x - a.x) * dv.x + (y - a.y) * dv.y) / l, 0, 1) if l else 0.0
			best = min(best, Vector2(x - a.x - dv.x * f, y - a.y - dv.y * f).length())
	return best
