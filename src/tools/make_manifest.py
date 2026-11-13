"""v4.4 write version.json with the delta pack list.
python3 tools/make_manifest.py <packs.json> <version> <build> "<notes>"   (legacy full-pack parts stay frozen at build 58)"""
import json, sys
RAW = "https://raw.githubusercontent.com/taha123123224/sokak/dist/"
packs = json.load(open(sys.argv[1]))
vp = '/home/claude/gh_sokak/version.json'
v = json.load(open(vp))
v['version'] = sys.argv[2]; v['build'] = int(sys.argv[3]); v['notes'] = sys.argv[4]
out = []
for p in packs:
    f = p['f']
    name = ('SOKAK_%s.pck' % p['md5'][:10]) if f == 'SOKAK.pck' else f.split('/')[-1]
    out.append({"f": f, "size": p['size'], "md5": p['md5'], "url": RAW + "packs/" + name})
v['packs'] = out
v['packs_total'] = sum(p['size'] for p in packs)
json.dump(v, open(vp, 'w'), indent=1, ensure_ascii=False)
print("manifest", v['version'], v['build'], len(out), "packs")
