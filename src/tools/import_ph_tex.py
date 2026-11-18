"""Convert downloaded Poly Haven 4K sets (dl_tex/<id>/<id>_{Diffuse,nor_gl,arm,Displacement}_4k.jpg) into
project textures assets/tex/<local>_{albedo,normal,orm,height}.jpg at the chosen resolution.

- albedo brightness (and saturation, for sets the game tints) is matched to the previous project texture
  of the same local name, so materials keep their tuned in-game look while gaining detail
- writes Godot .import files with the same settings as the existing textures (VRAM S3TC/BPTC, mipmaps,
  normal-map mode for *_normal) and removes the replaced .png sources
    python3 tools/import_ph_tex.py
"""
import os, re
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
TEX = os.path.join(ROOT, 'assets', 'tex')
DL = '/home/claude/dl_tex'
Image.MAX_IMAGE_PIXELS = None

# local name -> (poly haven id, size, mode)   mode: 'match' = keep old mean colour, 'grey' = neutral (tinted in game)
SETS = {
    'rawconc':     ('concrete_wall_004', 4096, 'match'),
    'plaster':     ('painted_plaster_wall', 4096, 'grey'),
    'brick2':      ('red_brick_03', 4096, 'match'),
    'stonewall':   ('rustic_stone_wall_02', 4096, 'match'),
    'asphalt':     ('asphalt_02', 4096, 'match'),
    'cobble':      ('cobblestone_floor_08', 4096, 'match'),
    'dryground':   ('dry_ground_01', 2048, 'match'),
    'mud':         ('muddy_tracks', 2048, 'raw'),
    'soilwall':    ('excavated_soil_wall', 2048, 'raw'),
    'plasterbrick': ('rough_plaster_brick_02', 2048, 'raw'),
    'fortwall':    ('defense_wall', 2048, 'raw'),
    'contside':    ('container_side', 2048, 'grey'),
    'rustsheet':   ('rusty_corrugated_iron', 2048, 'raw'),
    'drygrass':    ('withered_grass', 2048, 'raw'),
    'siding':      ('weathered_plank_siding', 2048, 'raw'),
    'whiteplaster': ('white_plaster_rough_01', 2048, 'raw'),
}

IMPORT_TMPL = '''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/tex/{name}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={nm}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
'''


def load(path, size):
    im = Image.open(path).convert('RGB')
    if im.size[0] != size:
        im = im.resize((size, size), Image.LANCZOS)
    return im


def write(local, kind, im, nm=0):
    name = f'{local}_{kind}.jpg'
    im.save(os.path.join(TEX, name), quality=94, subsampling=0 if kind != 'albedo' else 2)
    with open(os.path.join(TEX, name + '.import'), 'w') as f:
        f.write(IMPORT_TMPL.format(name=name, nm=nm))
    for ext in ('.png', '.png.import'):
        p = os.path.join(TEX, f'{local}_{kind}{ext}')
        if os.path.exists(p):
            os.remove(p)


def main():
    for local, (pid, size, mode) in SETS.items():
        d = os.path.join(DL, pid)
        if not os.path.isdir(d):
            print('missing', pid); continue
        f = {k: os.path.join(d, f'{pid}_{k}_4k.jpg') for k in ('Diffuse', 'nor_gl', 'arm', 'Displacement')}
        alb = np.asarray(load(f['Diffuse'], size)).astype(np.float32) / 255.0
        old = None
        for ext in ('png', 'jpg'):
            p = os.path.join(TEX, f'{local}_albedo.{ext}')
            if os.path.exists(p):
                old = np.asarray(Image.open(p).convert('RGB').resize((256, 256))).astype(np.float32) / 255.0
                break
        if mode == 'grey':
            lum = alb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
            alb = np.repeat(lum[..., None], 3, 2)
        if mode in ('match', 'grey') and old is not None:
            # per-channel mean match in linear-ish space (keeps the tuned in-game tone)
            tgt = old.reshape(-1, 3).mean(0); cur = alb.reshape(-1, 3).mean(0)
            alb = np.clip(alb * (tgt / np.maximum(cur, 1e-4)), 0, 1)
        write(local, 'albedo', Image.fromarray((alb * 255 + 0.5).astype(np.uint8)))
        write(local, 'normal', load(f['nor_gl'], size), nm=1)
        write(local, 'orm', load(f['arm'], size))
        if os.path.exists(f['Displacement']):
            write(local, 'height', load(f['Displacement'], size).convert('L').convert('RGB'))
        else:
            for ext in ('.png', '.png.import', '.jpg', '.jpg.import'):
                p = os.path.join(TEX, f'{local}_height{ext}')
                if os.path.exists(p):
                    os.remove(p)
        print(local, '<-', pid, size, mode, 'old' if old is not None else 'new')


if __name__ == '__main__':
    main()
