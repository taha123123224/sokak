"""Replace the synthesized placeholder sounds with real recordings (v2.9.9).
Sources (all free to use):
  * Kenney "Impact Sounds", "Interface Sounds", "UI Audio" - CC0 (kenney.nl), via the GitHub mirrors
    Boyquotes/kenney-impact-sounds-for-godot, Calinou/kenney-interface-sounds, Calinou/kenney-ui-audio
  * Music by Tanner Helland - CC-BY 4.0 (github.com/tannerhelland/free-music)
Each clip is trimmed, EQ'd and loudness-matched with ffmpeg so it sits with the CC0 gunshots.
python3 tools/build_sfx2.py
"""
import os, subprocess, shutil
E = "/home/claude/ext_audio/"
IMP = E + "impact/addons/" + os.listdir(E + "impact/addons")[0] + "/"
IF = E + "kenney-interface-sounds/addons/kenney_interface_sounds/"
UI = E + "kenney-ui-audio/addons/kenney_ui_audio/"
MUS = E + "free-music/ogg/"
OUT = "/home/claude/sokak/assets/sfx/"
BAK = "/home/claude/old_assets/sfx_synth/"
os.makedirs(BAK, exist_ok=True)
for d in (IMP, IF, UI):
    if not os.path.isdir(d):
        import glob
        print("missing", d, glob.glob(os.path.dirname(d.rstrip('/')) + "/*"))

def ff(src, dst, af="", ss=None, t=None, mono=True, rate=44100, codec=None):
    if os.path.exists(OUT + dst) and not os.path.exists(BAK + dst):
        shutil.copy(OUT + dst, BAK + dst)
    cmd = ["ffmpeg", "-v", "error", "-y"]
    if ss is not None: cmd += ["-ss", str(ss)]
    if t is not None: cmd += ["-t", str(t)]
    cmd += ["-i", src]
    if af: cmd += ["-af", af]
    cmd += ["-ac", "1" if mono else "2", "-ar", str(rate)]
    if codec: cmd += ["-c:a", codec]
    cmd += [OUT + dst]
    subprocess.run(cmd, check=True)

def norm(lufs, peak=-1.0):
    return f"loudnorm=I={lufs}:TP={peak}:LRA=11"

# ---------- footsteps (boots on concrete / wood; metal from light plate hits) ----------
for i in range(4):
    ff(IMP + f"footstep_concrete_00{i}.ogg", f"step_concrete{i}.wav", "highpass=f=60,equalizer=f=140:t=q:w=1:g=4,equalizer=f=3500:t=q:w=1:g=-3," + norm(-20))
    ff(IMP + f"footstep_wood_00{i}.ogg", f"step_wood{i}.wav", "highpass=f=60,equalizer=f=160:t=q:w=1:g=3," + norm(-20))
    ff(IMP + f"impact_plate_light_00{i}.ogg", f"step_metal{i}.wav", "highpass=f=80,lowpass=f=6000,afade=t=out:st=0.18:d=0.12," + norm(-22), t=0.32)
ff(IMP + "impact_soft_heavy_000.ogg", "land.wav", "highpass=f=40,equalizer=f=110:t=q:w=1:g=5," + norm(-18))
# body hitting the ground
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", IMP + "impact_punch_heavy_001.ogg", "-i", IMP + "impact_soft_heavy_002.ogg",
                "-filter_complex", "[1]adelay=90[b];[0][b]amix=inputs=2:normalize=0,highpass=f=40,equalizer=f=120:t=q:w=1:g=4," + norm(-17),
                "-ac", "1", "-ar", "44100", OUT + "bodyfall.wav"], check=True)

# ---------- bullet impacts ----------
for i in range(3):
    ff(IMP + f"impact_mining_00{i}.ogg", f"imp_concrete{i}.wav", "highpass=f=200," + norm(-19))
    ff(IMP + f"impact_metal_light_00{i}.ogg", f"imp_metal{i}.wav", "highpass=f=250," + norm(-19))
    ff(IMP + f"impact_wood_light_00{i}.ogg", f"imp_wood{i}.wav", "highpass=f=150," + norm(-19))
    ff(IMP + f"impact_punch_medium_00{i}.ogg", f"imp_flesh{i}.wav", "lowpass=f=5000," + norm(-18))

# ---------- feedback: hit, headshot "tink", kill, damage ----------
ff(IF + "tick_002.wav", "hitmarker.wav", "highpass=f=900," + norm(-16), t=0.12)
# headshot: helmet tink = light metal ping + bell overtone, short
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", IMP + "impact_metal_light_003.ogg", "-i", IMP + "impact_bell_heavy_001.ogg",
                "-filter_complex", "[0]highpass=f=1200[a];[1]highpass=f=1800,volume=0.35,afade=t=out:st=0.15:d=0.35[b];[a][b]amix=inputs=2:normalize=0," + norm(-14),
                "-t", "0.6", "-ac", "1", "-ar", "44100", OUT + "headshot.wav"], check=True)
ff(IF + "confirmation_002.wav", "kill.wav", "highpass=f=300," + norm(-15))
ff(IMP + "impact_punch_heavy_002.ogg", "hurt.wav", "lowpass=f=3000,equalizer=f=90:t=q:w=1:g=5," + norm(-16))

# ---------- interface ----------
ff(UI + "click3.wav", "ui_click.wav", norm(-20))
ff(UI + "rollover2.wav", "ui_hover.wav", norm(-26))
ff(IF + "back_002.wav", "ui_back.wav", norm(-20))
ff(IF + "confirmation_001.wav", "buy.wav", norm(-17))
ff(IF + "confirmation_004.wav", "success.wav", norm(-17))
ff(IF + "error_004.wav", "fail.wav", norm(-18))
ff(IF + "tick_001.wav", "tick.wav", norm(-20))
ff(IF + "select_005.wav", "beep.wav", norm(-17))
ff(IF + "maximize_006.wav", "beep_go.wav", norm(-15))
ff(IF + "pluck_002.wav", "medal.wav", norm(-15))
ff(IF + "glass_004.wav", "multikill.wav", norm(-14))
ff(IMP + "impact_tin_medium_001.ogg", "bounce.wav", "highpass=f=300," + norm(-19))

# ---------- music (CC-BY 4.0, Tanner Helland) ----------
for src, dst, ss, t in [("King of the Desert.ogg", "music_menu.ogg", None, None),
                        ("Retribution.ogg", "music_match.ogg", None, None)]:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", MUS + src, "-af", norm(-18, -1.5), "-ac", "2", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", OUT + dst], check=True)
# round won / lost stingers cut from the same composer's tracks
subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "40", "-t", "5", "-i", MUS + "Thugs.ogg", "-af", "afade=t=in:d=0.05,afade=t=out:st=3.6:d=1.4," + norm(-14), "-ac", "2", "-ar", "44100", OUT + "music_win.wav"], check=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "8", "-t", "5", "-i", MUS + "Destiny.ogg", "-af", "afade=t=in:d=0.3,afade=t=out:st=3.4:d=1.6," + norm(-16), "-ac", "2", "-ar", "44100", OUT + "music_lose.wav"], check=True)
for old in ["music_menu.wav", "music_match.wav"]:
    if os.path.exists(OUT + old):
        shutil.move(OUT + old, BAK + old)
        if os.path.exists(OUT + old + ".import"):
            os.remove(OUT + old + ".import")
print("done")
