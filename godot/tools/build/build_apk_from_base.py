#!/usr/bin/env python3
"""Route Defense (Godot): build a new APK from the last one, without the full Godot project.

The base APK holds the exported game: assets/ (one file per resource) plus assets/assets.sparsepck, the index
Godot reads (GDPC v4, flags 6 = relative file base + sparse bundle: each entry is path, offset, size, md5, flags,
and the data lives in the separate assets/<path> file). This script
  * replaces / adds / removes files under assets/ (new code as text .gd, new sound, new data),
  * rewrites the sparse index to match (size + md5 per entry),
  * raises android:versionCode in the binary AndroidManifest.xml,
  * repacks with the same compression per entry (stored entries 4-byte aligned, like zipalign),
  * signs with APK Signature Scheme v2 using the Route Defense key (same key = installs over the old app).

usage: build_apk_from_base.py base.apk out.apk version_code  (the file changes are listed in CHANGES below)
"""
import hashlib, io, os, struct, sys, zipfile, zlib

sys.path.insert(0, '/mnt/user-data/uploads')
from cryptography.hazmat.primitives import serialization

RD = '/home/claude/rdgodot'
KEYS = '/home/claude/apkbuild/keys'


def changes():
    """{asset path (under assets/): bytes or None (= remove)}"""
    ch = {}
    # code: the current scripts as text (the APK had them compiled as .gdc + .gd.remap)
    for f in sorted(os.listdir(RD + '/scripts')):
        if f.endswith('.gd'):
            ch['scripts/' + f] = open(RD + '/scripts/' + f, 'rb').read()
            ch['scripts/' + f[:-3] + '.gdc'] = None
            ch['scripts/' + f + '.remap'] = None
    ch['boot.gd'] = open('/tmp/winsrc/boot.gd', 'rb').read()     # BUILT_V = the code version inside this APK
    ch['boot.gdc'] = None
    ch['boot.gd.remap'] = None
    ch['data/snd.bin'] = open('/tmp/winsrc/snd.bin', 'rb').read()  # music list with _heavy2 (Red's Monster House)
    # sound re-rendered at the right speed (e11, e96, e98) and new (m128): the imported streams + m128's import file
    for f in os.listdir(RD + '/.godot/imported'):
        stem = f.split('.mp3-')[0]
        if f.endswith('.mp3str') and (stem in ('e11', 'e96', 'e98', 'm128') or (len(stem) == 5 and stem[0] == 'w')):
            ch['.godot/imported/' + f] = open(RD + '/.godot/imported/' + f, 'rb').read()
    # import files for the new sounds (exported games keep only the [remap] part of an .import file)
    for f in os.listdir(RD + '/snd'):
        if f.endswith('.mp3.import') and (f == 'm128.mp3.import' or (f[0] == 'w' and len(f) == 16)):
            imp = open(RD + '/snd/' + f).read()
            ch['snd/' + f] = imp.split('\n[deps]')[0].rstrip().encode() + b'\n'
    # data rebuilt since: forms / moves (dex), sprites (anim), shinies, special maps (tsx)
    for d in ('dex', 'anim', 'shiny', 'tsx'): ch['data/%s.bin' % d] = open('/tmp/winsrc/%s.bin' % d, 'rb').read()
    # every imported file the base APK lacks (shiny / form sprites, new tilesets, songs, move sounds) + its .import remap
    have = {n[7:] for n in zipfile.ZipFile(sys.argv[1]).namelist() if n.startswith('assets/')}
    for f in os.listdir(RD + '/.godot/imported'):
        r = '.godot/imported/' + f
        if not f.endswith('.md5') and r not in have and r not in ch: ch[r] = open(RD + '/' + r, 'rb').read()
    for dr in ('img/mon', 'img/ts', 'snd'):
        for f in os.listdir(RD + '/' + dr):
            r = dr + '/' + f
            if f.endswith('.import') and r not in have and r not in ch:
                ch[r] = open(RD + '/' + r).read().split('\n[deps]')[0].rstrip().encode() + b'\n'
    return ch


# ---------------------------------------------------------------- sparse pck index (GDPC v4)
def read_index(d):
    assert d[:4] == b'GDPC'
    ver, vmaj, vmin, vpat, flags = struct.unpack_from('<5I', d, 4)
    file_base, dir_off = struct.unpack_from('<QQ', d, 24)
    head = d[:dir_off]
    o = dir_off
    n = struct.unpack_from('<I', d, o)[0]; o += 4
    ents = []
    for _ in range(n):
        pl = struct.unpack_from('<I', d, o)[0]; o += 4
        path = d[o:o + pl].rstrip(b'\0').decode(); o += pl
        off, size = struct.unpack_from('<QQ', d, o); o += 16
        md5 = d[o:o + 16]; o += 16
        fl = struct.unpack_from('<I', d, o)[0]; o += 4
        ents.append([path, off, size, md5, fl])
    assert o == len(d), (o, len(d))
    return head, ents


def write_index(head, ents):
    out = bytearray(head)
    out += struct.pack('<I', len(ents))
    for path, off, size, md5, fl in ents:
        p = path.encode()
        p += b'\0' * (4 - len(p) % 4)          # padded to 4 with at least one 0 byte (as Godot writes it)
        out += struct.pack('<I', len(p)) + p + struct.pack('<QQ', off, size) + md5 + struct.pack('<I', fl)
    return bytes(out)


