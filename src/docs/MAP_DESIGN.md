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

---

## ÇANAKKALE — Mecidiye Tabyası (v4.12, sıfırdan)

**Kimlik:** Boğaz kıyısındaki tarihî Osmanlı kıyı bataryası. Haritanın parçaları:
- Krupp kıyı toplarının bulunduğu, toprak traverslerle ayrılmış top mevzileri.
- Traverslerin içinden geçen tonozlu cephanelikler.
- Kireç taşından bir redüt (kale).
- Siper hattı, taş köy evi ve zeytinlik.

Gün batımı ışığı ve kıyıda 9 m'lik yamaç. Eski sürümdeki 7 m'lik düz duvarlı avlu, silindir kuleler ve küre kayalar kaldırıldı.

**Ölçek:** 112 × 92 m. 8'e 8 doğuş. Kuzey ve güney karargâhları birbirinin aynası (y = 0 ekseninde).

```
 y=+46 ┌─ A KARARGÂHI: çan çadırlar, sandık yığınları, 1.9 m kum torbası perdesi (y≈29.5) ───────┐
       │  zeytinlik │ siper ║ köy evi + avlu │  samanlık   KALE (redüt)   nöbet kulübesi │ BATARYA │ ≈ uçurum
       │  (3 sıra)  │ hattı ║ (2 oda)        │             N kapı → depo  │ batarya yolu   │ 4 top   │ ≈ Boğaz
       │            │ zikzak║                │             avlu + kuyu    │                │ 5 travers│
       │            │ trav. ║                │             S kapı → koğuş │                │ cephanelik│
 y=-46 └─ B KARARGÂHI (aynası) ───────────────────────────────────────────────────────────────┘
        x=-60        -46        -28              5 (kale merkezi)            32       44    52
```

**Rotalar**
1. **Doğu (batarya):**
   - Top mevzileri kuzey-güney dizilmiş. Her traversin içinden 2.6 m genişliğinde tonozlu cephanelik tüneli geçiyor; tüneller mevzileri birbirine bağlıyor.
   - Kapalı ve dar bir yakın çatışma şeridi. Batarya yolu tarafındaki alçak taş duvar bel hizasında siper sağlıyor.
2. **Orta (kale):**
   - Kuzey ve güney ana kapılar. Kapıdan girince karşıya depo/koğuş binası çıkıyor; kapıdan kapıya düz atış yok.
   - Batı ve doğu duvarlarında birer küçük kapı (poterne) var.
   - İç merdivenlerle 5 m'lik sur yürüyüşüne çıkılıyor; mazgallı korkuluk var. KB ve GD köşelerinde sekizgen burçlar.
3. **Batı:**
   - Kesintisiz siper: toprak set, kum torbası kret ve ahşap döşeme. İçinde dönüşümlü kum torbası traversleri var, yani siperin boyunca düz atış yapılamıyor.
   - Doğu setinde 3, batı setinde 2 çıkış. Uçlarda makineli tüfek yuvaları.
   - Siperin doğusunda iki odalı taş köy evi ve duvarlı avlu, batısında zeytinlik.

**Görüş kesiciler:** Batarya yolunda nöbet kulübeleri, köy evi ile kale arasında samanlıklar var. Her ikisi de ayna çift.

**Ölçüm:** açık doğuş görüş hattı **0 / 64** (eski sürümde 5 / 36), en yakın düşman doğuşu **71 m**, hatalı doğuş 0.

**Malzemeler:**

| Yüzey | Doku seti |
|---|---|
| Kale ve evler | `rustic_stone_wall_02` (4K, sıcak kireç taşı tonu) |
| Batarya kaplamaları | `defense_wall` |
| Traversler ve zemin | `withered_grass` |
| Kale avlusu | `cobblestone_floor_08` (4K) |
| Siper setleri | toprak |

Zeytin ağaçları Poly Haven fotogrametri impostor'larıyla çizildi. Harita içindeki ağaçlar gölge düşürüyor ve gövdeleri çarpışma kutusuna sahip (`imp_tree()` → map json `trees`).

**Teknik:**
- Kıyı yamacı için çevre denizi -9 m'ye indirildi (`outskirts.gd` teması).
- Yamacın altındaki arazi `terrain_holes` ile kesildi.

---

## FABRİKA — Paslı Fabrika (giydirme katmanı, v4.12)

**Durum:** Dışarıdan alınmış "Rust" modeli (frostychaos144, CC-BY 4.0). Model, kendi ağlarıyla çarpışan tek parça atlas meshlerden oluşuyor. Bu yüzden mimarisi parça parça değiştirilemiyor; yeni içerik bir **giydirme katmanı** olarak ekleniyor:
- Araç: `tools/dress.py`. Çıktısı `fabrika_dress.glb` ve `fabrika_dress.json`.
- Oyun bu dosyaları ana modelin üstüne yüklüyor. JSON'daki çarpışma kutuları, ağaçlar, doğuşlar ve gizlenecek parçalar ana harita verisiyle birleşiyor.

**Bulunan sorunlar (P0):**
- Doğuşlar otomatik dağıtılmış: iki takım karışık, bazıları çatıda, biri karanlık bir garajda.
- Kuzey apronda A ve B doğuşu 27 m arayla birbirini görüyordu.
- Batı tarlası ve güneydoğu çıkıntısı boştu.

**Yeni düzen:** Yerleşkenin uzun ekseni (33.7°) boyunca iki karşıt saha kuruldu; bölge merkezleri arası yaklaşık 90 m.

| Saha | Konum | İçerik |
|---|---|---|
| A — ham madde sahası | batı tarlası | 2 depolama tankı (9 m, merdiven kafesi ve tepe korkuluğu), 3 çelik bobin sırası, 2 HEB profil istifi, yerleşkeye bakan konteyner perdesi (biri 2 katlı), bekçi kulübesi |
| B — cüruf sahası | güneydoğu çıkıntısı | A'nın aynası, pas tonlu tanklar |

**Yerleştirme:** Her nesnenin taban alanı modele karşı dikey ışınlarla test ediliyor (ağaç, bina, kot farkı). Yer yoksa nesne 3.5 m çevrede boş alan arıyor ve modelin gerçek zemin kotuna oturtuluyor.

**Ölçüm (modelin kendi geometrisi + giydirme):** açık doğuş görüş hattı **0 / 64**, en yakın düşman doğuşu **93 m**.
