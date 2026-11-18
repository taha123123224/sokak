# SOKAK: Operasyon — Harita Tasarım Belgesi

Her harita bu belgede: kimlik, yerleşim planı, rotalar, görüş hatları, doğuş güvenliği, doğrulama.
Ortak doğrulama aracı: `python3 tools/map_check.py <id> --top out.png`. Araç şunları denetler:
- Doğuşlar arası açık görüş hattını göz yüksekliğinde (1.65 m), tüm çarpışma kutularına karşı ölçer.
- En yakın düşman doğuşuna olan mesafeyi verir.
- Bir çarpışma kutusunun içinde kalan ya da altında zemin olmayan doğuşları bulur.

Hedefler:
- Açık doğuş görüş hattı **0**.
- En yakın düşman doğuşu **≥ 45 m** (küçük harita).
- Hatalı doğuş **0**.

---

## İNŞAAT — "Kartal Konutları 2. Etap" şantiyesi (v4.11, sıfırdan)

**Kimlik:** Yapımı süren, 3 katlı betonarme konut bloğu olan çalışan bir Türk şantiyesi:
- Tuğla dolgu duvarlar, zemin katı yarı sıvanmış.
- Temel kazısı, kule vinç, çimento silosu.
- Şantiye ofisi olarak kullanılan konteynerler.
- Seyyar tuvaletler, agrega bölmeleri, sacla çevrili şantiye.

"Terk edilmiş beton bloklar" değil, işçilerin her gün çalıştığı bir yer.

**Ölçek:** 80 × 68 m (eskisi 68 × 60). 8'e 8 doğuş.

```
 y=+34  ┌───────────── hoarding (sac çit, şantiye afişleri) ─────────────┐
        │  A DOĞUŞ (y≈30) · arkasında konteyner ofis sırası y=23          │
        │  silo ●   malzeme  ·  kalıp istifi  ·  takım deposu (90°)       │
        │──────────────┬────────────────────────────┬─────────────────────│
        │  BLOK-A      │  ORTA: TEMEL ÇUKURU         │  KONTEYNER SOKAĞI   │
        │  3 kat RC    │  20×16 m, 2.6 m derin       │  x≈21.5             │
        │  x -36..-18  │  KB rampa (A'ya), GD rampa  │  BLOK-B 2 kat       │
        │  zemin kat:  │  (B'ye), KD çelik merdiven  │  x 26..38           │
        │  K-G koridor │  kule vinç ● (14,10)        │  prefabrik döşeme   │
        │  merdiven →  │                             │  sahası             │
        │  1.-2. kat   │                             │                     │
        │──────────────┴────────────────────────────┴─────────────────────│
        │  agrega bölmeleri (kum/çakıl) · bloklar · beton mikseri         │
        │  B DOĞUŞ (y≈-30) · önünde kulübe + park etmiş TIR (y=-25)       │
 y=-34  └─────────────── ana kapı (kapalı) ───────────────────────────────┘
```

**Rotalar**
1. **Batı (Blok-A):**
   - Zemin katta kuzeyden güneye kapalı koridor; doğu cephesinde iki geniş açıklık ortaya bakıyor.
   - Merdiven çekirdeğinden 1. ve 2. kata çıkılıyor. 1. katın doğu pencereleri ortaya ve çukura bakıyor (güçlü pozisyon).
   - Çatı erişime kapalı. Yarısı dökülmüş, yarısı kalıplı; filiz demirleri duruyor.
   - Batı arka sokağı 4 m genişliğinde; blok paletleriyle daraltılmış bir kanat yolu.
2. **Orta (temel çukuru):**
   - 2.6 m derin. Kuzeybatı rampası A tarafına, güneydoğu rampası B tarafına çıkıyor (dönel simetri). Kuzeydoğuda çelik merdiven var.
   - Çukurun içinde temel pabuçları, filiz kolonlar, etriyeli donatı kafesleri, plywood kalıp panelleri ve su bidonları siper oluşturuyor.
   - Çukurun kenarları New Jersey bariyeri ve sarı korkulukla çevrili.
3. **Doğu:**
   - Konteyner sokağı ve 2 katlı Blok-B (1. kat doğuya bakıyor).
   - Prefabrik döşeme istifleri bel hizasında siper.
   - Güneydoğuda 2 katlı konteyner yığını B'ye yakın.

**Güç pozisyonları (denge)**
- Her iki takım da Blok-A'ya kendi tarafındaki kapıdan girebiliyor.
- A tarafı: batı ofis konteynerinin çatısı (2.6 m, merdiven).
- B tarafı: kulübenin çatısı (2.6 m, merdiven). Konumlar simetrik.

**Doğuş güvenliği**
- A: ofis sırası, jeneratör ve tuvaletler x −13 ile +13 arasında kesintisiz bir duvar oluşturuyor.
- B: kulübe, TIR ve jersey bariyerleri aynı görevi görüyor.
- Batı ve doğu çaprazları malzeme deposu (−14, 15.5) ve 90° döndürülmüş takım deposu (16.5, 17.8) ile kapatıldı.
- **Ölçüm: açık doğuş görüş hattı 0 / 64, en yakın düşman doğuşu 59 m, hatalı doğuş 0.**

**Malzemeler (Poly Haven, CC0)**

| Yüzey | Doku seti |
|---|---|
| Zemin | `dry_ground_01` |
| Kamyon yolu ve rampalar | `muddy_tracks` (lastik izli çamur) |
| Çukur duvarları | `excavated_soil_wall` (kazı toprağı) |
| Zemin kat dolgu | `rough_plaster_brick_02` (yarı sıvalı tuğla) |
| Üst katlar | `red_brick_03` (4K) |
| Beton | `concrete_wall_004` (4K) |

**Teknik**
- Çukurun altındaki harita dışı arazi `terrain_holes` ile kesildi. Önceden arazi çukuru tavan gibi kapatıyordu.

**Kalan (sonraki tur):**
- Çukura ekskavatör (lisanslı model bulunursa).
- Blok-A iç mekânlarına daha fazla anlatı detayı.
- Gece veya akşam ışık varyantı.
