#!/usr/bin/env python3
"""Route Defense WebView APK, built without the Android SDK (Google's download servers are blocked here).
Writes the binary AndroidManifest.xml and classes.dex by hand, packs the HTML game into assets/,
and signs the APK with APK Signature Scheme v2 using a key kept in keys/ (the same key every build,
so a new APK installs over the old one and keeps the save).

The app: one full-screen Activity holding a WebView that opens file:///android_asset/index.html,
with JavaScript, local storage (the save) and sound without a tap; keeps the screen on, hides the system bars,
and pauses the page when the app goes to the background.
"""
import hashlib, io, os, struct, sys, zipfile, zlib, datetime
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = 'com.routedefense.web'
LABEL = 'Route Defense'

# ---------------------------------------------------------------- binary XML (AndroidManifest.xml)
ANDROID_NS = 'http://schemas.android.com/apk/res/android'
ATTR_IDS = {  # android:attr resource ids (framework R.attr)
    'label': 0x01010001, 'name': 0x01010003, 'exported': 0x01010010, 'screenOrientation': 0x0101001e,
    'configChanges': 0x0101001f, 'minSdkVersion': 0x0101020c, 'versionCode': 0x0101021b, 'versionName': 0x0101021c,
    'targetSdkVersion': 0x01010270, 'hardwareAccelerated': 0x010102d3,
}
T_STRING, T_INT, T_BOOL = 0x03, 0x10, 0x12

def axml(tree):
    """tree: (tag, [(attrname, ns_android(bool), type, value)], [children])"""
    attr_names = sorted({a[0] for el in walk(tree) for a in el[1] if a[1]}, key=lambda n: ATTR_IDS[n])
    strings = list(attr_names)   # attribute names first, matching the resource map
    def si(s):
        if s not in strings: strings.append(s)
        return strings.index(s)
    for s in ('android', ANDROID_NS): si(s)
    for el in walk(tree):
        si(el[0])
        for a in el[1]:
            si(a[0])
            if a[2] == T_STRING: si(a[3])
    body = b''
    ns_p, ns_u = si('android'), si(ANDROID_NS)
    body += struct.pack('<HHIIIII', 0x0100, 16, 24, 1, 0xFFFFFFFF, ns_p, ns_u)
    def emit(el):
        nonlocal body
        tag, attrs, kids = el
        attrs = sorted(attrs, key=lambda a: (0, ATTR_IDS[a[0]]) if a[1] else (1, 0))
        ab = b''
        for name, isns, t, v in attrs:
            raw = si(v) if t == T_STRING else 0xFFFFFFFF
            data = si(v) if t == T_STRING else (0xFFFFFFFF if (t == T_BOOL and v) else (0 if t == T_BOOL else v & 0xFFFFFFFF))
            ab += struct.pack('<IIIHBBI', ns_u if isns else 0xFFFFFFFF, si(name), raw, 8, 0, t, data)
        hdr = struct.pack('<HHIIIII', 0x0102, 16, 36 + len(ab), 1, 0xFFFFFFFF, 0xFFFFFFFF, si(tag))
        hdr += struct.pack('<HHHHHH', 20, 20, len(attrs), 0, 0, 0)
        body += hdr + ab
        for k in kids: emit(k)
        body += struct.pack('<HHIIIII', 0x0103, 16, 24, 1, 0xFFFFFFFF, 0xFFFFFFFF, si(tag))
    emit(tree)
    body += struct.pack('<HHIIIII', 0x0101, 16, 24, 1, 0xFFFFFFFF, ns_p, ns_u)
    # string pool (UTF-16)
    offs, data = [], b''
    for s in strings:
        offs.append(len(data)); u = s.encode('utf-16-le'); data += struct.pack('<H', len(s)) + u + b'\0\0'
    while len(data) % 4: data += b'\0'
    sp_hdr = 28; strings_start = sp_hdr + 4 * len(strings)
    sp = struct.pack('<HHIIIIII', 0x0001, sp_hdr, strings_start + len(data), len(strings), 0, 0, strings_start, 0)
    sp += b''.join(struct.pack('<I', o) for o in offs) + data
    rm = struct.pack('<HHI', 0x0180, 8, 8 + 4 * len(attr_names)) + b''.join(struct.pack('<I', ATTR_IDS[n]) for n in attr_names)
    out = sp + rm + body
    return struct.pack('<HHI', 0x0003, 8, 8 + len(out)) + out

