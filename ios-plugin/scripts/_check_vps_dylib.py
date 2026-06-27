#!/usr/bin/env python3
"""Check and convert the VPS-built dylib"""
import struct, os

path = r'F:\summer\vs-code\XNOW-Flow\build-artifacts-ci\xnower-lld.dylib'
with open(path, 'rb') as f:
    data = bytearray(f.read())

ncmds = struct.unpack_from('<I', data, 16)[0]
print(f'ncmds={ncmds}, size={len(data)}')

off = 32
for i in range(ncmds):
    c, cs = struct.unpack_from('<II', data, off)
    if c == 0x80000022:
        vals = struct.unpack_from('<IIIIIIII', data, off+8)
        nz = {k:v for k,v in zip(['rebase_off','rebase_sz','bind_off','bind_sz','lazy_off','lazy_sz','export_off','export_sz'], vals) if v != 0}
        print(f'  [{i:2d}] PRIV_DYLD_INFO (0x80000022) cmdsize={cs}')
        print(f'    vals: rebase=0x{vals[0]:x}/{vals[1]} bind=0x{vals[2]:x}/{vals[3]} lazy=0x{vals[4]:x}/{vals[5]} export=0x{vals[6]:x}/{vals[7]}')
        if nz:
            print(f'    Non-zero: {nz}')
        # Convert to standard
        struct.pack_into('<I', data, off, 0x22)
        print('    -> Converted to LC_DYLD_INFO_ONLY!')
    elif c == 0x22:
        vals = struct.unpack_from('<IIIIIIII', data, off+8)
        print(f'  [{i:2d}] LC_DYLD_INFO_ONLY: rebase=0x{vals[0]:x}/{vals[1]} bind=0x{vals[2]:x}/{vals[3]}')
    elif c == 0x2E:
        segname = data[off+8:off+24].rstrip(b'\x00').decode()
        if segname in ['__LINKEDIT', '__TEXT']:
            fo = struct.unpack_from('<Q', data, off+40)[0]
            fs = struct.unpack_from('<Q', data, off+48)[0]
            print(f'  [{i:2d}] LC_SEGMENT_64: {segname} off=0x{fo:x} sz=0x{fs:x}')
    elif c in (0x0B, 0x0C):
        try:
            s = data[off+24:off+cs].rstrip(b'\x00').decode()
            print(f'  [{i:2d}] {"LC_ID_DYLIB" if c==0x0C else "LC_LOAD_DYLIB"}: {s[:60]}')
        except:
            pass
    elif c == 0x1B:
        ver = struct.unpack_from('<I', data, off+8)[0]
        print(f'  [{i:2d}] LC_VERSION_MIN_IPHONEOS: {ver>>16}.{ver>>8&0xff}.{ver&0xff}')
    off += cs

# Save converted
outpath = path.replace('.dylib', '-converted.dylib')
with open(outpath, 'wb') as f:
    f.write(data)
print(f'\nSaved converted: {outpath}')
print(f'Size: {len(data)} bytes')
