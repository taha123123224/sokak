# Hurda Sahası — Görsel Kalite Referansı (ölçüme dayalı)

Kaynak: `assets/maps/hurda.glb` (frostychaos144, CC-BY 4.0), `hurda.json`, `hurda_dress.{glb,json}`,
`scripts/match.gd` (_fix_imported_mats, MatLib.apply, _apply_baked_ao). Ölçüm aracı: `tools/glbstats` (scr/glbstats.py),
oyun içi kareler: `--match=hurda:tdm --quality=medium` (2026-11-18, 5 kamera; 2'si model içine düştü, 3'ü geçerli).

## 1. Ölçülen değerler

| metrik | Hurda | not |
|---|---|---|
| oynanabilir alan | 44 × 29 m = 1 276 m² | en küçük harita |
| üçgen (model + dress) | 109 k | |
| **üçgen / m²** | **85.5** | Gemi 15.6, İnşaat 15.1, Fabrika 9.1, Çekirdek 6.6 |
| ayrı mesh parçası | 118 (+47 dress) | her biri tanınabilir bir obje |
| ayrı malzeme | 27 | her objenin kendi atlası |
| doku çözünürlüğü | **26 / 26 doku 256 px** (gömülü JPG, toplam 634 KB) | kalite dokudan gelmiyor |
| normal / ORM haritası | yok (0 / 27) | sadece base color |
| ışık | `day` preset, sis 0.006 | net güneş gölgesi |
| çarpışma | modelin kendi meshi (trimesh), `nocol`: Decals, Clothes, Wood, plane1 | |

## 2. Neden iyi görünüyor (kanıt: oyun içi kareler `/tmp/hb_2,4,5.png`)

1. **Her obje elle modellenmiş, kendine özgü siluet:** hesco bariyerleri, projektörlü gözcü kuleleri, nervürlü konteynerler,
   korkuluklu ahşap merdiven, branda yığını, jeneratör, çit. Primitif kutu yok.
2. **Dokular elle boyanmış (baked) detay taşıyor:** kir, pas, kenar aşınması albedo'ya işlenmiş; 256 px olmasına rağmen
   tekrar eden desen yok çünkü her obje kendi UV atlasına sahip (tiling değil).
3. **Yoğunluk:** her 5–10 m'de bir siper; boş düz alan yok.
4. **Katmanlı kompozisyon:** ön plan (siper) → orta plan (konteyner yığınları) → arka plan (kuleler, vinçler, şehir).
5. **Tutarlı palet:** pas turuncusu, konteyner kırmızı/mavi, uyarı sarısı, ahşap kahve; zemin tek bir taş/döşeme.
6. **Hikâye objeleri:** çamaşır ipleri (Clothes), decal katmanı (yazı, leke), aydınlatma direkleri.
7. **Net sınır:** çevre duvar + çit; oyuncu nerede bittiğini görüyor.

## 3. Zayıf yanları (korunacak ama düzeltilebilir)
- Zemin dokusu 256 px → yakında bulanık (kare 2 ve 4). Yalnızca zemin için 2K PBR katman eklenebilir.
- Normal map yok; yakın plan düz.

## 4. Tüm haritalar için standart (Hurda'dan türetildi)

| alan | standart |
|---|---|
| büyük objeler (bina, araç, gemi, vinç, makine) | **gerçek, elle modellenmiş model**; primitif kutu/silindirden sahte obje yok |
| doku | obje başına UV atlas (tiling değil) veya tiling + kir/AO katmanı; görünür büyük yüzeyde ≥2K, kahraman objede 4K |
| yoğunluk | oyuncu yolunda her 5–10 m'de siper; doğuş-doğuş açık görüş 0 (map_check) |
| kompozisyon | ön / orta / arka plan katmanı + net harita sınırı |
| palet | harita başına 4–6 ana renk, aşınma ve kir ile birleşik |
| hikâye | her bölgede amaç belirten 2–3 obje (iş makinesi, kasa, çamaşır, tabela) |
| performans | harita başı ≤ 2 M üçgen görünür, küçük propta görünürlük mesafesi, tekrarlanan objede instancing |

## 5. Yeniden kullanılabilir
Lisans CC-BY 4.0 (frostychaos144) → atıf ile diğer haritalarda kullanılabilir: konteynerler, hesco bariyer, jeneratör,
projektör direği, kasalar, lastik. **Tema uyarısı:** Safranbolu, Mahalle, Çanakkale'ye hurda objesi konmaz.

## 6. Koruma
Hurda'nın `hurda.glb` dosyasına dokunulmaz. Sadece `hurda_dress` katmanı (v4.12) değişebilir; her değişiklikten sonra
görüş hattı ve oyuncu gözü kontrolü yapılır.