def walk(el):
    yield el
    for k in el[2]: yield from walk(k)

def manifest(vcode, vname):
    A = lambda n, t, v: (n, True, t, v)
    return axml(('manifest', [A('versionCode', T_INT, vcode), A('versionName', T_STRING, vname), ('package', False, T_STRING, PKG)], [
        ('uses-sdk', [A('minSdkVersion', T_INT, 24), A('targetSdkVersion', T_INT, 34)], []),
        ('application', [A('label', T_STRING, LABEL), A('hardwareAccelerated', T_BOOL, True)], [
            ('activity', [A('name', T_STRING, PKG + '.Main'), A('exported', T_BOOL, True), A('label', T_STRING, LABEL),
                          A('configChanges', T_INT, 0x0FB0), A('screenOrientation', T_INT, 13)], [   # 13 = fullUser: follows rotation, respects the lock
                ('intent-filter', [], [
                    ('action', [A('name', T_STRING, 'android.intent.action.MAIN')], []),
                    ('category', [A('name', T_STRING, 'android.intent.category.LAUNCHER')], []),
                ]),
            ]),
        ]),
    ]))

# ---------------------------------------------------------------- DEX (classes.dex)
def uleb(n):
    out = b''
    while True:
        b = n & 0x7f; n >>= 7
        if n: out += bytes([b | 0x80])
        else: return out + bytes([b])

