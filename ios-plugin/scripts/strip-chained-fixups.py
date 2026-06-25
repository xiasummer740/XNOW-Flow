#!/usr/bin/env python3
"""
strip-chained-fixups.py — 从 Mach-O dylib 剥离链式 fixup 命令和数据
使 dylib 使用纯 SYMTAB/DYSYMTAB 绑定（iOS 16 兼容）
"""
import struct, sys, os

LC_DYLD_CHAINED_FIXUPS = 0x36
LC_DYLD_EXPORTS_TRIE = 0x35
LC_PRIVATE_CHAINED = 0x80000034  # Private chained fixup (Xcode 15 variant)
LC_PRIVATE_EXPORTS = 0x80000033  # Private export trie (Xcode 15 variant)
LC_SEGMENT_64 = 0x19

FIXUP_CMDS = {LC_DYLD_CHAINED_FIXUPS, LC_DYLD_EXPORTS_TRIE,
              LC_PRIVATE_CHAINED, LC_PRIVATE_EXPORTS}
CMD_NAMES = {LC_DYLD_CHAINED_FIXUPS: 'LC_DYLD_CHAINED_FIXUPS',
             LC_DYLD_EXPORTS_TRIE: 'LC_DYLD_EXPORTS_TRIE',
             LC_PRIVATE_CHAINED: 'PRIVATE_CHAINED(0x80000034)',
             LC_PRIVATE_EXPORTS: 'PRIVATE_EXPORTS(0x80000033)'}

def strip_fixups(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', data, 20)[0]

    off = 32
    cmds_to_keep = []
    fixup_cmds = []  # (offset, size, dataoff, datasize)
    linkedit_off = -1
    linkedit_foff = linkedit_fsize = -1

    for i in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, csize = struct.unpack_from('<II', data, off)
        cmd_name = CMD_NAMES.get(cmd, f'0x{cmd:08x}')

        if cmd in FIXUP_CMDS:
            dataoff = struct.unpack_from('<I', data, off + 8)[0]
            datasize = struct.unpack_from('<I', data, off + 12)[0]
            fixup_cmds.append((off, csize, dataoff, datasize))
            print(f'  Found: {cmd_name}: dataoff={dataoff}, datasize={datasize}')
        else:
            cmds_to_keep.append((off, csize))
            # Print first few non-fixup commands for debugging
            if i < 8:
                print(f'  Keep [{i:2}] {cmd_name} sz={csize}')

        if cmd == LC_SEGMENT_64:
            segname = data[off+8:off+24].rstrip(b'\x00')
            if segname == b'__LINKEDIT':
                linkedit_off = off
                linkedit_foff = struct.unpack_from('<Q', data, off + 40)[0]
                linkedit_fsize = struct.unpack_from('<Q', data, off + 48)[0]

        off += csize

    if not fixup_cmds:
        print('  No chained fixup commands found - dylib is already clean')
        return True

    # Find the range of fixup data
    fixup_data_start = min(c[2] for c in fixup_cmds)
    fixup_data_end = max(c[2] + c[3] for c in fixup_cmds)
    fixup_data_size = fixup_data_end - fixup_data_start

    # Calculate new header values
    removed_cmd_size = sum(c[1] for c in fixup_cmds)
    new_ncmds = ncmds - len(fixup_cmds)
    new_sizeofcmds = sizeofcmds - removed_cmd_size

    # Build new load commands
    new_cmds = bytearray()
    for cmd_off, cmd_size in cmds_to_keep:
        new_cmds.extend(data[cmd_off:cmd_off+cmd_size])

    # Build new binary: header + new_cmds + segment data up to fixup_data_start
    result = bytearray()
    result.extend(data[:32])  # full header
    struct.pack_into('<I', result, 16, new_ncmds)
    struct.pack_into('<I', result, 20, new_sizeofcmds)
    result.extend(new_cmds)

    # Copy segment data (everything except the fixup data range at the end)
    cmd_end = 32 + sizeofcmds
    result.extend(data[cmd_end:fixup_data_start])

    # Update __LINKEDIT filesize
    new_linkedit_fsize = fixup_data_start - linkedit_foff
    # Find __LINKEDIT in the new load commands and update
    off2 = 32
    for i in range(new_ncmds):
        if off2 + 8 > len(result):
            break
        c, csize = struct.unpack_from('<II', result, off2)
        if c == LC_SEGMENT_64:
            segname = result[off2+8:off2+24].rstrip(b'\x00')
            if segname == b'__LINKEDIT':
                struct.pack_into('<Q', result, off2 + 48, new_linkedit_fsize)
                vm_align = lambda x: (x + 4095) & ~4095
                struct.pack_into('<Q', result, off2 + 32, vm_align(new_linkedit_fsize))
                print(f'  __LINKEDIT: filesize {linkedit_fsize} -> {new_linkedit_fsize}')
                break
        off2 += csize

    new_size = len(result)
    old_size = len(data)
    print(f'  Removed {len(fixup_cmds)} commands, {fixup_data_size} bytes of fixup data')
    print(f'  Size: {old_size} -> {new_size} bytes')

    # Verify no fixup commands remain
    verify_ncmds = struct.unpack_from('<I', result, 16)[0]
    verify_off = 32
    still_present = False
    for i in range(verify_ncmds):
        if verify_off + 8 > len(result):
            break
        c, _ = struct.unpack_from('<II', result, verify_off)
        if c in FIXUP_CMDS:
            print(f'  ERROR: {CMD_NAMES.get(c, f"0x{c:08x}")} still present!')
            still_present = True
        verify_off += struct.unpack_from('<I', result, verify_off + 4)[0]
    if still_present:
        return False

    # Write result
    with open(path, 'wb') as f:
        f.write(result)

    print(f'  ✅ Successfully stripped chained fixups')
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
    if strip_fixups(path):
        print('Done!')
    else:
        print('FAILED!')
        sys.exit(1)
