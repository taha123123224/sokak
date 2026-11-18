# Animasyon & Ses Kaynak Araştırması (2026-11-18)

Yöntem: her site kullanıcının bilgisayarındaki tarayıcı panelinden açıldı ve **sitenin kendi aramasıyla** tarandı
(sunucudan bu sitelere doğrudan erişim yok, proxy 403 veriyor). Sonuçlar sitelerin döndürdüğü gerçek kayıtlardır.
Ücretli hiçbir şey satın alınmadı.

## Özet karşılaştırma

| kaynak | ne bulundu (gerçek arama) | lisans / maliyet | format | erişim durumu | karar |
|---|---|---|---|---|---|
| **Mixamo** | "rifle" araması: **229 hareket** — Rifle Idle, Rifle Run, Rifle Walk, Rifle Crouch Walk, Rifle Crouch Backward Walk, Rifle Side Step, Rifle Death, Rifle Hit To Back, Rifle Kneel Hit To Back, Rifle Run To Dying, Firing Rifle (ayakta/yürürken/çömelik), Rifle Pull Out / Put Away, Grab Rifle From Back, Rifle Jump vb. | Ücretsiz, Adobe hesabıyla; oyunlarda ticari kullanım serbest (royalty-free) | FBX (Mixamo iskeleti) | arama açık; **indirme Adobe girişi istiyor — tarayıcı panelinde oturum YOK** | 3. şahıs lokomosyon/ölüm için EN İYİ kaynak. Kullanıcı girişi gerekiyor |
| **ActorCore** (Reallusion) | "rifle", "gun" aramaları: 0 sonuç; "Weapon Combat" kategorisi paketleri **$39.99–$129**, tek hareketler $1–$4.50 | ücretli | FBX/iClone | açık | ücretli → alınmadı |
| **Rokoko** Motion Library | 100 ücretsiz mocap (SuperAlloy 50 ücretsiz) — kütüphane **yalnız Rokoko Studio masaüstü uygulamasından** aranabiliyor, web araması yok | ücretsiz hesap + uygulama | FBX/BVH | web'den içerik aranamadı | **NOT VERIFIED** (uygulama + hesap gerekir) |
| **Cascadeur** | animasyon aracı (içerik kütüphanesi değil). Free: yalnız **ticari olmayan** kullanım, FBX dışa aktarma YOK; Indie ₺302/ay; Pro ₺1248/ay | ücretli (ticari) | .casc / FBX | açık | ticari projede ücretsiz sürüm kullanılamaz → kullanılmadı |
| **Blender** | araç; projede bpy 5.2.3 kurulu, tüm retarget/rig işleri bununla yapılıyor | GPL, ücretsiz | — | kurulu ✔ | KULLANILIYOR |
| **Fab** (ücretsiz filtre, "fps animations") | Knife FPS Animations, **M4 FPS Weapon Animations Pack FREE** (zaten oyunda, Sketchfab sürümü), **FPS Animation Pack_AKS74U** (y0ung001), Free FPS Pack, Super Simple FPS Pack, FPS Weapon Bundle (Deadghost), Advanced Locomotion System V4 | ücretsiz Standart Lisans | **yalnız Unreal Engine** (AKS74U listesinde "İçerdiği biçimler: Unreal Engine") | Epic girişi gerekir | Godot'a doğrudan aktarılamıyor → kullanılmadı |
| **Sketchfab** | animasyonlu FP paketleri (CC-BY): **FPS Character Animation Pack Ak-47** (DuqueCD7, 11 anim), **FPS Character Animation Pack Pistol** (DuqueCD7, 11 anim), **Animated FPS hands (rifle animation pack)** (ccransh, 8 anim), FPS pistol animations (ccransh, 5), FPS Benelli M4 Animations (ccransh, 8), FPS animations sniper rifle (ccransh, 6), Makarov PM FPS animations (ccransh, 5), Animated AKs-74u (dan741vlasov, 7), AKM FPS ANIMATION (Alexander_Ovelar), bumstrum/DJMaesen serisi (fps AK, heavy pistol, shotgun, smg9, revolver, pistol) | CC-BY 4.0 (atıf) | glb | oturum açık ✔ | **İNDİRİLDİ**: DuqueCD7 AK, DuqueCD7 Pistol, ccransh rifle |
| **Sonniss GDC 2026** | 7.47 GB, 5 parça; parça listesi tarandı: **ateşli silah kaydı yok** (Historical/Melee Weapons, Cartoon/Colossal Impacts, "Shooter Game Announcer — Headshot", Paintball ambiyans) | royalty-free, ticari, atıfsız; AI eğitimi yasak | WAV | açık ✔ | silah sesi için uygun değil |
| **Sonniss GDC Arşivi** | 2015–2024 (2025 yok). 2023 listesi: Glock 17 (Pole Position, 2 dosya), Black Powder Guns, Footstep (RYK-Sounds). **2020 listesi (14 parça, 48.2 GB): Pole Position — Colt M1911A1, Mauser K98k, MG 42, MP 40, Mosin Nagant M38, Springfield 1903A3, Thompson 1928A1, PPSh-41, TT-33, Walther P38; Olivier Girardot — Hand Guns Sound Effects Pack; PMSFX — Bullet Bys & Impacts (gövde, cam, toprak, vızıltı); SculpTunes — Cartridges & Casings; Wav Junction — Shotguns, Footsteps; aXLsound — Metal Sweeteners (gun hyper realism); Super Thump — Weapons of WWII Designed** | royalty-free, ticari, atıfsız | WAV 24-bit | açık ✔ (indirme tarayıcıdan) | **SEÇİLDİ — GDC 2020 Part 8 indiriliyor** |
| **Sonniss Store** | Pole Position, BOOM vb. tam kütüphaneler | ücretli | WAV | açık | alınmadı |
| **Freesound** (CC0 filtresi) | rifle gunshot: felix.blume #710084, #136399 (AK47 atış poligonu, 48 kHz/24 bit WAV); ak47: qubodup #184750, acidsnowflake #402791 (kapalı alan), serøutōnin #675008 (AK kurma ×3), kaniaplania #507048 (AK kovanı karo zemin); pistol: acidsnowflake #402789 (kapalı alan), michorvath #427598; bolt: Zott820 #370345 (Mosin), Pjkasinski3 #171703 (Rem 700), AugustSandberg #508747; shell casing: GryffDavid #318964, GrayJoy #210102, NicJonesAudio #347603; footsteps concrete: SecureSubset #813622, florianreichelt #459964; body fall: leonelmail #504626 (dirt), jmdh #181177 | CC0 | WAV/FLAC | **orijinal dosya indirme girişi istiyor**; önizleme (mp3) açık | yedek kaynak (giriş yapılırsa WAV) |
| **BOOM Library** | "gun" araması: TACTICAL GUNS (25 silah), GUNS, ASSAULT WEAPONS, BOOM ONE gun mechanics — hepsi **ücretli** (şu an 3-al-2-öde); ücretsiz aylık paket e-posta bülteniyle | ücretli | WAV | açık | alınmadı |
| **Pixabay** Sound Effects | "gunshot": 17 sayfa; çoğu "freesound_community" yeniden yüklemesi (Single Gunshot 5.4, Rifle Gunshot, AKM Gunshot — Ahsbt, Distant Gunshots — DRAGON-STUDIO, Silenced Gunshot) | Pixabay Content License (ücretsiz, ticari) | **yalnız MP3** | açık | kalite/format zayıf → yedek |

