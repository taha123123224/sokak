# SOKAK: Operasyon — Varlık Kaynakları ve Lisanslar

v4.9 grafik yenilemesinde eklenen / değiştirilen varlıklar. (Önceki silah, ses ve model
kaynakları oyun içinde Ayarlar > Lisanslar bölümünde ve `scripts/gs.gd` CREDITS listesinde.)

## PBR dokular — Poly Haven (CC0 1.0, atıf gerekmez)

Kaynak: https://polyhaven.com — 2K (bazıları 1K) albedo + OpenGL normal + ARM (AO/pürüzlülük/metal),
bazılarında yükseklik haritası. Projede `assets/tex/<yerel_ad>_{albedo,normal,orm,height}.png`.
Oyun içi parlaklık eski renk ayarlarıyla uyumlu olsun diye albedo ortalaması eşitlendi;
`paintmetal`, `plaster`, `corrugated` dokuları oyunda renklendirildiği için gri tonlamaya çevrildi.

| Yerel ad | Poly Haven varlığı | Kullanım |
|---|---|---|
| asphalt | [asphalt_02](https://polyhaven.com/a/asphalt_02) | yollar |
| cobble | [cobblestone_floor_08](https://polyhaven.com/a/cobblestone_floor_08) | Arnavut kaldırımı |
| paver | [patterned_concrete_pavers](https://polyhaven.com/a/patterned_concrete_pavers) | kaldırım taşı |
| concrete | [concrete_floor_worn_001](https://polyhaven.com/a/concrete_floor_worn_001) | beton zemin, bordür |
| rawconc | [concrete_wall_004](https://polyhaven.com/a/concrete_wall_004) | çıplak beton, mikro detay normali |
| plaster | [painted_plaster_wall](https://polyhaven.com/a/painted_plaster_wall) | boyalı sıva cepheler |
| grass | [leafy_grass](https://polyhaven.com/a/leafy_grass) | çim |
| dirt | [forest_ground_04](https://polyhaven.com/a/forest_ground_04) | toprak |
| rockface | [rock_face_03](https://polyhaven.com/a/rock_face_03) | kayalıklar, dağ yamaçları |
| planks | [weathered_brown_planks](https://polyhaven.com/a/weathered_brown_planks) | tahta, sandık, palet |
| woodbeam | [rough_wood](https://polyhaven.com/a/rough_wood) | kereste, kalıp |
| deck | [wood_floor_deck](https://polyhaven.com/a/wood_floor_deck) | gemi güvertesi |
| corrugated | [corrugated_iron](https://polyhaven.com/a/corrugated_iron) | oluklu sac, konteyner, depo |
| paintmetal | [blue_metal_plate](https://polyhaven.com/a/blue_metal_plate) | boyalı metal |
| rooftiles | [clay_roof_tiles_02](https://polyhaven.com/a/clay_roof_tiles_02) | kiremit |
| sandbag | [hessian_230](https://polyhaven.com/a/hessian_230) | kum torbası, halat |
| gravel2 | [gravel_floor_02](https://polyhaven.com/a/gravel_floor_02) | çakıl |
| ashlar | [sandstone_blocks_05](https://polyhaven.com/a/sandstone_blocks_05) | kesme taş |
| rust | [rust_coarse_01](https://polyhaven.com/a/rust_coarse_01) | pas, inşaat demiri |
| snow | [snow_02](https://polyhaven.com/a/snow_02) | kar |
| sand | [coast_sand_01](https://polyhaven.com/a/coast_sand_01) | kum |
| diamondplate | [metal_plate](https://polyhaven.com/a/metal_plate) | tırtıklı sac, çelik zemin |

## Higgsfield ile üretilen görseller (kullanıcının Higgsfield hesabı, GPT Image 2.6)

| Dosya | İçerik |
|---|---|
| `assets/tex/trees_atlas.png` | 9 ağaç (3 ladin, 2 yapraklı + kavak, 3 zeytin), arka planı kaldırılmış, harita çevresi billboard ağaçları |
| `assets/tex/facade_hf.png` | tekrarlanabilir apartman cephesi (balkon, panjur, klima) — harita çevresi şehir binaları |

## Prosedürel (projede üretilen)

`assets/tex/micro_detail.png` (rawconc dokusundan yüksek geçiren filtre), `forest_canopy.png`, `facade_apt.png`.

## Geri alma

Değiştirilen eski dokuların kopyaları: `/home/claude/old_assets/v48_tex/` (geliştirme makinesi),
tüm proje yedeği: `/home/claude/backups/sokak_pre_gfx_v48.tgz`. Git'te `v4.8.0` sürümüne dönmek de yeterli.
