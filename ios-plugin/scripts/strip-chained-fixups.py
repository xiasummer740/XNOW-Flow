#!/usr/bin/env python3
"""
strip-chained-fixups.py — 从 Mach-O dylib 剥离链式 fixup
策略：fixup 命令 cmd 类型改成 0x00（dyld 跳过未知命令）
不改变文件大小/布局/偏移
"""
import struct, sys, os

FIXUP_CMDS = {0x36, 0x35, 0x80000034, 0x80000033}
CMD_NAMES = {0x36: 'LC_DYLD_CHAINED_FIXUPS', 0x35: 'LC_DYLD_EXPORTS_TRIE',
             0x80000034: 'PRIVATE_CHAINED', 0x80000033: 'PRIVATE_EXPORTS'}

def strip_fixups(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32
    stripped = 0

    for i in range(ncmds):
        if off + 8 > len(data): break
        cmd, csize = struct.unpack_from('<II', data, off)
        if cmd in FIXUP_CMDS:
            # Zero out the cmd (set to 0x00 = unknown, dyld skips it)
            struct.pack_into('<I', data, off, 0)
            # Also zero cmd size for safety
            struct.pack_into('<I', data, off + 4, csize)
            print(f'  Neutralized: {CMD_NAMES.get(cmd, f"0x{cmd:x}")} sz={csize}')
            stripped += 1
        off += csize

    if not stripped:
        print('  No chained fixup commands found')
        return True

    with open(path, 'wb') as f:
        f.write(data)

    print(f'  Neutralized {stripped} commands, file unchanged ({len(data)} bytes)')
    print(f'  SUCCESS')
    return True

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'build/xnower.dylib'
    if not os.path.exists(path): print(f'Error: {path} not found'); sys.exit(1)
    sys.exit(0 if strip_fixups(path) else 1)
