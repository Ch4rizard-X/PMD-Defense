"""Minimal VCDIFF (RFC 3284) decoder with xdelta3's LZMA secondary compression and adler32 window checks."""
import sys, lzma, zlib
def code_table():
    T = [((0, 0, 0), (0, 0, 0))] * 256; T = list(T)
    T[0] = ((3, 0, 0), (0, 0, 0))                       # RUN
    for s in range(18): T[1 + s] = ((1, s, 0), (0, 0, 0))  # ADD 0..17
    i = 19
    for m in range(9):
        T[i] = ((2, 0, m), (0, 0, 0)); i += 1
        for s in range(4, 19): T[i] = ((2, s, m), (0, 0, 0)); i += 1
    for m in range(6):
        for a in range(1, 5):
            for c in range(4, 7): T[i] = ((1, a, 0), (2, c, m)); i += 1
    for m in range(6, 9):
        for a in range(1, 5): T[i] = ((1, a, 0), (2, 4, m)); i += 1
    for m in range(9): T[i] = ((2, 4, m), (1, 1, 0)); i += 1
    assert i == 256; return T
CT = code_table()
def apply(src, patch):
    p = patch; i = 0
    def vi():
        nonlocal i; r = 0
        while True:
            c = p[i]; i += 1; r = (r << 7) | (c & 0x7f)
            if c < 128: return r
    assert p[:3] == b'\xd6\xc3\xc4'; hi = p[4]; i = 5
    sec = None
    if hi & 1: sec = p[i]; i += 1
    if hi & 2: raise SystemExit('custom code table not supported')
    if hi & 4: n = vi(); i += n
    out = bytearray(); win = 0; DEC = {}   # xdelta3 keeps one LZMA stream per section kind for the whole file
    while i < len(p):
        wi = p[i]; i += 1
        if wi & 3:
            ssz = vi(); spos = vi(); seg = (src if wi & 1 else out)[spos:spos + ssz]
        else: seg = b''
        dlen = vi(); start = i; tlen = vi(); di = p[i]; i += 1
        ld, li, la = vi(), vi(), vi()
        ck = None
        if wi & 4: ck = int.from_bytes(p[i:i + 4], 'big'); i += 4
        data = p[i:i + ld]; i += ld; inst = p[i:i + li]; i += li; addr = p[i:i + la]; i += la
        def unsec(b, bit):
            if not (di & bit): return b
            j = 0; r = 0
            while True:
                c = b[j]; j += 1; r = (r << 7) | (c & 0x7f)
                if c < 128: break
            D = DEC.setdefault(bit, lzma.LZMADecompressor()); d = D.decompress(b[j:], max_length=r); assert len(d) == r, (len(d), r); return d
        data, inst, addr = unsec(data, 1), unsec(inst, 2), unsec(addr, 4)
        t = bytearray(); dp = ip = ap = 0; near = [0] * 4; ni = 0; same = [0] * (3 * 256); S = len(seg)
        def avi():
            nonlocal ap; r = 0
            while True:
                c = addr[ap]; ap += 1; r = (r << 7) | (c & 0x7f)
                if c < 128: return r
        def ivi():
            nonlocal ip; r = 0
            while True:
                c = inst[ip]; ip += 1; r = (r << 7) | (c & 0x7f)
                if c < 128: return r
        while ip < len(inst):
            op = inst[ip]; ip += 1
            for typ, size, mode in CT[op]:
                if typ == 0: continue
                if size == 0: size = ivi()
                if typ == 1: t += data[dp:dp + size]; dp += size
                elif typ == 3: b = data[dp]; dp += 1; t += bytes([b]) * size
                else:
                    here = S + len(t)
                    if mode == 0: a = avi()
                    elif mode == 1: a = here - avi()
                    elif mode < 6: a = near[mode - 2] + avi()
                    else: a = same[(mode - 6) * 256 + addr[ap]]; ap += 1
                    near[ni] = a; ni = (ni + 1) % 4; same[a % 768] = a
                    for k in range(size):     # may overlap the target being written
                        x = a + k; t.append(seg[x] if x < S else t[x - S])
        assert len(t) == tlen, (len(t), tlen)
        if ck is not None: assert zlib.adler32(bytes(t)) == ck, 'adler mismatch in window %d (wrong base ROM?)' % win
        out += t; win += 1
        if win % 50 == 0: print('window', win, len(out) >> 20, 'MB', flush=True)
    return bytes(out)
if __name__ == '__main__':
    o = apply(open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()); open(sys.argv[3], 'wb').write(o); print('done', len(o))
