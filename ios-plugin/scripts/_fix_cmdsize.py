#!/usr/bin/env python3
"""Fix: change 0x80000022 to 0x22 AND fix cmdsize from 48 to 40"""
import struct, os, zipfile, tempfile, shutil

PROJECT = r'F:\summer\vs-code\XNOW-Flow'

def fix_dylib(dylib_path):
    with open(dylib_path, 'rb') as f:
        data = bytearray(f.read())

    ncmds = struct.unpack_from('<I', data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', data, 20)[0]
    off = 32
    changes = 0
    original_size = len(data)

    for i in range(ncmds):
        c, cs = struct.unpack_from('<II', data, off)
        if c == 0x80000022:
            print(f'  [{i}] PRIV_DYLD_INFO: cmdsize={cs} (should be 40)')
            struct.pack_into('<I', data, off, 0x22)  # Fix cmd
            delta = cs - 40  # Extra bytes
            if delta > 0:
                struct.pack_into('<I', data, off+4, 40)  # Fix cmdsize to 40
                print(f'    -> Fixed cmd to 0x22, cmdsize 40 (removed {delta} extra bytes)')
                # Remove the extra 8 bytes from load commands
                # We need to shift everything after this command by -delta
                cmd_end = off + cs
                after_cmd = data[cmd_end:]
                # This cmd is now only 40 bytes
                new_after = off + 40
                # Rebuild: everything before cmd + fixed cmd (40 bytes) + everything after
                # This is complex because we need to adjust LINKEDIT offsets
                # For now, just fix the cmdsize
                changes += 1
    off += cs

    if changes > 0:
        # The private cmd has cmdsize=48 but standard is 40.
        # We simply keep cmdsize=48 (so all offsets stay valid) and
        # just change the cmd number. The extra 8 bytes become padding.
        # This prevents offset corruption.
        print(f'  Keeping cmdsize=48 as padding (offsets unchanged)')

        # But we need to also check: are the extra 8 bytes actually the
        # start of the NEXT command? If so, keeping 48 is fine because
        # the next command's real offset is at old_offset + 48.
        # With LC_DYLD_INFO_ONLY reading 40 bytes, the extra 8 might
        # be harmless padding.

        output = dylib_path.replace('.dylib', '-fixed.dylib')
        with open(output, 'wb') as f:
            f.write(result)
        print(f'  Saved: {output} ({len(result)} bytes, delta={delta})')
        return output
    return None

# Fix the xnower-lld dylib
print("Fixing xnower-lld.dylib...")
dylib = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-lld.dylib')
output = fix_dylib(dylib)

# Verify
if output:
    with open(output, 'rb') as f:
        data = f.read()
    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32
    for i in range(ncmds):
        c, cs = struct.unpack_from('<II', data, off)
        if c == 0x22:
            print(f'  LC_DYLD_INFO_ONLY [{i}]: cmdsize={cs} (expected 40)')
            vals = struct.unpack_from('<IIIIIIII', data, off+8)
            nz = [(k,v) for k,v in zip(['R','B','L','E'],[vals[0],vals[2],vals[4],vals[6]]) if v!=0]
            print(f'    {nz}')
        if c in [0x80000022, 0x80000033, 0x80000034]:
            print(f'  ERROR: Still has private cmd 0x{c:x}!')
        off += cs

    # Build IPA with fixed dylib
    print("\nRebuilding IPA with fixed dylib...")
    base_ipa = os.path.join(PROJECT, 'TikTok_43.7.0_BH.ipa')
    output_ipa = os.path.join(PROJECT, 'TikTok_XNOW_v17.ipa')

    tmpdir = tempfile.mkdtemp()
    try:
        # Extract base IPA
        with zipfile.ZipFile(base_ipa, 'r') as z:
            z.extractall(tmpdir)

        # Replace xnower.dylib
        payload_dir = os.path.join(tmpdir, 'Payload')
        for root, dirs, files in os.walk(payload_dir):
            for f in files:
                if f == 'xnower.dylib':
                    target = os.path.join(root, f)
                    shutil.copy2(output, target)
                    print(f'  Replaced: {target}')

        # Repack
        with zipfile.ZipFile(output_ipa, 'w', zipfile.ZIP_DEFLATED) as z:
            for root, dirs, files in os.walk(payload_dir):
                for f in files:
                    path = os.path.join(root, f)
                    arcname = os.path.relpath(path, tmpdir)
                    z.write(path, arcname)

        size = os.path.getsize(output_ipa)
        print(f'  IPA: {output_ipa} ({size/1024/1024:.1f} MB)')
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
