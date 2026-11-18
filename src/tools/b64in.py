"""Rebuild a binary file from base64 chunks pasted into chunk files.
usage: python3 tools/b64in.py <out_file> <chunk1> [chunk2 ...]
(the Higgsfield sandbox can only talk back to us through tool output text, so images come over as base64)"""
import sys, base64, hashlib
out = sys.argv[1]
data = ''.join(open(c).read() for c in sys.argv[2:])
raw = base64.b64decode(''.join(data.split()))
open(out, 'wb').write(raw)
print(out, len(raw), hashlib.md5(raw).hexdigest()[:10])
