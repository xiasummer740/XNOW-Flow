#!/usr/bin/env python3
"""
strip-chained-fixups.py
- 移除 fixup 命令, 添加空 LC_DYLD_INFO_ONLY, 填 0 fixup 数据
- 自动调整段偏移（delta 很小）
"""
import struct, sys, os

FIXUP_CMDS = {0x36, 0x35, 0x80000034, 0x80000033}
CMD_NAMES = {0x36: 'LC_DYLD_CHAINED_FIXUPS', 0x35: 'LC_DYLD_EXPORTS_TRIE',
             0x80000034: 'PRIVATE_CHAINED', 0x80000033: 'PRIVATE_EXPORTS'}
LC_DYLD_INFO_ONLY = 0x22
LC_SEGMENT_64 = 0x19

def strip_fixups(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', data, 20)[0]

    off = 32
    keep_cmds = bytearray()
    fixup_ranges = []
    removed = 0

    for i in range(ncmds):
        if off + 8 > len(data): break
        cmd, csize = struct.unpack_from('<II', data, off)
        if cmd in FIXUP_CMDS:
            d_off = struct.unpack_from('<I', data, off + 8)[0]
            d_sz = struct.unpack_from('<I', data, off + 12)[0]
            fixup_ranges.append((d_off, d_off + d_sz))
            print(f'  Remove: {CMD_NAMES.get(cmd, f"0x{cmd:x}")}')
            removed += 1
        else:
            keep_cmds.extend(data[off:off+csize])
        off += csize

    if not removed: print('  No fixup cmds'); return True

    # Add LC_DYLD_INFO_ONLY
    di = bytearray(40)
    struct.pack_into('<II', di, 0, LC_DYLD_INFO_ONLY, 40)
    keep_cmds.extend(di)

    old_cmd_end = 32 + sizeofcmds
    new_sizeofcmds = len(keep_cmds)
    delta = new_sizeofcmds - sizeofcmds  # positive = load cmds grew
    new_ncmds = ncmds - removed + 1

    result = bytearray(data[:32])  # header
    struct.pack_into('<I', result, 16, new_ncmds)
    struct.pack_into('<I', result, 20, new_sizeofcmds)
    result.extend(keep_cmds)
    result.extend(data[old_cmd_end:])  # segment data shifted

    # Update all LC_SEGMENT_64 fileoff values
    off2 = 32
    for i in range(new_ncmds):
        if off2 + 8 > len(result): break
        c, cs = struct.unpack_from('<II', result, off2)
        if c == LC_SEGMENT_64:
            seg = result[off2+8:off2+24].rstrip(b'\x00').decode()
            fo = struct.unpack_from('<Q', result, off2 + 40)[0]
            fs = struct.unpack_from('<Q', result, off2 + 48)[0]
            # __PAGEZERO often has fileoff=0, don't adjust
            if seg == '__PAGEZERO':
                pass
            else:
                new_fo = fo + delta
                struct.pack_into('<Q', result, off2 + 40, new_fo)
                print(f'  Adjusted {seg}: fileoff {fo} -> {new_fo}')
        off2 += cs

    # Zero-fill fixup data
    for zs, ze in fixup_ranges:
        result[zs:ze] = b'\x00' * (ze - zs)
        print(f'  Zero data: [{zs},{ze})')

    # Verify
    vn = struct.unpack_from('<I', result, 16)[0]
    vo = 32
    for i in range(vn):
        c, _ = struct.unpack_from('<II', result, vo)
        if c in FIXUP_CMDS: print(f'  ERROR: fixup cmd 0x{c:x} present!'); return False
        if c == LC_DYLD_INFO_ONLY: print(f'  Verified: LC_DYLD_INFO_ONLY at [{i}]')
        vo += struct.unpack_from('<I', result, vo + 4)[0]

    with open(path, 'wb') as f: f.write(result)
    print(f'  Size: {len(data)} -> {len(result)} ({delta} B delta)')
    print(f'  SUCCESS')
    return True

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'build/xnower.dylib'
    if not os.path.exists(path): print(f'Error: {path} not found'); sys.exit(1)
    sys.exit(0 if strip_fixups(path) else 1)
