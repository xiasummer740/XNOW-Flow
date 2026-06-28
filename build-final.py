#!/usr/bin/env python3
"""
build-final.py — 用 GitHub Actions 编译的新 dylib + 43.7.0 TikTok 构建最终 IPA
用法: python3 build-final.py <dylib_path> [version]
  例: python3 build-final.py build-artifacts/xnower.dylib v38
"""
import struct, zipfile, shutil, os, tempfile, sys

LC_LOAD_DYLIB = 0x0C
LC_SEGMENT_64 = 0x19

VERSION = 'v38'

def align(x, a): return (x + a - 1) & ~(a - 1)
def inject_single(data, path):
    n = struct.unpack_from('<I', data, 16)[0]
    ss = struct.unpack_from('<I', data, 20)[0]
    off = 32
    for i in range(n):
        if off+8 > len(data): break
        t, s = struct.unpack_from('<II', data, off)
        if t == LC_LOAD_DYLIB:
            no = struct.unpack_from('<I', data, off+8)[0]
            e = data.find(b'\x00', off+no, off+s)
            if e > off+no and b'xnower' in data[off+no:e]: return data, None
        off += s
    npad = path + b'\x00'
    no = 24
    cs = align(24+len(npad), 8)
    cmd = bytearray(cs)
    struct.pack_into('<II', cmd, 0, LC_LOAD_DYLIB, cs)
    struct.pack_into('<IIII', cmd, 8, no, 0, 0, 0)
    cmd[24:24+len(npad)] = npad
    new = bytearray(len(data)+cs)
    lo = -1; off2 = 32
    for i in range(n):
        if off2+8 > len(data): break
        t2 = struct.unpack_from('<I', data, off2)[0]
        if t2 == LC_SEGMENT_64:
            sn = data[off2+8:off2+24].rstrip(b'\x00')
            if sn == b'__LINKEDIT': lo = off2; break
        off2 += struct.unpack_from('<I', data, off2+4)[0]
    ip = lo if lo > 0 else 32+ss
    new[:ip] = data[:ip]; new[ip:ip+cs] = cmd; new[ip+cs:] = data[ip:]
    struct.pack_into('<I', new, 16, n+1)
    struct.pack_into('<I', new, 20, ss+cs)
    return bytes(new), None

def main():
    version = VERSION
    if len(sys.argv) < 2:
        dylib_path = 'build-artifacts/xnower.dylib'
        print(f'Usage: python3 build-final.py <dylib_path> [version]')
        print(f'Using default: {dylib_path}')
    else:
        dylib_path = sys.argv[1]
        if len(sys.argv) >= 3:
            version = sys.argv[2]

    ipa_base = 'TikTok_43.7.0_BH.ipa'
    if not os.path.exists(ipa_base):
        ipa_base = 'TikTok_42.2.0_BH.ipa'

    if not os.path.exists(dylib_path):
        print(f'ERROR: dylib not found: {dylib_path}')
        sys.exit(1)

    print(f'Base IPA: {ipa_base}')
    print(f'Dylib: {dylib_path} ({os.path.getsize(dylib_path)} bytes)')

    with zipfile.ZipFile(ipa_base) as z:
        main = z.read([n for n in z.namelist() if n.endswith('/TikTok') and 'dylib' not in n and 'framework' not in n.lower()][0])
        all_names = z.namelist()

    with open(dylib_path, 'rb') as f:
        dylib = f.read()

    # Verify dylib uses legacy fixups (no chained fixup commands)
    ncmds = struct.unpack_from('<I', dylib, 16)[0]
    off = 32
    has_chained = False
    for i in range(ncmds):
        c, s = struct.unpack_from('<II', dylib, off)
        if c in (0x36, 0x35, 0x80000033, 0x80000034):
            print(f'  WARNING: dylib has fixup cmd 0x{c:08x} at [{i}]')
            has_chained = True
        off += s
    if has_chained:
        print('  DYLIB HAS CHAINED FIXUPS - may not work on iOS 16!')

    # Inject
    main_inj, err = inject_single(main, b'@executable_path/Frameworks/xnower.dylib')
    assert err is None
    m = struct.unpack_from('<I', main_inj, 0)[0]
    assert m == 0xFEEDFACF
    print(f'Main injected: {len(main_inj)} bytes, ncmds={struct.unpack_from("<I", main_inj, 16)[0]}')

    # Build IPA
    tmpdir = tempfile.mkdtemp()
    try:
        with zipfile.ZipFile(ipa_base, 'r') as z:
            z.extractall(tmpdir)

        app = os.path.join(tmpdir, 'Payload', 'TikTok.app')
        with open(os.path.join(app, 'TikTok'), 'wb') as f:
            f.write(main_inj)

        fw = os.path.join(app, 'Frameworks')
        os.makedirs(fw, exist_ok=True)
        with open(os.path.join(fw, 'xnower.dylib'), 'wb') as f:
            f.write(dylib)

        for p in ['ios-plugin/xnow-dylib/Config.plist', 'build-artifacts/Config.plist']:
            if os.path.exists(p):
                shutil.copy2(p, os.path.join(app, 'xnower-config.plist'))
                break

        out = f'TikTok_XNOW_{version}.ipa'
        if os.path.exists(out): os.remove(out)
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=5) as z:
            for r, dirs, files in os.walk(tmpdir):
                for f in files:
                    z.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), tmpdir))

        sz = os.path.getsize(out)
        print(f'\n=== {out}: {sz/1024/1024:.1f} MB ===')
        print(f'用爱思签 TikTok_XNOW_final.ipa')

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

if __name__ == '__main__':
    main()
