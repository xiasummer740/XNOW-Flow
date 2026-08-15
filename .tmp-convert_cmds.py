import struct
with open('/root/xnow-build/xnower.dylib', 'rb') as fh:
    data = bytearray(fh.read())
ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
converted = 0
for i in range(ncmds):
    c, cs = struct.unpack_from('<II', data, off)
    if c == 0x80000022:
        struct.pack_into('<I', data, off, 0x22); converted += 1
    if c == 0x80000033:
        struct.pack_into('<I', data, off, 0x35); converted += 1
    if c == 0x80000034:
        struct.pack_into('<I', data, off, 0x36); converted += 1
    off += cs
print(f'Converted {converted} command(s)')
with open('/root/xnow-build/xnower.dylib', 'wb') as fh:
    fh.write(data)