# ---------------------------------------------------------------- binary AndroidManifest: android:versionCode
def set_version_code(axml, code):
    b = bytearray(axml)
    o = 8; resmap = []; strings = None
    while o < len(b):
        typ, hsz, csz = struct.unpack_from('<HHI', b, o)
        if typ == 0x0180:                       # resource map: string index -> attribute resource id
            resmap = list(struct.unpack_from('<%dI' % ((csz - hsz) // 4), b, o + hsz))
        elif typ == 0x0102:                     # start element
            acount = struct.unpack_from('<H', b, o + 28)[0]; astart = struct.unpack_from('<H', b, o + 24)[0]
            ao = o + 16 + astart
            for i in range(acount):
                a = ao + i * 20
                name = struct.unpack_from('<I', b, a + 4)[0]
                if name < len(resmap) and resmap[name] == 0x0101021b:     # android:versionCode
                    old = struct.unpack_from('<I', b, a + 16)[0]
                    struct.pack_into('<I', b, a + 16, code)
                    return bytes(b), old
        o += csz
    raise SystemExit('versionCode not found')


# ---------------------------------------------------------------- zip writing (zipalign-style 4-byte alignment for stored entries)
def build_zip(entries):
    """entries: list of (name, data, compress_type, date_time)"""
    out = io.BytesIO(); cd = []
    for name, data, ct, dt in entries:
        nb = name.encode()
        crc = zlib.crc32(data) & 0xffffffff
        if ct == zipfile.ZIP_DEFLATED:
            co = zlib.compressobj(9, zlib.DEFLATED, -15); comp = co.compress(data) + co.flush()
        else:
            comp = data
        dosdate = ((dt[0] - 1980) << 9) | (dt[1] << 5) | dt[2]; dostime = (dt[3] << 11) | (dt[4] << 5) | (dt[5] // 2)
        off = out.tell()
        extra = b''
        if ct == zipfile.ZIP_STORED:
            pad = (4 - (off + 30 + len(nb)) % 4) % 4
            extra = b'\0' * pad
        out.write(struct.pack('<IHHHHHIIIHH', 0x04034b50, 20, 0, ct, dostime, dosdate, crc, len(comp), len(data), len(nb), len(extra)))
        out.write(nb + extra + comp)
        cd.append(struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 20, 20, 0, ct, dostime, dosdate, crc, len(comp), len(data),
                              len(nb), 0, 0, 0, 0, 0, off) + nb)
    cdo = out.tell(); cdb = b''.join(cd)
    out.write(cdb)
    out.write(struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, len(cd), len(cd), len(cdb), cdo, 0))
    return out.getvalue()


def main(base, out, vcode):
    import importlib.util
    spec = importlib.util.spec_from_file_location('ba', '/mnt/user-data/uploads/7c7e7d8e-build_apk.py')
    ba = importlib.util.module_from_spec(spec); spec.loader.exec_module(ba)
    k = serialization.load_pem_private_key(open(KEYS + '/routedefense-key.pem', 'rb').read(), None)
    cert = open(KEYS + '/routedefense-cert.der', 'rb').read()

    z = zipfile.ZipFile(base)
    ch = changes()
    head, ents = read_index(z.read('assets/assets.sparsepck'))
    by = {e[0]: e for e in ents}
    for p, data in ch.items():
        if data is None:
            by.pop(p, None)
        else:
            md5 = hashlib.md5(data).digest()
            if p in by:
                by[p][2] = len(data); by[p][3] = md5
            else:
                by[p] = [p, 0, len(data), md5, 0]
    new_ents = [by[e[0]] for e in ents if e[0] in by] + [by[p] for p in ch if ch[p] is not None and p not in {e[0] for e in ents}]
    idx = write_index(head, new_ents)

    entries = []; seen = set()
    for i in z.infolist():
        n = i.filename
        if n.startswith('META-INF/') and n.split('/')[-1].upper().endswith(('.SF', '.RSA', '.EC', '.MF')) and n.count('/') == 1:
            continue                                    # old v1 signature files (none expected)
        if n.startswith('assets/'):
            p = n[7:]
            if p in ch:
                seen.add(p)
                if ch[p] is None:
                    continue
                entries.append((n, ch[p], i.compress_type, i.date_time)); continue
            if p == 'assets.sparsepck':
                entries.append((n, idx, i.compress_type, i.date_time)); continue
        data = z.read(n)
        if n == 'AndroidManifest.xml':
            data, old = set_version_code(data, vcode); print('versionCode', old, '->', vcode)
        entries.append((n, data, i.compress_type, i.date_time))
    for p, data in ch.items():
        if data is not None and p not in seen:
            entries.append(('assets/' + p, data, zipfile.ZIP_DEFLATED, (2026, 11, 16, 0, 0, 0)))
    apk = ba.sign_v2(build_zip(entries), k, cert)
    open(out, 'wb').write(apk)
    print('index entries', len(ents), '->', len(new_ents), ' files changed/added', sum(1 for v in ch.values() if v is not None),
          ' removed', sum(1 for v in ch.values() if v is None))
    print('built', out, round(len(apk) / (1 << 20), 1), 'MB')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]))
