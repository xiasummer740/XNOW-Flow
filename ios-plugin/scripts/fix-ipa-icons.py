#!/usr/bin/env python3
"""
fix-ipa-icons.py — 修复 IPA 缺失的图标尺寸
对 BH/cracked IPA 中残缺的图标补全所有需要的尺寸

用法: python3 fix-ipa-icons.py <IPA路径> [输出IPA路径]
  例: python3 fix-ipa-icons.py TikTok_XNOW_v38.ipa TikTok_XNOW_v38_fixed.ipa

功能:
- 扫描 IPA 中所有 App Icon PNG
- 根据现有最大尺寸生成缺失的 (@3x, @2x, @1x) 图标
- 更新 Info.plist 图标引用
- 输出修复后的 IPA
"""
import struct, zlib, io, os, sys, shutil, tempfile, zipfile
from PIL import Image

def parse_chunks(data):
    """Parse PNG chunks, return list of (type, data_bytes)"""
    if data[:4] != b'\x89PNG':
        return None
    off = 8
    chunks = []
    while off < len(data) - 4:
        length = struct.unpack_from('>I', data, off)[0]
        ctype = data[off+4:off+8]
        chunk_data = data[off+8:off+8+length]
        crc = data[off+8+length:off+12+length]
        chunks.append({'type': ctype, 'data': chunk_data, 'crc': crc,
                       'start': off, 'end': off + 12 + length})
        off += 12 + length
        if ctype == b'IEND':
            break
    return chunks

def is_cgbi(data):
    """Check if PNG is CgBI (iPhone-optimized) format"""
    chunks = parse_chunks(data)
    if not chunks: return False
    return any(c['type'] == b'CgBI' for c in chunks)

def cgbi_to_std_png(cgbi_data):
    """Convert CgBI PNG to standard PNG"""
    # Validate
    if cgbi_data[:4] != b'\x89PNG':
        return None

    # Extract IHDR info
    chunks = parse_chunks(cgbi_data)
    ihdr_chunk = next((c for c in chunks if c['type'] == b'IHDR'), None)
    if not ihdr_chunk:
        return None
    w, h = struct.unpack_from('>II', ihdr_chunk['data'], 0)
    stride = w * 4 + 1  # filter byte per row

    # Collect IDAT data
    idat_data = b''
    for c in chunks:
        if c['type'] == b'IDAT':
            idat_data += c['data']

    if not idat_data:
        return None

    # Decompress (handle CgBI's modified zlib header)
    try:
        pixels = zlib.decompress(idat_data, -zlib.MAX_WBITS)
    except:
        try:
            pixels = zlib.decompress(idat_data)
        except:
            return None

    expected = h * stride
    if len(pixels) != expected:
        return None

    # Standard RGBA pixels (swap B<->R in CgBI)
    std_pixels = bytearray()
    for y in range(h):
        # CgBI may or may not have filter byte
        if len(pixels) >= (y + 1) * stride:
            row_start = y * stride + 1
        else:
            row_start = y * w * 4
        row = pixels[row_start:row_start + w * 4]
        for i in range(0, len(row), 4):
            # BGRA -> RGBA
            std_pixels.extend([row[i+2], row[i+1], row[i], row[i+3]])

    return bytes(std_pixels), w, h

def rgba_to_cgbi_png(pixels_rgba, width, height):
    """
    Convert RGBA pixel data to CgBI-format PNG
    CgBI: BGRA byte order + modified zlib header + CgBI chunk
    """
    # Add filter bytes (None filter for each scanline)
    filtered = bytearray()
    for y in range(height):
        filtered.append(0)  # filter type: None
        row_start = y * width * 4
        row = pixels_rgba[row_start:row_start + width * 4]
        for i in range(0, len(row), 4):
            # RGBA -> BGRA
            filtered.extend([row[i+2], row[i+1], row[i], row[i+3]])

    # Compress
    compressed = zlib.compress(bytes(filtered))

    # Build CgBI PNG
    result = bytearray()
    result.extend(b'\x89PNG\r\n\x1a\n')

    def write_chunk(d, ctype, content):
        crc = zlib.crc32(ctype, 0xFFFFFFFF)
        crc = zlib.crc32(content, crc) ^ 0xFFFFFFFF
        d.extend(struct.pack('>I', len(content)))
        d.extend(ctype)
        d.extend(content)
        d.extend(struct.pack('>I', crc & 0xFFFFFFFF))

    # CgBI chunk (required marker)
    write_chunk(result, b'CgBI', b'\x50\x00\x20\x06')

    # IHDR
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    write_chunk(result, b'IHDR', ihdr)

    # IDAT
    write_chunk(result, b'IDAT', compressed)

    # IEND
    write_chunk(result, b'IEND', b'')

    return bytes(result)

def load_png_pixels(data):
    """Load pixels from PNG (both standard and CgBI), return (pixels, w, h)"""
    # Try CgBI first
    if is_cgbi(data):
        result = cgbi_to_std_png(data)
        if result:
            return result

    # Try standard PNG via PIL
    try:
        img = Image.open(io.BytesIO(data))
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        return img.tobytes(), img.width, img.height
    except:
        return None

