#!/usr/bin/env python3
"""
convert-private-cmds.py — 将 ld-prime 产生的私有 Mach-O 命令转为标准格式
用法: python3 convert-private-cmds.py <dylib_path>

转换:
  0x80000022 (PRIV_DYLD_INFO)    → 0x22 (LC_DYLD_INFO_ONLY)
  0x80000033 (PRIV_EXPORTS)      → 0x35 (LC_EXPORTS_TRIE)
  0x80000034 (PRIV_CHAINED)      → 0x36 (LC_DYLD_CHAINED_FIXUPS)
"""
import struct, sys

MAP = {
    0x80000022: (0x22, 'PRIV_DYLD_INFO', 'LC_DYLD_INFO_ONLY'),
    0x80000033: (0x35, 'PRIV_EXPORTS', 'LC_EXPORTS_TRIE'),
    0x80000034: (0x36, 'PRIV_CHAINED', 'LC_DYLD_CHAINED_FIXUPS'),
}

def convert(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32
    converted = 0

    for i in range(ncmds):
        c, cs = struct.unpack_from('<II', data, off)
        if c in MAP:
            new_cmd, old_name, new_name = MAP[c]
            struct.pack_into('<I', data, off, new_cmd)
            print(f'  [{i}] {old_name} -> {new_name}')
            converted += 1
        off += cs

    if converted > 0:
        with open(path, 'wb') as f:
            f.write(data)
        print(f'Converted {converted} command(s)')
    else:
        print('No private commands found')

    return converted

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python3 convert-private-cmds.py <dylib_path>')
        sys.exit(1)
    convert(sys.argv[1])
