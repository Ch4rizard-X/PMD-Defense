#!/usr/bin/env python3
"""Sign an unsigned APK (Godot export with package/signed=false) with the Route Defense key, APK Signature Scheme v2.
Same key as the WebView and Unity builds, so the app installs over them and keeps updating."""
import sys
sys.path.insert(0, '/home/claude/apkbuild')
import build_apk as B
src, dst = sys.argv[1], sys.argv[2]
apk = open(src, 'rb').read()
assert b'APK Sig Block 42' not in apk, 'already signed'
k, cert = B.key()
open(dst, 'wb').write(B.sign_v2(apk, k, cert))
print('signed', dst)