def build_dex():
    MAIN = 'L' + PKG.replace('.', '/') + '/Main;'
    ACT, WV, WS, WIN, VIEW, BUN, CTX, STR = 'Landroid/app/Activity;', 'Landroid/webkit/WebView;', 'Landroid/webkit/WebSettings;', 'Landroid/view/Window;', 'Landroid/view/View;', 'Landroid/os/Bundle;', 'Landroid/content/Context;', 'Ljava/lang/String;'
    URL = 'file:///android_asset/index.html'
    # method refs: (class, name, return, (params))
    M = {
        'act_init': (ACT, '<init>', 'V', ()), 'main_init': (MAIN, '<init>', 'V', ()),
        'act_onCreate': (ACT, 'onCreate', 'V', (BUN,)), 'main_onCreate': (MAIN, 'onCreate', 'V', (BUN,)),
        'act_onPause': (ACT, 'onPause', 'V', ()), 'main_onPause': (MAIN, 'onPause', 'V', ()),
        'act_onResume': (ACT, 'onResume', 'V', ()), 'main_onResume': (MAIN, 'onResume', 'V', ()),
        'getWindow': (ACT, 'getWindow', WIN, ()), 'requestWindowFeature': (ACT, 'requestWindowFeature', 'Z', ('I',)),
        'setContentView': (ACT, 'setContentView', 'V', (VIEW,)),
        'addFlags': (WIN, 'addFlags', 'V', ('I',)), 'getDecorView': (WIN, 'getDecorView', VIEW, ()),
        'setSUV': (VIEW, 'setSystemUiVisibility', 'V', ('I',)),
        'wv_init': (WV, '<init>', 'V', (CTX,)), 'getSettings': (WV, 'getSettings', WS, ()), 'loadUrl': (WV, 'loadUrl', 'V', (STR,)),
        'wv_onPause': (WV, 'onPause', 'V', ()), 'wv_onResume': (WV, 'onResume', 'V', ()),
        'setJS': (WS, 'setJavaScriptEnabled', 'V', ('Z',)), 'setDom': (WS, 'setDomStorageEnabled', 'V', ('Z',)),
        'setFile': (WS, 'setAllowFileAccess', 'V', ('Z',)), 'setMedia': (WS, 'setMediaPlaybackRequiresUserGesture', 'V', ('Z',)),
    }
    F = {'w': (MAIN, 'w', WV)}
    shorty = lambda r, ps: ''.join('L' if t.startswith('L') or t.startswith('[') else t for t in (r,) + ps)
    strings = {URL}
    types = {MAIN, ACT, WV, WS, WIN, VIEW, BUN, CTX, STR, 'V', 'Z', 'I'}
    protos = set()
    for c, n, r, ps in M.values(): strings |= {n}; protos.add((r, ps))
    for c, n, t in F.values(): strings.add(n)
    for r, ps in protos: strings.add(shorty(r, ps))
    strings |= types
    S = sorted(strings, key=lambda s: s.encode('utf-16-be')); si = {s: i for i, s in enumerate(S)}
    T = sorted(types, key=lambda t: si[t]); ti = {t: i for i, t in enumerate(T)}
    P = sorted(protos, key=lambda p: (ti[p[0]], [ti[x] for x in p[1]])); pi = {p: i for i, p in enumerate(P)}
    FL = sorted(F.values(), key=lambda f: (ti[f[0]], si[f[1]], ti[f[2]])); fi = {k: FL.index(v) for k, v in F.items()}
    ML = sorted(set(M.values()), key=lambda m: (ti[m[0]], si[m[1]], pi[(m[2], m[3])])); mi = {k: ML.index(v) for k, v in M.items()}

    def inv(op, m, regs):
        r = list(regs) + [0] * (5 - len(regs))
        return [(len(regs) << 12) | (r[4] << 8) | op, mi[m], (r[3] << 12) | (r[2] << 8) | (r[1] << 4) | r[0]]
    V, D, S_ = 0x6e, 0x70, 0x6f
    mro = lambda a: [(a << 8) | 0x0c]
    c4 = lambda a, v: [((v & 0xf) << 12) | (a << 8) | 0x12]
    c16 = lambda a, v: [(a << 8) | 0x13, v & 0xffff]
    ret = [0x000e]
    # registers: locals v0..v3, then the ins (this = v4, then params)
    code = {}
    code['main_init'] = (1, 1, 1, inv(D, 'act_init', [0]) + ret)
    p0, p1 = 4, 5
    oc = []
    oc += inv(S_, 'act_onCreate', [p0, p1])
    oc += c4(1, 1) + inv(V, 'requestWindowFeature', [p0, 1])                      # no title bar
    oc += inv(V, 'getWindow', [p0]) + mro(0) + c16(1, 0x480) + inv(V, 'addFlags', [0, 1])   # full screen + keep the screen on
    oc += [(0 << 8) | 0x22, ti[WV]] + inv(D, 'wv_init', [0, p0])                 # new WebView(this)
    oc += [(p0 << 12) | (0 << 8) | 0x5b, fi['w']]                               # this.w = it
    oc += inv(V, 'getSettings', [0]) + mro(1) + c4(2, 1)
    oc += inv(V, 'setJS', [1, 2]) + inv(V, 'setDom', [1, 2]) + inv(V, 'setFile', [1, 2])
    oc += c4(2, 0) + inv(V, 'setMedia', [1, 2])                                 # sound without a tap first
    oc += inv(V, 'setContentView', [p0, 0])
    oc += [(1 << 8) | 0x1a, si[URL]] + inv(V, 'loadUrl', [0, 1]) + ret
    code['main_onCreate'] = (6, 2, 2, oc)
    op = inv(S_, 'act_onPause', [1]) + [(1 << 12) | (0 << 8) | 0x54, fi['w']] + inv(V, 'wv_onPause', [0]) + ret
    code['main_onPause'] = (2, 1, 1, op)
    orr = inv(S_, 'act_onResume', [2]) + [(2 << 12) | (0 << 8) | 0x54, fi['w']] + inv(V, 'wv_onResume', [0])
    orr += inv(V, 'getWindow', [2]) + mro(0) + inv(V, 'getDecorView', [0]) + mro(0) + c16(1, 0x1706) + inv(V, 'setSUV', [0, 1]) + ret   # hide the system bars (sticky immersive)
    code['main_onResume'] = (3, 1, 2, orr)

    # layout
    n_s, n_t, n_p, n_f, n_m, n_c = len(S), len(T), len(P), len(FL), len(ML), 1
    off = 0x70
    o_s = off; off += 4 * n_s
    o_t = off; off += 4 * n_t
    o_p = off; off += 12 * n_p
    o_f = off; off += 8 * n_f
    o_m = off; off += 8 * n_m
    o_c = off; off += 32 * n_c
    data_off = off
    data = bytearray(); base = data_off
    def align4():
        while (base + len(data)) % 4: data.append(0)
    # type lists
    align4(); tl_off = {}; tl_start = base + len(data); n_tl = 0
    for p in P:
        if p[1] and p[1] not in tl_off:
            align4(); tl_off[p[1]] = base + len(data); n_tl += 1
            data += struct.pack('<I', len(p[1])) + b''.join(struct.pack('<H', ti[x]) for x in p[1])
    # code items
    align4(); code_start = base + len(data); code_off = {}
    order = ['main_init', 'main_onCreate', 'main_onPause', 'main_onResume']
    for k in order:
        align4(); code_off[k] = base + len(data); regs, ins, outs, insns = code[k]
        data += struct.pack('<HHHHII', regs, ins, outs, 0, 0, len(insns)) + b''.join(struct.pack('<H', u) for u in insns)
    # string data
    sd_start = base + len(data); sd_off = []
    for s in S:
        sd_off.append(base + len(data)); data += uleb(len(s)) + s.encode('utf-8') + b'\0'
    # class data
    cd_off = base + len(data)
    direct = [('main_init', 0x10001)]
    virtual = sorted([('main_onCreate', 0x4), ('main_onPause', 0x4), ('main_onResume', 0x4)], key=lambda x: mi[x[0]])
    cd = uleb(0) + uleb(1) + uleb(len(direct)) + uleb(len(virtual))
    cd += uleb(fi['w']) + uleb(0x2)   # private WebView w
    prev = 0
    for k, acc in direct: cd += uleb(mi[k] - prev) + uleb(acc) + uleb(code_off[k]); prev = mi[k]
    prev = 0
    for k, acc in virtual: cd += uleb(mi[k] - prev) + uleb(acc) + uleb(code_off[k]); prev = mi[k]
    data += cd
    # map list
    align4(); map_off = base + len(data)
    entries = [(0x0000, 1, 0), (0x0001, n_s, o_s), (0x0002, n_t, o_t), (0x0003, n_p, o_p), (0x0004, n_f, o_f), (0x0005, n_m, o_m), (0x0006, n_c, o_c)]
    if n_tl: entries.append((0x1001, n_tl, tl_start))
    entries += [(0x2001, len(order), code_start), (0x2002, n_s, sd_start), (0x2000, 1, cd_off), (0x1000, 1, map_off)]
    entries.sort(key=lambda e: e[2])
    data += struct.pack('<I', len(entries)) + b''.join(struct.pack('<HHII', t, 0, n, o) for t, n, o in entries)

    ids = bytearray()
    ids += b''.join(struct.pack('<I', o) for o in sd_off)
    ids += b''.join(struct.pack('<I', si[t]) for t in T)
    ids += b''.join(struct.pack('<III', si[shorty(*p)], ti[p[0]], tl_off.get(p[1], 0) if p[1] else 0) for p in P)
    ids += b''.join(struct.pack('<HHI', ti[c], ti[t], si[n]) for c, n, t in FL)
    ids += b''.join(struct.pack('<HHI', ti[c], pi[(r, ps)], si[n]) for c, n, r, ps in ML)
    ids += struct.pack('<IIIIIIII', ti[MAIN], 0x1, ti[ACT], 0, 0xFFFFFFFF, 0, cd_off, 0)
    assert 0x70 + len(ids) == data_off
    size = data_off + len(data)
    hdr = bytearray(b'dex\n035\0' + b'\0' * 24)
    hdr += struct.pack('<IIIII', size, 0x70, 0x12345678, 0, 0) + struct.pack('<I', map_off)
    hdr += struct.pack('<IIIIIIIIIIII', n_s, o_s, n_t, o_t, n_p, o_p, n_f, o_f, n_m, o_m, n_c, o_c)
    hdr += struct.pack('<II', len(data), data_off)
    assert len(hdr) == 0x70
    dex = bytearray(hdr + ids + data)
    dex[12:32] = hashlib.sha1(dex[32:]).digest()
    dex[8:12] = struct.pack('<I', zlib.adler32(bytes(dex[12:])) & 0xffffffff)
    return bytes(dex)

