"""Decode files that were shipped through an image channel as raw bytes in an RGB PNG
(8-byte little-endian length header). usage: png_unpack.py <in.png> <out_file>"""
import sys, hashlib, numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).tobytes()
n = int.from_bytes(a[:8], 'little')
d = a[8:8 + n]
open(sys.argv[2], 'wb').write(d)
print(sys.argv[2], n, hashlib.md5(d).hexdigest())
