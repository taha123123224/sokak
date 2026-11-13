"""v4.4 delta updates: split the exported SOKAK.pck into a small main pack + content-addressed shard packs.

    python3 tools/split_pck.py <full.pck> <outdir> [shards=64]

Large imported resources (.godot/imported/*, >= 64 KB) are spread over N shards by a stable hash of their path,
everything else (scripts, scenes, project settings, small files) stays in the main pack. Each pack is a valid
Godot 4.5 PCK (format 3); entries are sorted, so an unchanged shard is byte-identical between releases and its
file name (pNN_<md5>.pck) does not change -> players only download the packs that really changed.
Writes <outdir>/SOKAK.pck, <outdir>/veri/pNN_<md5>.pck and <outdir>/packs.json.
"""
import hashlib, json, os, struct, sys, zlib

ALIGN = 16
MIN_SHARD = 64 * 1024


def read_pck(path):
    f = open(path, 'rb')
    magic, ver, ma, mi, pa, flags = struct.unpack('<4sIIIII', f.read(24))
    assert magic == b'GDPC' and ver == 3, (magic, ver)
    file_base, dir_off = struct.unpack('<QQ', f.read(16))
    f.seek(dir_off)
    n = struct.unpack('<I', f.read(4))[0]
    ents = []
    for _ in range(n):
        ln = struct.unpack('<I', f.read(4))[0]
        p = f.read(ln).rstrip(b'\0').decode('utf-8')
        off, size = struct.unpack('<QQ', f.read(16))
        md5 = f.read(16)
        fl = struct.unpack('<I', f.read(4))[0]
        ents.append(dict(path=p, off=off, size=size, md5=md5, flags=fl))
    return f, (ma, mi, pa, flags), file_base, ents


def pad(n):
    return (ALIGN - n % ALIGN) % ALIGN


def write_pck(out, src, verinfo, file_base_src, ents):
    ma, mi, pa, flags = verinfo
    ents = sorted(ents, key=lambda e: e['path'])
    hdr_len = 24 + 16 + 16 * 4
    base = hdr_len + pad(hdr_len)
    # lay out data
    cur = 0
    lay = []
    for e in ents:
        lay.append(cur)
        cur += e['size'] + pad(e['size'])
    dir_off = base + cur
    with open(out, 'wb') as o:
        o.write(struct.pack('<4sIIIII', b'GDPC', 3, ma, mi, pa, flags))
        o.write(struct.pack('<QQ', base, dir_off))
        o.write(b'\0' * (16 * 4))
        o.write(b'\0' * pad(hdr_len))
        for e in ents:
            src.seek(file_base_src + e['off'])
            left = e['size']
            while left > 0:
                chunk = src.read(min(left, 1 << 22))
                o.write(chunk)
                left -= len(chunk)
            o.write(b'\0' * pad(e['size']))
        assert o.tell() == dir_off
        o.write(struct.pack('<I', len(ents)))
        for e, rel in zip(ents, lay):
            pb = e['path'].encode('utf-8')
            ln = len(pb) + 1
            ln += (4 - ln % 4) % 4
            o.write(struct.pack('<I', ln))
            o.write(pb + b'\0' * (ln - len(pb)))
            o.write(struct.pack('<QQ', rel, e['size']))
            o.write(e['md5'])
            o.write(struct.pack('<I', e['flags']))


def md5_file(p):
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 22), b''):
            h.update(c)
    return h.hexdigest()


def main():
    src_path, outdir = sys.argv[1], sys.argv[2]
    N = int(sys.argv[3]) if len(sys.argv) > 3 else 64
    src, verinfo, fb, ents = read_pck(src_path)
    main_e, shards = [], {}
    for e in ents:
        if e['path'].startswith('.godot/imported/') and e['size'] >= MIN_SHARD:
            k = zlib.crc32(e['path'].encode('utf-8')) % N
            shards.setdefault(k, []).append(e)
        else:
            main_e.append(e)
    os.makedirs(os.path.join(outdir, 'veri'), exist_ok=True)
    packs = []
    mp = os.path.join(outdir, 'SOKAK.pck')
    write_pck(mp, src, verinfo, fb, main_e)
    packs.append({"f": "SOKAK.pck", "size": os.path.getsize(mp), "md5": md5_file(mp)})
    for k in sorted(shards):
        tmp = os.path.join(outdir, 'veri', 'tmp.pck')
        write_pck(tmp, src, verinfo, fb, shards[k])
        m = md5_file(tmp)
        name = 'veri/p%02d_%s.pck' % (k, m[:10])
        os.replace(tmp, os.path.join(outdir, name))
        packs.append({"f": name, "size": os.path.getsize(os.path.join(outdir, name)), "md5": m})
    json.dump(packs, open(os.path.join(outdir, 'packs.json'), 'w'), indent=1)
    tot = sum(p['size'] for p in packs)
    print("main %.1f MB, %d shards, total %.1f MB (largest shard %.1f MB)" % (
        packs[0]['size'] / 1e6, len(packs) - 1, tot / 1e6, max(p['size'] for p in packs[1:]) / 1e6))


if __name__ == '__main__':
    main()
