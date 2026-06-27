#!/usr/bin/env python3
"""
strip-chained-fixups.py — 从 Mach-O dylib 剥离链式 fixup 命令
只移除 LOAD COMMANDS，不动 __LINKEDIT 数据（保持所有偏移有效）
"""
import struct, sys, os

FIXUP_CMDS = {0x36, 0x35, 0x80000034, 0x80000033}
CMD_NAMES = {0x36: 'LC_DYLD_CHAINED_FIXUPS', 0x35: 'LC_DYLD_EXPORTS_TRIE',
             0x80000034: 'PRIVATE_CHAINED', 0x80000033: 'PRIVATE_EXPORTS'}

def strip_fixups(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', data, 20)[0]

    off = 32
    keep_cmds = bytearray()
    removed = 0

    for i in range(ncmds):
        cmd, csize = struct.unpack_from('<II', data, off)
        if cmd in FIXUP_CMDS:
            print(f'  Removing: {CMD_NAMES.get(cmd, f"0x{cmd:x}")} sz={csize}')
            removed += 1
        else:
            keep_cmds.extend(data[off:off+csize])
        off += csize

    if not removed:
        print('  No chained fixup commands found')
        return True

    new_ncmds = ncmds - removed
    new_sizeofcmds = sizeofcmds - (off - 32 - len(keep_cmds))

    result = bytearray(data[:32])  # copy header
    struct.pack_into('<I', result, 16, new_ncmds)
    struct.pack_into('<I', result, 20, new_sizeofcmds)
    result.extend(keep_cmds)          # only fixup-free commands
    result.extend(data[32+sizeofcmds:])  # ALL segment data untouched

    # Verify
    vn = struct.unpack_from('<I', result, 16)[0]
    vo = 32
    for i in range(vn):
        c, _ = struct.unpack_from('<II', result, vo)
        if c in FIXUP_CMDS:
            print(f'  ERROR: fixup cmd 0x{c:x} still present!')
            return False
        vo += struct.unpack_from('<I', result, vo+4)[0]

    with open(path, 'wb') as f:
        f.write(result)

    print(f'  Removed {removed} load commands, data untouched')
    print(f'  Size: {len(data)} -> {len(result)} bytes')
    print(f'  SUCCESS')
    return True

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'build/xnower.dylib'
    if not os.path.exists(path): print(f'Error: {path} not found'); sys.exit(1)
    sys.exit(0 if strip_fixups(path) else 1)
