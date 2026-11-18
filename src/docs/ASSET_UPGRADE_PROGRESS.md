# Asset Upgrade — İlerleme

## Faz 0 — Proje ve çalışma ortamı (doğrulandı 2026-11-18)
- Godot 4.5.1, Forward+ (Vulkan). Haritalar: `assets/maps/<id>.glb + <id>.json` (+ isteğe bağlı `<id>_dress.{glb,json}`).
- Prosedürel haritalar `tools/maps.py` (bpy 5.2) ile üretilir: mahalle, safranbolu, insaat, canakkale, liman, gemi.
- İçe aktarılmış haritalar (mesh_collision): hurda, fabrika, kereste, cekirdek.
- Malzemeler: `scripts/matlib.gd` (isim → PBR tanımı, `assets/tex/*`), içe aktarılanlar `_fix_imported_mats`.
- Yükleme: `scripts/match.gd`; çevre: `scripts/outskirts.gd` (arazi, şehir, impostor ağaçlar).
- Yetenekler: terminal ✔, Blender (bpy) ✔, Godot headless + xvfb render ✔, ekran görüntüsü ✔.
  İnternet: sunucudan sanat sitelerine **yok**; kullanıcının bilgisayarındaki tarayıcı paneli üzerinden ✔
  (Poly Haven, Sketchfab API). Dosya aktarımı: Downloads klasörü → `device_stage_files`.
- Sketchfab indirme: hesap girişi gerekiyor → **BLOCKED (kullanıcı girişi bekleniyor)**.
- Disk: sunucuda ~2.9 GB boş → büyük arşivler parça parça işlenecek.

## Faz 1 — Benchmark: `docs/HURDA_SAHASI_ASSET_QUALITY_BENCHMARK.md` ✔

## Faz 2 — Harita denetimi (ölçüm: glbstats + map_check)

| harita | alan m² | üçgen/m² | malzeme | büyük objeler nasıl yapılmış | Hurda'ya göre ana fark | öncelik |
|---|---|---|---|---|---|---|
| Hurda | 1 276 | 85.5 | 27 | elle modellenmiş (CC-BY) | referans | — |
| Gemi | 5 248 | 15.6 | 29 | **gemi gövdesi, köprüüstü, vinçler primitif kutu/silindir** | sahte gemi; düşük yoğunluk | **P0** |
| Liman | 7 680 | 28.4 | 77 | depolar/vinç/forklift primitif; konteynerler prosedürel | gemi ve iş makineleri sahte | **P0** |
| İnşaat | 5 440 | 15.1 | 60 | iskele, vinç, iş makinesi primitif | iş makinesi yok/sahte | P1 |
| Mahalle | 11 200 | 156.5 | 111 | binalar prosedürel kutu + pencere | bina mimarisi ve araçlar sahte | P1 |
| Safranbolu | 10 816 | 140.9 | 41 | konaklar prosedürel | detay prosedürel | P1 |
| Çanakkale | 10 304 | 48.9 | 28 | tabya, top, çadır prosedürel (v4.12) | toplar primitif | P2 |
| Fabrika | 13 225 | 9.1 | 16 | içe aktarılmış (CC-BY) + dress | çok seyrek; makineler primitif dress | P2 |
| Kereste | 1 900 | 28.0 | 18 | içe aktarılmış | prop çeşitliliği az | P3 |
| Çekirdek | 8 455 | 6.6 | 73 | içe aktarılmış | seyrek | P3 |

Görsel denetim durumu: Hurda ✔ (oyun içi), Gemi ✔, Çanakkale ✔, Fabrika ✔, Hurda dress ✔, İnşaat ✔ (v4.11);
Mahalle, Safranbolu, Liman, Kereste, Çekirdek **bu tur için yeniden çekilmedi (NOT VERIFIED)**.

## Faz 3+ — Yürütme günlüğü
- 2026-11-18 19:10 Sketchfab API ile 24 kategori arandı → `docs/ASSET_RESEARCH_CATALOG.md`.
- 19:33 Sketchfab indirme yolu bulundu: Claude tarayıcı paneli (oturum açık) → blob → Downloads → stage. (Chrome'da kuruluş politikası indirmeleri sessizce engelliyor.)
- 19:35 İndirildi (DOWNLOADED): Container Ship 4K + 12 prop (bkz. ASSET_LIBRARY_AND_LICENSES.md).
- 20:10 **Gemi v4.14 — INTEGRATED + TESTED:** primitif gövde, köprüüstü, baş kasara, vinçler, ambar kutuları silindi; gerçek
  Container Ship (RM02) ×2.67 (gerçek 40 ft konteyner ölçüsü) yerleştirildi. Çarpışma modeli izliyor (ambar 0.12 m, yan geçit
  −1.73 m, köprüüstü bloğu, dalgakıran, baş omuzları). Model konteynerleri oynanış alanında silindi, kıçta arka plan olarak kaldı.
  Deniz seviyesi −10.5 m (gerçek fribord). Doğuş-doğuş açık görüş 0/64, en yakın düşman doğuşu 95 m.
  Oyun içi kareler: oyuncu gözü ×3, helikopter, sudan gövde (medium kalite) ✔.