def get_icon_sizes(plist_data):
    """Parse IconFiles from Info.plist data"""
    import plistlib
    try:
        pl = plistlib.loads(plist_data)
    except:
        return []

    icon_names = set()

    # CFBundleIcons -> CFBundlePrimaryIcon -> CFBundleIconFiles
    icons = pl.get('CFBundleIcons', {})
    primary = icons.get('CFBundlePrimaryIcon', {})
    for f in primary.get('CFBundleIconFiles', []):
        icon_names.add(f)

    # CFBundleIcons~ipad
    icons_ipad = pl.get('CFBundleIcons~ipad', {})
    primary_ipad = icons_ipad.get('CFBundlePrimaryIcon', {})
    for f in primary_ipad.get('CFBundleIconFiles', []):
        icon_names.add(f)

    # Legacy CFBundleIconFiles
    for f in pl.get('CFBundleIconFiles', []):
        icon_names.add(f)

    return sorted(icon_names)

def update_info_plist_icons(plist_data, icon_files):
    """Add missing icon file names to Info.plist"""
    import plistlib
    try:
        pl = plistlib.loads(plist_data)
    except:
        return plist_data

    modified = False

    # Add to both iPhone and iPad sections
    for key in ['CFBundleIcons', 'CFBundleIcons~ipad']:
        icons_dict = pl.get(key, {})
        primary = icons_dict.get('CFBundlePrimaryIcon', {})
        existing = set(primary.get('CFBundleIconFiles', []))
        for icon_file in icon_files:
            if icon_file not in existing:
                existing.add(icon_file)
                modified = True
        if modified:
            primary['CFBundleIconFiles'] = sorted(existing)
            icons_dict['CFBundlePrimaryIcon'] = primary
            pl[key] = icons_dict

    if modified:
        return plistlib.dumps(pl)
    return plist_data

