# SOKAK: Operasyon — Kalite Denetimi

Son güncelleme: 18.11.2026 (v4.11 turu). Kanıtlar oyuncu gözü yüksekliğinden (1.75 m) çekilmiş
ekran görüntüleridir (`/tmp/fc_AUD_<harita>_{a,b}.png`, sabit kameralar: ilk doğuş noktasından
haritanın merkezine bakış). Mahalle ve Safranbolu bu sunucuda (8 GB RAM) zaman aşımına uğradığı için
ayrı turlarda daha hafif ayarla denetlenecek.

Önem: **P0** kritik / kırık · **P1** büyük kalite sorunu · **P2** belirgin iyileştirme · **P3** cila

## 1. Proje yapısı (doğrulandı)

| Alan | Gerçek durum |
|---|---|
| Motor | Godot 4.5.1, Vulkan Forward+ |
| Haritalar | 10 harita = `assets/maps/<id>.glb` + `<id>.json` (çarpışma kutuları, doğuşlar, ortam). 6'sı prosedürel (`tools/maps.py`, Blender bpy 5.2): Mahalle, Safranbolu, Gemi, Liman, İnşaat, Çanakkale. 4'ü dışarıdan dönüştürülmüş model (`tools/import_usdmap.py`): Kereste, Çekirdek, Hurda, Fabrika |
| Harita çevresi | `scripts/outskirts.gd` — arazi, deniz, şehir blokları, ağaçlar (helikopterden görülen alan) |
| Materyaller | `scripts/matlib.gd` — malzeme adına göre PBR seti (Poly Haven CC0) |
| Silahlar | 60 dünya modeli (`w_*.glb`), 34 birinci şahıs kol+silah modeli (`fp_*.glb` + `fp_*.json` şarjör çıkarma/takma zamanlaması) |
| El tutuşu | Botlar için `hand_grip.gd` (IK sonrası parmak bükme), birinci şahısta animasyonlu kol modelleri |
| Ses | 438 dosya; silah sesleri CC0 (Free Firearm Sound Library, GunLib), adım/ortam Oculus Audio Pack (CC BY), çarpma ve arayüz sesleri Kenney (CC0) |
| Arayüz | `ui.gd` tema, Barlow ailesi (OFL, Türkçe karakter tam) |

## 2. Haritalar

| Harita | Önem | Kanıt (oyuncu gözü) | Sorun | Çözüm | Durum |
|---|---|---|---|---|---|
| **İnşaat** | P0 | Boş beton meydan, ortada tek yarım bina, top biçimli kum yığınları, düz kutu arka plan binaları | Belirgin koridor/darboğaz yok, köşe doğuşlardan çapraz uzun görüş, tekrar eden kutular | **Sıfırdan yeniden tasarlandı (v4.11)**, bkz. MAP_DESIGN.md | ✅ v4.11 |
| **Çanakkale** | P1 | Doğuş: 7 m yüksek düz taş duvarla çevrili boş avlu, doku gerilmiş | Mimari kırılım yok (söve, mazgal, tabya formu), sahne boş | Osmanlı tabyası olarak yeniden tasarım; `defense_wall`, `withered_grass` setleri indirildi | Sırada |
| **Fabrika** | P1 | Doğuşta boş çimen tarla, çim dokusunda dikiş çizgileri | Dışarıdan gelen modelin açık alanı doldurulmamış | Doğuş bölgesi düzenlemesi, saha dekoru, çim → endüstriyel zemin | Sırada |
| **Gemi** | P2 | Düz güverte, konteynerler iyi | Güverte detayı az, oyunun kendi afişi güvertede | Güverte ekipmanı, ambar kapakları, babalar, halat | Sırada |
| **Hurda** | P2 | Düşük çözünürlüklü stilize dokular, hurda kimliği zayıf | Ezilmiş araç, lastik yığını, pres makinesi yok | Hurda dekoru + `rustsheet`, `mud` setleri | Sırada |
| **Çekirdek** | P2 | Bilim-kurgu "greeble" dokular, gürültülü | Sanat yönetimine (bugünün Türkiyesi) uymuyor | Kimlik: enerji santrali/çekirdek tesisi, doku değişimi | Sırada |
| **Liman** | P2 | Depo içi düzgün; raflar kalın turuncu plaka, sandıklar tekrar | Raf geometrisi gerçekçi değil | Raf sistemi yeniden, palet çeşitliliği | Sırada |
| **Kereste** | P3 | Tuğla binalar iyi; zemin ızgara taş (kereste sahasına uymuyor), doğuş kamerasında ağaç | Zemin malzemesi, kereste yığınları az | Toprak/talaş zemin, istif düzeni | Sırada |
| Mahalle | ? | — (render zaman aşımı) | v4.9'da cephe/doku yenilendi | Ayrı turda denetim | Bekliyor |
| Safranbolu | ? | — (render zaman aşımı) | v4.9'da yenilendi | Ayrı turda denetim | Bekliyor |