# ---------------------------------------------------------------- signing key (kept, so updates install over the old app)
def key():
    kd = os.path.join(HERE, 'keys'); os.makedirs(kd, exist_ok=True)
    kp, cp = os.path.join(kd, 'routedefense-key.pem'), os.path.join(kd, 'routedefense-cert.der')
    if not os.path.exists(kp):
        k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Route Defense')])
        now = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        cert = x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(k.public_key()).serial_number(x509.random_serial_number()) \
            .not_valid_before(now).not_valid_after(now + datetime.timedelta(days=365 * 40)).sign(k, hashes.SHA256())
        open(kp, 'wb').write(k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        open(cp, 'wb').write(cert.public_bytes(serialization.Encoding.DER))
    k = serialization.load_pem_private_key(open(kp, 'rb').read(), None)
    return k, open(cp, 'rb').read()

# ---------------------------------------------------------------- APK Signature Scheme v2
def lp(b): return struct.pack('<I', len(b)) + b
def sign_v2(apk, k, cert):
    eocd = apk.rfind(b'PK\x05\x06'); cd_off = struct.unpack_from('<I', apk, eocd + 16)[0]
    secs = [apk[:cd_off], apk[cd_off:eocd], apk[eocd:]]
    chunks = []
    for s in secs:
        for i in range(0, len(s), 1 << 20):
            c = s[i:i + (1 << 20)]; chunks.append(hashlib.sha256(b'\xa5' + struct.pack('<I', len(c)) + c).digest())
    digest = hashlib.sha256(b'\x5a' + struct.pack('<I', len(chunks)) + b''.join(chunks)).digest()
    ALG = 0x0103   # RSASSA-PKCS1-v1_5 with SHA2-256
    signed = lp(lp(struct.pack('<I', ALG) + lp(digest))) + lp(lp(cert)) + lp(b'')
    sig = k.sign(signed, padding.PKCS1v15(), hashes.SHA256())
    pub = k.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    signer = lp(signed) + lp(lp(struct.pack('<I', ALG) + lp(sig))) + lp(pub)
    value = lp(lp(signer))
    pair = struct.pack('<I', 0x7109871a) + value
    pairs = struct.pack('<Q', len(pair)) + pair
    size = len(pairs) + 8 + 16
    block = struct.pack('<Q', size) + pairs + struct.pack('<Q', size) + b'APK Sig Block 42'
    new_eocd = bytearray(secs[2]); struct.pack_into('<I', new_eocd, 16, cd_off + len(block))
    return secs[0] + block + secs[1] + bytes(new_eocd)

# ---------------------------------------------------------------- build
def main(html, out):
    vf = os.path.join(HERE, 'keys', 'version.txt'); k, cert = key()
    v = int(open(vf).read()) + 1 if os.path.exists(vf) else 1
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('AndroidManifest.xml', manifest(v, '1.%d' % v))
        z.writestr('classes.dex', build_dex())
        z.write(html, 'assets/index.html')
    apk = sign_v2(buf.getvalue(), k, cert)
    open(out, 'wb').write(apk); open(vf, 'w').write(str(v))
    print('built', out, len(apk) // (1 << 20), 'MB, version', v)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