def fix_ipa(input_ipa, output_ipa=None):
    """Main function: fix icons in IPA"""
    if output_ipa is None:
        base, ext = os.path.splitext(input_ipa)
        output_ipa = f"{base}_iconfix{ext}"

    if not os.path.exists(input_ipa):
        print(f"ERROR: {input_ipa} not found")
        return False

    size_in = os.path.getsize(input_ipa)
    print(f"Input:  {input_ipa} ({size_in/1024/1024:.1f} MB)")
    print(f"Output: {output_ipa}")

    tmpdir = tempfile.mkdtemp()
    try:
        print("\n[1] Extract IPA...")
        with zipfile.ZipFile(input_ipa, 'r') as z:
            z.extractall(tmpdir)

        # Find .app directory
        payload = os.path.join(tmpdir, 'Payload')
        app_dirs = [d for d in os.listdir(payload) if d.endswith('.app')]
        if not app_dirs:
            print("ERROR: No .app found in Payload")
            return False

        app_dir = os.path.join(payload, app_dirs[0])
        print(f"  App: {app_dirs[0]}")

        # Read Info.plist
        plist_path = os.path.join(app_dir, 'Info.plist')
        if not os.path.exists(plist_path):
            print("ERROR: Info.plist not found")
            return False

        with open(plist_path, 'rb') as f:
            plist_data = f.read()

        icon_names = get_icon_sizes(plist_data)
        print(f"\n[2] Scan icons from Info.plist...")
        print(f"  Icon names: {icon_names}")

        if not icon_names:
            print("  No icon references found in Info.plist!")
            return False

        # Scan existing icon files (handle ~ipad suffix too)
        existing_icons = {}
        for name in icon_names:
            for suffix, size_label in [('@3x.png', '@3x'), ('@2x.png', '@2x'), ('.png', '@1x')]:
                for variant in ['', '~ipad']:
                    fname = f"{name}{suffix.replace('.png', variant + '.png')}"
                    fpath = os.path.join(app_dir, fname)
                    if os.path.exists(fpath):
                        with open(fpath, 'rb') as f:
                            data = f.read()
                        existing_icons[(name, size_label)] = {
                            'path': fpath,
                            'data': data,
                            'is_cgbi': is_cgbi(data),
                            'variant': variant
                        }
                        print(f"  Found: {fname} ({len(data)} bytes, {'CgBI' if is_cgbi(data) else 'Standard'})")
                        break

        # Generate missing sizes
        generated = []
        for name in icon_names:
            # Find the best source (prefer largest existing)
            source = None
            for sl in ['@3x', '@2x', '@1x']:
                if (name, sl) in existing_icons:
                    source = existing_icons[(name, sl)]
                    source_scale = {'@3x': 3, '@2x': 2, '@1x': 1}[sl]
                    break

            if not source:
                print(f"  WARNING: No source icon for {name}, skipping")
                continue

            # Determine target sizes from the existing source
            pixels_info = load_png_pixels(source['data'])
            if not pixels_info:
                print(f"  WARNING: Cannot decode source icon {name}, skipping")
                continue

            src_pixels, src_w, src_h = pixels_info

            # Generate missing sizes
            for suffix, target_scale, label in [
                ('@3x.png', 3, '@3x'),
                ('@2x.png', 2, '@2x'),
                ('.png', 1, '@1x'),
            ]:
                if (name, label) in existing_icons:
                    continue  # already exists

                # Only generate sizes smaller than or equal to the source
                if target_scale > source_scale:
                    # Can upscale: use source as base
                    target_w = src_w * target_scale // source_scale
                    target_h = src_h * target_scale // source_scale

                    # PIL resize
                    img = Image.frombytes('RGBA', (src_w, src_h), src_pixels)
                    img_resized = img.resize((target_w, target_h), Image.LANCZOS)
                    resize_pixels = img_resized.tobytes()

                    # Save as CgBI PNG
                    cgbi_png = rgba_to_cgbi_png(resize_pixels, target_w, target_h)

                    fname = f"{name}{suffix}"
                    fpath = os.path.join(app_dir, fname)
                    with open(fpath, 'wb') as f:
                        f.write(cgbi_png)
                    generated.append((fname, target_w, target_h, len(cgbi_png)))
                    print(f"  Generated: {fname} ({target_w}x{target_h}, {len(cgbi_png)} bytes)")
                elif target_scale < source_scale:
                    # Downscale
                    target_w = src_w * target_scale // source_scale
                    target_h = src_h * target_scale // source_scale

                    img = Image.frombytes('RGBA', (src_w, src_h), src_pixels)
                    img_resized = img.resize((target_w, target_h), Image.LANCZOS)
                    resize_pixels = img_resized.tobytes()

                    cgbi_png = rgba_to_cgbi_png(resize_pixels, target_w, target_h)

                    fname = f"{name}{suffix}"
                    fpath = os.path.join(app_dir, fname)
                    with open(fpath, 'wb') as f:
                        f.write(cgbi_png)
                    generated.append((fname, target_w, target_h, len(cgbi_png)))
                    print(f"  Generated: {fname} ({target_w}x{target_h}, {len(cgbi_png)} bytes)")
                else:
                    pass  # same scale, skip

        if not generated:
            print("\n  No missing icons to generate. All sizes present.")

        # Also generate iPad icon if needed
        ipad_check = [n for n in icon_names if '76x76' in n or '83.5' in n]
        if not ipad_check:
            # Try to add iPad icon support
            ipad_sizes = [
                ('AppIcon_TikTok76x76', 76, 76, '@2x~ipad.png', 2),
                ('AppIcon_TikTok83.5x83.5', 83.5, 83.5, '@2x~ipad.png', 2),
            ]
            for name, w_pt, h_pt, suffix, scale in ipad_sizes:
                fname = f"{name}{suffix}"
                fpath = os.path.join(app_dir, fname)
                if not os.path.exists(fpath) and '60x60' in str(icon_names):
                    # Generate from 60x60 source
                    src_key = next(((n, s) for n, s in existing_icons if '60x60' in n), None)
                    if src_key:
                        source = existing_icons.get(src_key)
                        if source:
                            pixels_info = load_png_pixels(source['data'])
                            if pixels_info:
                                src_pixels, src_w, src_h = pixels_info
                                target_w = int(w_pt * scale)
                                target_h = int(h_pt * scale)
                                img = Image.frombytes('RGBA', (src_w, src_h), src_pixels)
                                img_resized = img.resize((target_w, target_h), Image.LANCZOS)
                                cgbi_png = rgba_to_cgbi_png(img_resized.tobytes(), target_w, target_h)
                                with open(fpath, 'wb') as f:
                                    f.write(cgbi_png)
                                print(f"  Generated (iPad): {fname} ({target_w}x{target_h}, {len(cgbi_png)} bytes)")

        print("\n[3] Verify generated icons...")
        for name in icon_names:
            for suffix, label in [('@3x.png', '@3x'), ('@2x.png', '@2x'), ('.png', '@1x')]:
                fname = f"{name}{suffix}"
                fpath = os.path.join(app_dir, fname)
                if os.path.exists(fpath):
                    with open(fpath, 'rb') as f:
                        data = f.read()
                    ok = is_cgbi(data) and len(data) > 100
                    print(f"  {'OK' if ok else '??'} {fname} ({len(data)} bytes)")

        print("\n[4] Package IPA...")
        if os.path.exists(output_ipa):
            os.remove(output_ipa)

        with zipfile.ZipFile(output_ipa, 'w', zipfile.ZIP_DEFLATED, compresslevel=5) as zout:
            for root, dirs, files in os.walk(tmpdir):
                for f in files:
                    fp = os.path.join(root, f)
                    zout.write(fp, os.path.relpath(fp, tmpdir))

        size_out = os.path.getsize(output_ipa)
        delta = (size_out - size_in) / 1024 / 1024
        print(f"\n[OK] {output_ipa} ({size_out/1024/1024:.1f} MB, {'+' if delta >= 0 else ''}{delta:.1f} MB)")
        print(f"Generated {len(generated)} missing icon file(s)")
        return True

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    input_ipa = sys.argv[1]
    output_ipa = sys.argv[2] if len(sys.argv) > 2 else None

    success = fix_ipa(input_ipa, output_ipa)
    sys.exit(0 if success else 1)
