# SOKAK: Operasyon — Sanat Yönetimi

Son güncelleme: 18.11.2026 (v4.11 turu)

Bu belge oyunun tek bir görsel dünyaya ait olması için kuralları tanımlar. Her yeni varlık, harita ve
arayüz ekranı bu kurallara göre değerlendirilir. Kuralı çiğneyen varlık ya düzeltilir ya da kullanılmaz.

## 1. Kimlik

**Bugünün Türkiyesi, sahada.** Gerçekçi, ama okunaklı. Taktik ve sade. Fantastik, bilim-kurgu ya da
"Avrupa şehri" görüntüsü yok. Mekânlar Türkiye'de var olabilecek yerler: mahalle arası, liman,
şantiye, kereste fabrikası, hurdalık, tarihi Safranbolu sokağı, Çanakkale kıyısı.

Kalite referansı CS2'dir (netlik, okunaklılık, materyal ciddiyeti), varlık kaynağı değildir.
CS2'den ya da başka bir oyundan hiçbir model, doku, ses kullanılmaz.

## 2. Gerçekçilik seviyesi

| Alan | Hedef |
|---|---|
| Materyaller | Fiziksel tabanlı (PBR). Poly Haven CC0 setleri ana kaynak. Albedo orta tonda tutulur (0.18–0.55 parlaklık), saf siyah / saf beyaz yok. |
| Geometri | Gerçek ölçek: kat yüksekliği 3.0–3.6 m, kapı 2.1×0.9 m, korkuluk 1.0–1.1 m, basamak 17–18 cm. Duvar kalınlığı en az 0.2 m. |
| Detay yoğunluğu | Savaş alanında orta, kenarlarda düşük. Oyuncunun baktığı yerde (köşe, kapı, siper) en yüksek. |
| Eskime | Her yüzeyde var ama hafif: kir, pas, boya dökülmesi. "Terk edilmiş harabe" değil, "kullanılan yer". |

## 3. Renk sistemi

### Dünya
- **Nötr taban:** beton grisi, sıva kırık beyazı, asfalt koyu gri. Haritanın %70'i.
- **Bölgesel renk:** her haritanın kendi 1–2 vurgu rengi (aşağıda). %20.
- **Oyun işaretleri:** sarı-siyah güvenlik şeridi, turuncu koni, kırmızı yangın tüpü. %5'ten az; oyuncuyu yönlendirmek için.
- Doygunluk sınırı: varsayılan renk paketi "dogal" (kontrast 1.07, doygunluk 1.0). "Canlı" paket isteğe bağlı.

### Harita vurguları
| Harita | Vurgu | Işık | Atmosfer |
|---|---|---|---|
| Mahalle | Sıva pastelleri (krem, açık pembe, açık yeşil), tabela renkleri | Öğle güneşi | Açık gökyüzü |
| Liman | Konteyner kırmızısı / mavisi, vinç sarısı | Bulutlu | Deniz sisi |
| Gemi | Gövde kırmızısı, güverte yeşili, beyaz üst yapı | Gün batımı | Düşük sis |
| İnşaat | Kalıp tahtası sarısı, iskele turuncusu, çıplak beton | Öğleden sonra | Hafif toz |
| Fabrika | Pas turuncusu, endüstriyel yeşil | Bulutlu | Kapalı |
| Hurda | Pas, solmuş araba boyaları | Gündüz | Tozlu |
| Kereste | Ham ahşap sarısı, talaş | Altın saat | Sıcak |
| Safranbolu | Beyaz badana, koyu ahşap, kiremit kırmızısı | Gündüz | Açık |
| Çanakkale | Taş, kum, deniz mavisi | Altın saat | Kıyı sisi |
| Çekirdek | Endüstriyel mavi, beyaz panel | Bulutlu | Temiz |

### Takımlar
- KARTAL (A): `#3d8bff` mavi
- AKREP (B): `#ff4d3d` kırmızı
- Takım rengi dünyada kullanılmaz (bayrak ve doğuş işaretleri hariç), böylece düşman siluetiyle karışmaz.

