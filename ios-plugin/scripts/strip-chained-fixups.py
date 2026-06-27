#!/usr/bin/env python3
"""
strip-chained-fixups.py — 从 Mach-O dylib 剥离链式 fixup
策略：
1. fixup 命令 cmd→0x00（dyld 跳过）
2. fixup 数据区间填 0（dyld 回退读 __LINKEDIT 也读不到有效 opcode）
3. 不改变文件大小/布局/偏移
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
    zero_ranges = []

    for i in range(ncmds):
        if off + 8 > len(data): break
        cmd, csize = struct.unpack_from('<II', data, off)
        if cmd in FIXUP_CMDS:
            # Get fixup data range before neutralizing the command
            d_off = struct.unpack_from('<I', data, off + 8)[0]
            d_sz = struct.unpack_from('<I', data, off + 12)[0]
            zero_ranges.append((d_off, d_off + d_sz))
            print(f'  Neutralize cmd: {CMD_NAMES.get(cmd, f"0x{cmd:x}")} data=[{d_off},{d_off+d_sz})')
            struct.pack_into('<I', data, off, 0)  # cmd = 0x00
            stripped += 1
        off += csize

    if not stripped:
        print('  No chained fixup commands found')
        return True

    # Zero-fill fixup data ranges
    for zs, ze in zero_ranges:
        print(f'  Zeroed data: [{zs},{ze}) size={ze-zs}')
        data[zs:ze] = b'\x00' * (ze - zs)

    with open(path, 'wb') as f:
        f.write(data)

    print(f'  Neutralized {stripped} commands, zeroed {sum(e-s for s,e in zero_ranges)} data bytes')
    print(f'  Size: {len(data)} bytes (unchanged)')
    print(f'  SUCCESS')
    return True

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'build/xnower.dylib'
    if not os.path.exists(path): print(f'Error: {path} not found'); sys.exit(1)
    sys.exit(0 if strip_fixups(path) else 1)
