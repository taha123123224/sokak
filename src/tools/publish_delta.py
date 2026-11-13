"""v4.4 delta publish: copy only new packs from <split dir> into the dist repo, drop the ones no longer used.
python3 tools/publish_delta.py <split dir>  -> prints what changed (then commit/push dist, run make_manifest.py)"""
import json, os, shutil, sys
split = sys.argv[1]
D = '/tmp/distrepo/packs'
packs = json.load(open(os.path.join(split, 'packs.json')))
want = set()
new_mb = 0
for p in packs:
    name = ('SOKAK_%s.pck' % p['md5'][:10]) if p['f'] == 'SOKAK.pck' else p['f'].split('/')[-1]
    want.add(name)
    if not os.path.exists(os.path.join(D, name)):
        shutil.copy(os.path.join(split, p['f']), os.path.join(D, name))
        new_mb += p['size'] / 1e6
        print("NEW", name, round(p['size'] / 1e6, 1), "MB")
for fn in os.listdir(D):
    if fn not in want:
        os.remove(os.path.join(D, fn))
        print("DEL", fn)
print("download for players: %.1f MB" % new_mb)