### Tüm haritaları etkileyen sorunlar
| Sorun | Önem | Çözüm | Durum |
|---|---|---|---|
| Oyunun kendi "ŞİMDİ OYNA" afişleri her haritaya rastgele 12 afiş + 4 dev pano olarak konuyor (gemi güvertesi, şantiye) | P1 | Sadece sokak reklamının gerçekçi olduğu Mahalle'de, az sayıda | v4.11 |
| Harita dışı ağaçlar: tek açıdan yapay zekâ görseli kartlar, ışık almıyor | P1 | Poly Haven fotogrametri ağaçlarından 8 açılı impostor + normal haritası | ✅ v4.11 |
| Arazi oyun alanının 35 cm altında tüm alanı kaplıyor → çukur/bodrum yapılamıyor | P1 | `terrain_holes` ile arazi kesme | ✅ v4.11 |
| İnşaat'ta oyun içi ortam sesi `amb_wind`, oda önizlemesinde `amb_site` | P3 | Oyun içi de `amb_site` | v4.11 |

## 3. Silah, el, animasyon
| Sorun | Önem | Kanıt | Öneri |
|---|---|---|---|
| Kol modeli tüm silahlarda aynı, tutuş konumu silah başına sabit ofset | P1 | `fp_*.json` yalnızca şarjör zamanlaması içeriyor, el bağlantı noktası tanımı yok | Veri odaklı silah rigi: sağ el, sol el, tetik, namlu, kovan çıkışı noktaları |
| Şarjör değiştirme zamanlaması var, sürgü/mekanizma animasyonu silaha göre değişmiyor | P2 | `reload.attach/mag_out/mag_in/bolt` alanları | Silah türüne göre ek olaylar |
| Lisans kontrolü gereken modeller | P1 | Kereste ve Çekirdek: "kullanıcının sağladığı model", lisansı kayıtlı değil; RPK-16 "Sketchfab Standard" | Kaynak sayfasından lisans teyidi; Standard lisans oyunda kullanım için uygun |

## 4. Ses
| Sorun | Önem | Öneri |
|---|---|---|
| Silah sesleri CC0 kütüphaneden; iç/dış mekân ve uzak atış varyasyonu sınırlı (`shotfar_*` var) | P2 | Sonniss GDC paketleri (ücretsiz, ticari kullanım serbest) — indirme için hesap/elle indirme gerekiyor |
| Yüzeye göre adım sesi v4.10'da eklendi; dışarıdan dönüştürülen haritalarda yüzey tanınmıyor | P2 | Atlas malzemelerine yüzey etiketi |

## 5. Performans (ölçülen)
İnşaat (v4.11), yüksek kalite, 1280×720: 340–380 bin üçgen, 640–810 çizim çağrısı (oyun içi `SHOT` günlüğü).
Sunucuda GPU yazılımsal olduğu için FPS değeri anlamlı değil; gerçek FPS kullanıcı makinesinde ölçülmeli.

## v4.13 (build 69) — sight-line pass on the remaining maps
| harita | önce (açık doğuş görüş hattı) | sonra | değişiklik |
|---|---|---|---|
| Gemi | 3 / 36 | 0 / 36 | -13 ve +31 ambar kapaklarına bağlı konteyner yığınları; vinç bomları kabine menteşeli (önceden havada asılıydı), kanca + halat + karşı ağırlık |
| Liman | 1 / 36 | 0 / 36 | depo kapısı ile konteyner sahası arasındaki batı koridoruna 2 katlı konteyner yığını |
| Çekirdek | 1 / 64 (mesh) | 0 / 64 | doğu terasına sandık yığını (dress katmanı, yanında geçiş boşluğu var) |
| Kereste | 0 / 64 (mesh) | — | değişiklik gerekmedi |
| Mahalle, Safranbolu, İnşaat, Çanakkale, Fabrika, Hurda | 0 | 0 | — |
