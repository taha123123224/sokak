# SOKAK: Operasyon — Dönüşüm Planı ve İlerleme

Son güncelleme: 18.11.2026. Kaynak: kullanıcının "Master Development Directive" belgesi (31 bölüm).
Çalışma kuralı: Önce en kötü harita referans kaliteye çıkarılıyor, sonra aynı standart diğerlerine uygulanıyor. Her tur:
1. Uygulama
2. Test: `map_check` ve oyuncu gözünden render
3. Yayın
4. Bu dosyanın güncellenmesi

## Tamamlanan turlar
| Sürüm | İçerik |
|---|---|
| v4.8 | Kereste doğuş hataları, helikopter atlayışı, harita çevreleri |
| v4.9 | 24 PBR set (Poly Haven), şehir/orman çevresi, silah malzemeleri, lobi |
| v4.10 | Haritaya özel oda kurma arka planı ve ortam sesi, zemine göre ayak sesi, REKABETÇİ grafik ayarı |
| **v4.11** | Denetim belgeleri; İnşaat sıfırdan yeniden tasarım; fotogrametri ağaç impostor'ları (tüm haritaların çevresi); 6 ana yüzey 4K'ya, 10 yeni doku seti; arazi kesme; afişler yalnızca Mahalle'de |

## Varlık edinme hattı (v4.11'de kuruldu)
Sunucunun ağı sanat sitelerine kapalı. Bu yüzden dosyalar şu yoldan geliyor:
1. Kullanıcının bilgisayarındaki Claude tarayıcısı Poly Haven API'sinden dosyaları çeker.
2. Dosyalar 40 MB'lık paketler hâlinde İndirilenler klasörüne düşer (`sokak_<etiket>.bin.NNN`).
3. Paketler buraya aktarılır ve `tools/unbundle.py` ile açılır.
4. Dokular `tools/import_ph_tex.py` ile, ağaçlar `tools/bake_impostors.py` ile işlenir.

İndirilenler klasöründeki `sokak_*.bin*` dosyaları işlendi; kullanıcı silebilir.

## Sıradaki işler (öncelik sırasıyla)
1. **Çanakkale** (P1): Osmanlı kıyı tabyası olarak yeniden tasarım (`defense_wall`, `withered_grass`, zeytin impostor'ları).
2. **Fabrika** (P1): Doğuş tarlası, endüstriyel zemin, saha dekoru.
3. **Gemi, Hurda, Çekirdek, Liman, Kereste** (P2/P3): MAP_DESIGN.md'deki şablonla tek tek.
4. **Mahalle, Safranbolu**: hafif render ayarıyla denetim, ardından düzeltmeler.
5. Harita içi ağaçlar: `maps.py` içindeki top biçimli ağaçların yerine impostor (gölgeli) sürümü.
6. **Silah rigi** (P1): Silah başına el bağlantı noktaları veri dosyası. Lisanslı birinci şahıs animasyon kaynağı araştırması.
7. **Ses** (P2): Sonniss GDC paketleri, iç/dış mekân yankı ayrımı.
8. Envanter, market, HUD tasarım sistemi geçişi (UI_DESIGN_SYSTEM.md).
9. "Ultra doku paketi": tüm setlerin 4K sürümü, isteğe bağlı ayrı indirme.

## Bilinen sınırlar
- Bu sunucuda 8 GB RAM var: 7.8 milyon üçgenli köknar modeli işlenemedi, yerine köknar fidanı seti kullanıldı. Mahalle ve Safranbolu "yüksek" kalitede render edilemiyor.
- Ücretli varlık satın alınmadı.
