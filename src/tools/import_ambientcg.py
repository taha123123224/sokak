"""v3.1: upgrade the main map surface sets to 2K CC0 ambientCG PBR scans (via petroulacl/fps-asset-kit).
Writes <set>_albedo.png (2K), _normal.png (2K, OpenGL), _orm.png (1K: AO, roughness, metal=0), _height.png (1K).
The new albedo is scaled to the old set's mean brightness so the per-material tints in matlib.gd still hold."""
import os, shutil
import numpy as np
from PIL import Image
SRC = "/home/claude/ext3d/fak/textures/"
OUT = "/home/claude/sokak/assets/tex/"
BAK = "/home/claude/old_assets/tex_v300/"
MAP = {"asphalt": "Asphalt023S", "brick2": "Bricks097", "stonewall": "Bricks102", "rawconc": "Concrete047A",
       "concrete": "Concrete034", "plaster": "Plaster002", "dryground": "Ground103"}
def f(s, k): return SRC + s + "/" + s + "_2K-JPG_" + k + ".jpg"
for dst, s in MAP.items():
    for k in ("albedo", "normal", "orm", "height"):
        p = OUT + dst + "_" + k + ".png"
        if os.path.exists(p) and not os.path.exists(BAK + os.path.basename(p)):
            shutil.copy(p, BAK)
    col = Image.open(f(s, "Color")).convert("RGB")
    old = OUT + dst + "_albedo.png"
    if os.path.exists(BAK + dst + "_albedo.png"):
        old = BAK + dst + "_albedo.png"
    a = np.asarray(col).astype(np.float32)
    if os.path.exists(old):
        o = np.asarray(Image.open(old).convert("RGB").resize((256, 256))).astype(np.float32)
        k = (o.mean() + 1) / (a.mean() + 1)
        a = np.clip(a * k, 0, 255)
    Image.fromarray(a.astype(np.uint8)).save(OUT + dst + "_albedo.png")
    Image.open(f(s, "NormalGL")).convert("RGB").save(OUT + dst + "_normal.png")
    rough = Image.open(f(s, "Roughness")).convert("L").resize((1024, 1024), Image.LANCZOS)
    ao = Image.open(f(s, "AmbientOcclusion")).convert("L").resize((1024, 1024), Image.LANCZOS) if os.path.exists(f(s, "AmbientOcclusion")) else Image.new("L", (1024, 1024), 255)
    Image.merge("RGB", (ao, rough, Image.new("L", (1024, 1024), 0))).save(OUT + dst + "_orm.png")
    if os.path.exists(f(s, "Displacement")):
        Image.open(f(s, "Displacement")).convert("L").resize((1024, 1024), Image.LANCZOS).save(OUT + dst + "_height.png")
    print("ok", dst, "<-", s)
