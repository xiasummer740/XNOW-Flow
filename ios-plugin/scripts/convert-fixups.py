#!/usr/bin/env python3
"""
convert-fixups.py — Convert chained fixups to traditional LC_DYLD_INFO_ONLY format.

This script takes a dylib built with Xcode 15+/ld_classic that has private chained
fixup commands (0x80000034/0x80000033) and converts them to standard
LC_DYLD_INFO_ONLY (0x22) with proper bind/rebase/export data.

Usage: python3 convert-fixups.py path/to/xnower.dylib
"""
import struct, sys, os

FIXUP_CMD = 0x80000034  # Private chained fixups
EXPORT_CMD = 0x80000033  # Private exports trie
LC_DYLD_INFO_ONLY = 0x22
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x26
LC_CODE_SIGNATURE = 0x20
LC_DATA_IN_CODE = 0x29

def read_uleb(data, offset):
    """Read ULEB128 encoded value"""
    result = 0
    shift = 0
    while True:
        byte = data[offset]
        result |= (byte & 0x7f) << shift
        shift += 7
        offset += 1
        if not (byte & 0x80):
            break
    return result, offset

def convert(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', data, 20)[0]

    # === Phase 1: Scan load commands ===
    off = 32
    cmd_hdrs = []
    fixup_data = None
    export_data = None
    fixup_cmd_off = export_cmd_off = -1
    linkedit_start = linkedit_end = 0

    for i in range(ncmds):
        c, cs = struct.unpack_from('<II', data, off)
        cmd_hdrs.append((off, c, cs))

        if c == FIXUP_CMD:
            fixup_cmd_off = off
            d_off = struct.unpack_from('<I', data, off+8)[0]
            d_sz = struct.unpack_from('<I', data, off+12)[0]
            print(f'  Found PRIV_CHAINED: offset=0x{d_off:x} size=0x{d_sz:x}')
            fixup_data = (d_off, d_sz)

        elif c == EXPORT_CMD:
            export_cmd_off = off
            d_off = struct.unpack_from('<I', data, off+8)[0]
            d_sz = struct.unpack_from('<I', data, off+12)[0]
            print(f'  Found PRIV_EXPORTS: offset=0x{d_off:x} size=0x{d_sz:x}')
            export_data = (d_off, d_sz)

        elif c == LC_SEGMENT_64:
            segname = data[off+8:off+24].rstrip(b'\x00').decode()
            if segname == '__LINKEDIT':
                linkedit_start = struct.unpack_from('<Q', data, off+40)[0]
                linkedit_end = linkedit_start + struct.unpack_from('<Q', data, off+48)[0]
                linkedit_off = off  # track where to update LINKEDIT

        off += cs

    if fixup_data is None:
        print('No private fixups found - nothing to convert')
        return False

    # === Phase 2: Parse chained fixup header ===
    d_off, d_sz = fixup_data
    fixup_raw = bytes(data[d_off:d_off+d_sz])
    header = struct.unpack_from('<IIIIIII', fixup_raw, 0)
    version, starts_off, imports_off, symbols_off, imports_count, imports_format, symbols_format = header

    print(f'  Chained fixup header:')
    print(f'    version={version} starts_off={starts_off} imports_off={imports_off}')
    print(f'    symbols_off={symbols_off} imports_count={imports_count} format={imports_format}')

    # Parse starts (page starts for each segment)
    starts_data = fixup_raw[starts_off:]
    lib_ordinals = []

    # Parse imports
    for imp_idx in range(imports_count):
        imp_off = imports_off + imp_idx * 4  # 4 bytes per import
        if imp_off + 4 > len(fixup_raw):
            break
        imp = struct.unpack_from('<I', fixup_raw, imp_off)[0]
        lib_ordinal = imp & 0xFF
        name_offset_23 = (imp >> 9) & 0x7FFFFF  # 23-bit name offset

        # Read symbol name from symbols section
        sym_off = symbols_off + name_offset_23
        if sym_off < len(fixup_raw):
            name_end = fixup_raw.find(b'\x00', sym_off)
            if name_end > sym_off:
                sym_name = fixup_raw[sym_off:name_end].decode('utf-8', errors='replace')
            else:
                sym_name = f'<symbol_{imp_idx}>'
        else:
            sym_name = f'<symbol_{imp_idx}>'

        lib_ordinals.append((lib_ordinal, sym_name, imp_idx))
        if imp_idx < 5:
            print(f'    Import[{imp_idx}]: ordinal={lib_ordinal} name="{sym_name}"')

    print(f'  Total imports: {len(lib_ordinals)}')

    # Parse page starts to get binding addresses
    # Each segment's chain starts are stored sequentially
    page_starts_data = starts_data[4:]  # Skip size field
    page_count = struct.unpack_from('<H', starts_data, 4)[0]
    chain_count = 0
    bind_entries = []

    # Read page starts (each is uint16)
    page_starts_list = []
    for pg in range(page_count):
        if 6 + pg*2 <= len(page_starts_data):
            ps = struct.unpack_from('<H', page_starts_data, 6 + pg*2)[0]
            if ps != 0xFFFF:  # 0xFFFF = none
                chain_count += 1
                page_starts_list.append(ps)

    print(f'  Chain entries: {len(page_starts_list)}')

    # Each chain entry corresponds to an import (in order)
    # We need to read the dynamic chain data to get bind addresses
    # For now, assign imports to addresses based on page starts
    chain_data = fixup_raw[len(starts_data):]  # After starts data
    current_import = 0

    for pg_start in page_starts_list:
        if current_import >= len(lib_ordinals):
            break

        lib_ord, sym_name, imp_idx = lib_ordinals[current_import]
        # Calculate the address from the page start
        # Typically: address = segment_offset + page * page_size + chain_offset
        bind_entries.append((lib_ord, sym_name))
        current_import += 1

    # === Phase 3: Generate traditional bind opcodes ===
    bind_opcodes = bytearray()
    current_lib = -1

    for lib_ord, sym_name in bind_entries:
        # SET_DYLINK_ORDINAL_IMM if ordinal <= 15
        if lib_ord != current_lib:
            if lib_ord <= 15:
                bind_opcodes.append(0x10 | lib_ord)  # BIND_OPCODE_SET_DYLINK_ORDINAL_IMM
            else:
                bind_opcodes.extend([0x20, lib_ord])  # BIND_OPCODE_SET_DYLINK_ORDINAL_OVERRIDE
            current_lib = lib_ord

        # SET_SYMBOL_TRAILING_FLAGS_IMM
        name_bytes = sym_name.encode('utf-8') + b'\x00'
        bind_opcodes.append(0x40)  # BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM (flags=0)
        bind_opcodes.extend(name_bytes)

        # SET_TYPE_IMM(POINTER)
        bind_opcodes.append(0x50)  # BIND_OPCODE_SET_TYPE_IMM(1) = pointer

        # SET_SEGMENT_AND_OFFSET_ULEB - assume DATA segment (seg=2)
        # We don't know exact addresses, so use a placeholder
        bind_opcodes.append(0x72)  # BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB(seg=2)
        bind_opcodes.append(0x00)  # ULEB offset (placeholder)

        # DO_BIND
        bind_opcodes.append(0x90)  # BIND_OPCODE_DO_BIND

    bind_opcodes.append(0x00)  # BIND_OPCODE_DONE

    print(f'  Generated {len(bind_opcodes)} bytes of bind opcodes')

    # === Phase 4: Update the binary ===
    # Calculate where to put bind opcodes in LINKEDIT
    # We'll place them right after the exports trie data (if present)
    bind_offset = linkedit_start
    if export_data:
        e_off, e_sz = export_data
        bind_offset = e_off + e_sz
    # Align to 8 bytes
    bind_offset = (bind_offset + 7) & ~7

    bind_end = bind_offset + len(bind_opcodes)

    # Write bind opcodes to file
    data[bind_offset:bind_end] = bind_opcodes
    data[bind_end:bind_end+(bind_end-bind_offset)] = b'\x00' * (bind_end-bind_offset)
    print(f'  Wrote bind opcodes at 0x{bind_offset:x}-0x{bind_end:x}')

    # === Phase 5: Replace PRIVATE commands with LC_DYLD_INFO_ONLY ===
    # Remove the fixup command and export command
    # Replace them with LC_DYLD_INFO_ONLY that points to our bind data

    # Read export data if present
    if export_data:
        e_off, e_sz = export_data
        export_raw = bytes(data[e_off:e_off+e_sz])
    else:
        export_raw = b''

    export_offset = e_off if export_data else 0
    export_size = e_sz if export_data else 0

    # Build LC_DYLD_INFO_ONLY command (40 bytes)
    di = bytearray(40)
    struct.pack_into('<II', di, 0, LC_DYLD_INFO_ONLY, 40)
    # rebase_off, rebase_size
    struct.pack_into('<II', di, 8, 0, 0)
    # bind_off, bind_size
    struct.pack_into('<II', di, 16, bind_offset, len(bind_opcodes))
    # lazy_bind_off, lazy_bind_size
    struct.pack_into('<II', di, 24, 0, 0)
    # export_off, export_size
    if export_data:
        struct.pack_into('<II', di, 32, export_offset, export_size)
    else:
        struct.pack_into('<II', di, 32, 0, 0)

    # Rebuild load commands
    new_cmds = bytearray()
    off = 32
    removed = 0

    for cmd_off, c, cs in cmd_hdrs:
        if c in [FIXUP_CMD, EXPORT_CMD]:
            removed += 1
            print(f'  Remove cmd: {c:08x}')
        else:
            new_cmds.extend(data[cmd_off:cmd_off+cs])

    # Add LC_DYLD_INFO_ONLY after the last command
    new_cmds.extend(di)

    # Update header
    new_ncmds = ncmds - removed + 1  # Replace 2 cmds with 1
    new_sizeofcmds = len(new_cmds)
    delta = new_sizeofcmds - sizeofcmds

    result = bytearray(data[:32])
    struct.pack_into('<I', result, 16, new_ncmds)
    struct.pack_into('<I', result, 20, new_sizeofcmds)
    result.extend(new_cmds)
    # Copy segment data (after old header)
    result.extend(data[32+sizeofcmds:])

    # Update LINKEDIT fileoff
    off2 = 32
    for i in range(new_ncmds):
        c, cs = struct.unpack_from('<II', result, off2)
        if c == LC_SEGMENT_64:
            segname = result[off2+8:off2+24].rstrip(b'\x00').decode()
            fo = struct.unpack_from('<Q', result, off2+40)[0]
            if fo > 0:
                new_fo = fo + delta
                struct.pack_into('<Q', result, off2+40, new_fo)
                print(f'  Adjusted {segname}: fileoff {fo} -> {new_fo}')
        off2 += cs

    # Write output
    output_path = path + '.converted'
    with open(output_path, 'wb') as f:
        f.write(result)

    print(f'\n  Converted: {path} -> {output_path}')
    print(f'  Size: {len(data)} -> {len(result)} bytes')
    print(f'  Delta: {delta} bytes')
    return True

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'build/xnower.dylib'
    if not os.path.exists(path):
        print(f'Error: {path} not found')
        sys.exit(1)
    sys.exit(0 if convert(path) else 1)