## Seçim gerekçesi
- **Silah sesleri:** Sonniss GDC 2020 (gerçek silah kayıtları, çok mesafeli mikrofon, 24-bit WAV, atıfsız ticari lisans).
  Freesound CC0 WAV'lar giriş sonrası tamamlayıcı. Pixabay yalnız MP3 → elendi.
- **Birinci şahıs animasyon:** Sketchfab CC-BY paketleri (glb, Godot'a doğrudan, oyunda zaten aynı boru hattı `tools/rig_fp.py`).
  Fab FP paketleri yalnız Unreal → elendi.
- **Üçüncü şahıs karakter animasyonu:** Mixamo (229 tüfek hareketi; lokomosyon, çömelme, yan adım, ölüm, vurulma).
  ActorCore ücretli, Rokoko uygulama gerektiriyor, Cascadeur ücretsiz sürümü ticari değil.

## Engeller
- Mixamo: kullanıcı Adobe hesabıyla giriş yaptı ✔ (22:55)
- Freesound: kullanıcı giriş yaptı ✔ (22:00)
- Rokoko: Rokoko Studio uygulaması + hesap gerekir — **yapılmadı**.

## İndirme / entegrasyon durumu (2026-11-18)

### Üçüncü şahıs — Mixamo "Pro Rifle Pack" (X Bot, 49 klip) — DOWNLOADED → INTEGRATED
`/home/claude/src_assets/mixamo/pro_rifle/*.fbx` → `tools/rocketbox.py` (`load_pack` + `retarget_pack`) → 8 karakterin
`assets/models/rb_*.glb` dosyasına 25 klip: R_Idle, R_IdleAim, R_Walk/Run F·B·L·R, R_Sprint, R_CrouchIdle/Aim, R_Crouch F·B·L·R,
R_JumpUp/Loop/Down, R_DeathFront/Back/Right/Head/Crouch. `scripts/bot.gd`: yöne göre klip seçimi (`_pack_locomotion`),
yön/headshot/çömelmeye göre ölüm klibi → 0.18–0.32 s sonra ragdoll'a devir; ragdoll kapalıysa klip sonuna kadar oynar.
Lisans: Mixamo (Adobe) — ücretsiz, oyunlarda ticari kullanım serbest; ham animasyon dosyası olarak yeniden dağıtılamaz
(oyun içine gömülü kullanım serbest).

### Birinci şahıs — Sketchfab
| paket | yaratıcı | lisans | durum |
|---|---|---|---|
| FPS Character Animation Pack Ak-47 (b95778a5…) | DuqueCD7 | CC-BY 4.0 | DOWNLOADED → INTEGRATED (AK-47: draw/idle/fire/reload/ads_idle/ads_fire/walk/sprint) |
| FPS Character Animation Pack Pistol (e2815a5b…) | DuqueCD7 | CC-BY 4.0 | DOWNLOADED (entegrasyon sırada) |
| Animated FPS hands (rifle animation pack) (5f2d0ed7…) | ccransh | CC-BY 4.0 | DOWNLOADED (entegrasyon sırada) |

### Ses — `tools/build_sfx4.py` → `assets/sfx` (eski dosyalar `/home/claude/old_assets/sfx_v415/`)
| oyun sesi | kaynak |
|---|---|
| shot_ak (+v1,v2) | Freesound #136399 felix.blume — AK47 atış poligonu (CC0) |
| shot_akm (+v1,v2) | Freesound #184750 qubodup — AK-47 (CC0) |
| shotfar_ak, shotfar_akm | Freesound #201669 Franki-01234 — AK47 down the block (CC0) |
| shot_sniper (+v1), shot_awm (+v1) | Sonniss GDC 2020 — Pole Position "Springfield 1903A3, Firing 1m" |
| shot_kar | Freesound #710084 felix.blume — rifle gunshot (CC0) |
| shot_pistol (+v1,v2), shot_usp, shot_m1911 | Freesound #668348 DeltaCode, #402789 acidsnowflake (kapalı alan), #427598 michorvath (CC0) |
| shot_smg (+v1,v2) | Sonniss GDC 2020 — Pole Position "Thompson 1928A1 burst" |
| shot_sup | Freesound #539141 SubwaySandwitch420 — suppressed rifle (CC0) |
| bolt_back, bolt_fwd | Sonniss GDC 2020 — "M1903A3 Handling, Cycling Bolt" |
| dryfire | Sonniss GDC 2020 — "1928A1 Handling, Dry Fire" |
| shell0-2 | Freesound #318964 GryffDavid — bouncing shell casings (CC0) |
| bodyfall | Freesound #181177 jmdh (CC0) |
| step_concrete0-3 | Freesound #813622 SecureSubset (CC0) |
İndirildi, henüz kullanılmadı: #675008 AK kurma, #370345 Mosin bolt, #171703 Rem700 bolt, #508747 bolt reload, #431830 şarjöre
mermi, #507048 AK kovanı karo, #620929 pompalı kovanları, #459964 adım beton, #504626 toprağa düşme, #627087 susturuculu tabanca,
#402791 AK kapalı alan, #710084. Sonniss GDC 2020 Part 7 (M1911, K98k, MP40, MG42, PMSFX mermi çarpma, SculpTunes kovan) indiriliyor.