### Arayüz
- Vurgu: `#ff8a1f` turuncu, ikinci vurgu `#ffb347`
- Zemin: füme cam `rgba(14,15,18,0.84)`, ince beyaz çizgi `rgba(255,255,255,0.10)`
- Metin `#ebedf2`, sönük metin `#a1a6ad`
- Durum: başarı `#38e07b`, uyarı `#ffc23d`, hata `#ff3b3b`
- Nadirlik: Sıradan `#9aa4ad`, Nadir `#3b8cff`, Epik `#b04bff`, Efsanevi `#ffb02e`

## 4. Tipografi
Tek aile: **Barlow** (OFL, Türkçe karakterler tam: ç ğ ı İ ö ş ü).
- Başlık / büyük sayılar: Barlow Condensed ExtraBold
- Başlık 2 / düğme: Barlow Semi Condensed Bold
- Gövde / etiket: Barlow Semi Condensed SemiBold / Medium
Rajdhani, Russo One ve Teko dosyaları eski çağrılar için duruyor ama `UI.FONT_MAP` hepsini Barlow'a yönlendiriyor.

## 5. Mimari dil (haritalar)

**Türk kentsel yapısı:** betonarme karkas, tuğla dolgu, sıvalı cephe, çıkma balkonlar,
alüminyum doğrama, panjur yok (Safranbolu hariç), çatıda su deposu ve çanak anten, zemin katta dükkân
ve kepenk, Türkçe tabela. Kaldırım bordürü yüksek (15–20 cm), elektrik direği ve havai hat.

**Safranbolu:** taş zemin kat, üstte ahşap çatkı (bağdadi) beyaz badanalı katlar, çıkmalar, geniş saçak,
kiremit çatı, ahşap kapı ve kafes pencere.

**Endüstri (Liman, Fabrika, Kereste, Hurda, İnşaat):** çelik karkas, oluklu sac, beton zemin,
güvenlik boyaları, yangın merdivenleri, aydınlatma direkleri.

Kurallar:
- Düz bir kutuya doku basıp "bina" demek yok: pencere girintisi, söve, döşeme kirişi, saçak gibi en az 3 kırılım.
- Aynı bina modeli renk ve kat sayısı değiştirilmeden tekrar edilmez.
- Havada duran parça yok; her şey bir şeyin üstünde duruyor.
- Haritanın içine oyunun kendi afişi ya da logosu konmaz (dünyanın parçası değil, reklam gibi duruyor).

## 6. Işık
- Bir ana güneş + gökyüzü ortam ışığı + yerel ışıklar (sokak lambası, iç mekân floresan, endüstriyel projektör).
- Gölgeler her zaman açık; iç mekânlar en az %25 ortam ışığı alır, simsiyah köşe yok (rekabetçi okunaklılık).
- Parlama (glow) düşük. Alan derinliği (DOF) oyun içinde yok.

## 7. Silahlar ve karakterler
- Metal metal gibi parlar (pürüzlülük 0.3–0.5), polimer mat (0.6–0.8), lastik çok mat (0.85+), ahşap yarı mat.
- Tek materyal tüm silaha basılmaz.
- Kaplamalar: desen UV'ye oturur, gerilmez; sadece renk değiştirmek "kaplama" sayılmaz.
- Karakter: modern Türk özel kuvvet (KARTAL) ve düzensiz silahlı grup (AKREP). Kask, yelek, eldiven, dizlik.

## 8. Varlık kabul ölçütü (ağırlıklı puan)
| Ölçüt | Ağırlık |
|---|---:|
| Görsel kalite | %30 |
| Sanat yönetimine uyum | %20 |
| Teknik kalite (UV, normal, ölçek, poligon) | %15 |
| Oyun içi performans | %15 |
| Oynanışa katkı | %10 |
| Lisans uygunluğu | %10 — **geçti/kaldı**: ticari kullanıma izin vermeyen varlık puanı ne olursa olsun alınmaz |
