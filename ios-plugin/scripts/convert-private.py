#!/usr/bin/env python3
"""
convert-private.py — Convert private fixup cmds to standard ones.
Changes 0x80000034 → 0x36 (LC_DYLD_CHAINED_FIXUPS) and
         0x80000033 → 0x35 (LC_DYLD_EXPORTS_TRIE).
These have identical structures (cmd+cmdsize+dataoff+datasize = 16 bytes).
iOS 16.7 dyld may handle standard chained fixups but not private ones.
"""
import struct, sys, os

def convert(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32
    changes = 0

    for i in range(ncmds):
        c, cs = struct.unpack_from('<II', data, off)
        new_cmd = None
        if c == 0x80000034:
            new_cmd = 0x36  # LC_DYLD_CHAINED_FIXUPS
        elif c == 0x80000033:
            new_cmd = 0x35  # LC_DYLD_EXPORTS_TRIE
        elif c == 0x22:  # LC_DYLD_INFO_ONLY (can be removed later if needed)
            pass

        if new_cmd:
            struct.pack_into('<I', data, off, new_cmd)
            name = {0x36:'LC_DYLD_CHAINED_FIXUPS', 0x35:'LC_DYLD_EXPORTS_TRIE'}[new_cmd]
            d_off = struct.unpack_from('<I', data, off+8)[0]
            d_sz = struct.unpack_from('<I', data, off+12)[0]
            print(f'  [{i}] 0x{c:08x} -> {name} (data=0x{d_off:x} size=0x{d_sz:x})')
            changes += 1

    if changes == 0:
        print('No private fixup commands found')
        return False

    output = path + '.fixed'
    with open(output, 'wb') as f:
        f.write(data)

    print(f'\nConverted {changes} commands')
    print(f'Output: {output}')
    print(f'Size: {len(data)} bytes')
    print()
    print('Verify with: otool -l', output, '| grep -E "DYLD_CHAINED|EXPORTS_TRIE"')
    return True

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'build/xnower.dylib'
    if not os.path.exists(path):
        print(f'Error: {path} not found')
        sys.exit(1)
    sys.exit(0 if convert(path) else 1)
