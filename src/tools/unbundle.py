"""Unpack SOKBNDL1 bundles (written by the browser downloader, possibly split into .bin.NNN chunks).
    python3 tools/unbundle.py <tag> <src_dir> <out_dir> [--delete]
"""
import sys, os, json, struct, glob
tag, src, out = sys.argv[1:4]
parts = sorted(glob.glob(os.path.join(src, f'sokak_{tag}.bin.[0-9][0-9][0-9]'))) or [os.path.join(src, f'sokak_{tag}.bin')]
class Cat:
    def __init__(s, files): s.files = files; s.i = 0; s.f = open(files[0], 'rb')
    def read(s, n):
        buf = b''
        while n > 0:
            d = s.f.read(n)
            if not d:
                s.i += 1
                if s.i >= len(s.files): break
                s.f.close(); s.f = open(s.files[s.i], 'rb'); continue
            buf += d; n -= len(d)
        return buf
c = Cat(parts)
hdr = c.read(16); assert hdr[:8] == b'SOKBNDL1', hdr[:8]
mlen = struct.unpack('<Q', hdr[8:])[0]
man = json.loads(c.read(mlen))
tot = 0
for f in man['files']:
    p = os.path.join(out, f['n']); os.makedirs(os.path.dirname(p), exist_ok=True)
    data = c.read(f['s']); assert len(data) == f['s'], (f['n'], len(data), f['s'])
    open(p, 'wb').write(data); tot += len(data)
print(tag, len(man['files']), 'files', round(tot / 1e6, 1), 'MB ->', out)
if '--delete' in sys.argv:
    for p in parts: os.remove(p)
