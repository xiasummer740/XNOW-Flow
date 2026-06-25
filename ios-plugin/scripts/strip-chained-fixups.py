#!/usr/bin/env python3
"""
strip-chained-fixups.py — 从 Mach-O dylib 剥离链式 fixup 命令和数据
精确移除 fixup 数据区间，不移除 LINKEDIT 的其他内容
"""
import struct, sys, os

FIXUP_CMDS = {0x36, 0x35, 0x80000034, 0x80000033}
CMD_NAMES = {0x36: 'LC_DYLD_CHAINED_FIXUPS', 0x35: 'LC_DYLD_EXPORTS_TRIE',
             0x80000034: 'PRIVATE_CHAINED', 0x80000033: 'PRIVATE_EXPORTS'}
LC_SEGMENT_64 = 0x19

def strip_fixups(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', data, 20)[0]

    off = 32
    keep_cmds = []
    fixup_cmds = []
    linkedit_off = -1
    linkedit_foff = linkedit_fsize = -1

    for i in range(ncmds):
        if off + 8 > len(data): break
        cmd, csize = struct.unpack_from('<II', data, off)
        if cmd in FIXUP_CMDS:
            d_off = struct.unpack_from('<I', data, off + 8)[0]
            d_sz = struct.unpack_from('<I', data, off + 12)[0]
            fixup_cmds.append({'off': off, 'size': csize, 'data_off': d_off, 'data_sz': d_sz})
            print(f'  Found: {CMD_NAMES.get(cmd, f"0x{cmd:x}")} dataoff={d_off} datasize={d_sz}')
        else:
            keep_cmds.append({'off': off, 'size': csize})
        if cmd == LC_SEGMENT_64:
            seg = data[off+8:off+24].rstrip(b'\x00')
            if seg == b'__LINKEDIT':
                linkedit_off = off
                linkedit_foff = struct.unpack_from('<Q', data, off + 40)[0]
                linkedit_fsize = struct.unpack_from('<Q', data, off + 48)[0]
        off += csize

    if not fixup_cmds:
        print('  No chained fixup commands found - dylib is clean')
        return True

    # Calculate fixup data range
    fixup_start = min(c['data_off'] for c in fixup_cmds)
    fixup_end = max(c['data_off'] + c['data_sz'] for c in fixup_cmds)
    fixup_size = fixup_end - fixup_start
    print(f'  Fixup data range: [{fixup_start}, {fixup_end}) size={fixup_size}')

    # Calculate size of removed load commands
    removed_cmd_sz = sum(c['size'] for c in fixup_cmds)

    # Build new load command block
    new_cmds = bytearray()
    for c in keep_cmds:
        new_cmds.extend(data[c['off']:c['off']+c['size']])

    # Build new binary: header + new_cmds + data-before-fixups + data-after-fixups
    cmd_end = 32 + sizeofcmds
    before_fixups = data[cmd_end:fixup_start]
    after_fixups = data[fixup_end:]

    result = bytearray()
    result.extend(data[:32])  # header
    struct.pack_into('<I', result, 16, ncmds - len(fixup_cmds))
    struct.pack_into('<I', result, 20, sizeofcmds - removed_cmd_sz)
    result.extend(new_cmds)
    result.extend(before_fixups)
    result.extend(after_fixups)

    # Update __LINKEDIT.filesize
    new_linkedit_sz = (fixup_end - linkedit_foff) - fixup_size
    # Find LINKEDIT in new binary and update
    off2 = 32
    for i in range(ncmds - len(fixup_cmds)):
        if off2 + 8 > len(result): break
        c, cs = struct.unpack_from('<II', result, off2)
        if c == LC_SEGMENT_64:
            seg = result[off2+8:off2+24].rstrip(b'\x00')
            if seg == b'__LINKEDIT':
                struct.pack_into('<Q', result, off2+48, new_linkedit_sz)
                va = lambda x: (x+4095)&~4095
                struct.pack_into('<Q', result, off2+32, va(new_linkedit_sz))
                print(f'  __LINKEDIT: filesize {linkedit_fsize} -> {new_linkedit_sz}')
                break
        off2 += cs

    # Also update any SEGMENT_64 that covers the end (e.g., __TEXT)
    off3 = 32
    for i in range(ncmds - len(fixup_cmds)):
        if off3 + 8 > len(result): break
        c, cs = struct.unpack_from('<II', result, off3)
        if c == LC_SEGMENT_64:
            seg = result[off3+8:off3+24].rstrip(b'\x00')
            fo = struct.unpack_from('<Q', result, off3+40)[0]
            fs = struct.unpack_from('<Q', result, off3+48)[0]
            if fo + fs > fixup_start and fo <= fixup_start and seg != b'__LINKEDIT':
                new_fs = fs - fixup_size
                struct.pack_into('<Q', result, off3+48, new_fs)
                print(f'  {seg}: filesize {fs} -> {new_fs}')
        off3 += cs

    print(f'  Size: {len(data)} -> {len(result)} bytes')
    print(f'  Removed {len(fixup_cmds)} load cmds, {fixup_size} bytes fixup data')

    # Verify no fixup commands remain
    verify_nc = struct.unpack_from('<I', result, 16)[0]
    verify_off = 32
    for i in range(verify_nc):
        if verify_off + 8 > len(result): break
        c, _ = struct.unpack_from('<II', result, verify_off)
        if c in FIXUP_CMDS:
            print(f'  ERROR: {CMD_NAMES.get(c, f"0x{c:x}")} still present!')
            return False
        verify_off += struct.unpack_from('<I', result, verify_off + 4)[0]

    # Write result
    with open(path, 'wb') as f:
        f.write(result)
    print(f'  SUCCESS: chained fixups stripped')
    return True


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <dylib_path>')
        sys.exit(1)
    path = sys.argv[1]
    if not os.path.exists(path):
        print(f'Error: file not found: {path}')
        sys.exit(1)
    print(f'Processing: {path}')
    sys.exit(0 if strip_fixups(path) else 1)
