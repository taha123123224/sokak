"""Second pass of real recordings (v2.9.9): Oculus Audio Pack 01 (Oculus VR, LLC) - CC BY 4.0,
via github.com/facebookincubator/Meta-open-sound. Ambience loops, footsteps, knife, gore, shells, cloth.
python3 tools/build_sfx3.py   (run after build_sfx2.py)"""
import os, subprocess, shutil
O = "/home/claude/ext_audio/meta/corpora/oculus-audio-pack/ogg/"
OUT = "/home/claude/sokak/assets/sfx/"
BAK = "/home/claude/old_assets/sfx_synth/"
os.makedirs(BAK, exist_ok=True)

def backup(dst):
    for ext in (".wav", ".ogg"):
        n = os.path.splitext(dst)[0] + ext
        if os.path.exists(OUT + n) and not os.path.exists(BAK + n):
            shutil.copy(OUT + n, BAK + n)
        if ext != os.path.splitext(dst)[1] and os.path.exists(OUT + n):
            os.remove(OUT + n)
            if os.path.exists(OUT + n + ".import"): os.remove(OUT + n + ".import")

def ff(srcs, dst, af="", ss=None, t=None, mono=True, q=None):
    backup(dst)
    cmd = ["ffmpeg", "-v", "error", "-y"]
    if isinstance(srcs, str): srcs = [srcs]
    for s in srcs:
        if ss is not None: cmd += ["-ss", str(ss)]
        if t is not None: cmd += ["-t", str(t)]
        cmd += ["-i", O + s + ".ogg"]
    if len(srcs) > 1:
        ins = "".join(f"[{i}]" for i in range(len(srcs)))
        af = f"{ins}amix=inputs={len(srcs)}:normalize=0" + ("," + af if af else "")
        cmd += ["-filter_complex", af]
    elif af:
        cmd += ["-af", af]
    cmd += ["-ac", "1" if mono else "2", "-ar", "44100"]
    if dst.endswith(".ogg"): cmd += ["-c:a", "libvorbis", "-q:a", str(q or 5)]
    cmd += [OUT + dst]
    subprocess.run(cmd, check=True)

N = lambda lufs: f"loudnorm=I={lufs}:TP=-1.5:LRA=11"
FADE = lambda d: f"afade=t=in:d=1.5,afade=t=out:st={d-1.5}:d=1.5"

# ---- ambience loops (stereo ogg, long, gentle fades so the loop seam is soft) ----
amb = {
    "amb_city": (["AMBUrbn_CityEuroDaytime_LOOP_01"], -30),
    "amb_town": (["WINDVege_LightWindTreesBirds_LOOP_01"], -31),
    "amb_ship": (["WATRLap_WaterLapping_LOOP_01", "AMBInd_RoomToneMachineRoom_LOOP_01"], -31),
    "amb_port": (["AMBSea_BeachWavesStonesBirds_LOOP_01"], -30),
    "amb_sea":  (["WATRWave_OceanWaves_LOOP_01"], -30),
    "amb_wind": (["WINDVege_WindTreesBirdsFlies_LOOP_01", "CLOTHFlp_FlagFlapping_LOOP_01"], -31),
    "amb_site": (["AMBCnst_ConstructionSiteMedium_LOOP_01"], -34),
}
for k, (src, l) in amb.items():
    ff(src, k + ".ogg", "highpass=f=60," + N(l), t=60, mono=False, q=4)

# ---- footsteps: real shoes on concrete / metal / wood ----
for surf, nm in (("Concrete", "concrete"), ("Metal", "metal"), ("Wood", "wood")):
    for i in range(4):
        ff(f"FEETHmn_Shoe{surf}Run_OS_0{i+1}", f"step_{nm}{i}.wav", "highpass=f=70,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse," + N(-22))
ff("FEETHmn_ShoeConcreteLand_OS_01", "land.wav", "highpass=f=50," + N(-20))

# ---- knife ----
ff("SWSH_Swoosh_OS_02", "knife_swing.wav", "highpass=f=200,atrim=0:0.5," + N(-20))
ff(["GORESqsh_BloodSquishSlimy_OS_01", "FGHTImpt_PunchHarder_OS_01"], "knife_hit.wav", "atrim=0:0.6," + N(-17))
ff(["WEAPKnif_KnifeScrape_OS_01", "METLImpt_MetalHitSurface_OS_01"], "knife_wall.wav", "atrim=0:0.7," + N(-19))
# ---- gore (bullet hits on flesh) ----
ff(["GORESqsh_BloodSquishSlimy_OS_02", "FGHTImpt_PunchHarder_OS_02"], "gore0.wav", "atrim=0:0.5," + N(-19))
ff("GORESqsh_BloodSquishSlimy_OS_03", "gore1.wav", "atrim=0:0.5," + N(-19))
# ---- brass shell casings on concrete ----
for i in range(3):
    ff(f"BLLTShel_ShellCasingConcrete_OS_0{i+1}", f"shell{i}.wav", "highpass=f=300,atrim=0:0.8," + N(-26))
# ---- grenade throw / equip cloth ----
ff("WHSH_WhooshMedium_OS_01", "throw.wav", "highpass=f=150,atrim=0:0.7," + N(-21))
ff(["CLOTHMvmt_MovementWithGear_OS_01", "MECHSwtch_SwitchSmallOn_OS_01"], "equip.wav", "atrim=0:0.6," + N(-22))
ff("WHSH_WhooshSmall_OS_01", "whiz.wav", "highpass=f=400,atrim=0:0.4," + N(-22))
print("done")
