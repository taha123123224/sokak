# SOKAK performans testi (v4.18 altyapısı, v4.17.1 ile geldi)

## Oyun içinden
Ayarlar → Grafik → **PERFORMANS TESTİ**: "HIZLI TEST — Hurda, 60 sn" ya da "TAM TEST — tüm haritalar × 60 sn".
Seçili grafik profiliyle botlu bir takım maçında sabit kamera rotası (harita doğuş noktaları, her durakta 270° dönüş)
izlenir; 6 sn ısınmadan sonra 60 sn ölçülür. Ölçüm sırasında dinamik çözünürlük ve otomatik efekt düşürme kapalıdır,
oyuncu hasar almaz.

## Komut satırından (RTX 4050 profil karşılaştırması için)
```
SOKAK.exe -- --bench=all --bench-profile=high  --bench-time=60
SOKAK.exe -- --bench=all --bench-profile=ultra --bench-time=60
SOKAK.exe -- --bench=hurda,liman --bench-profile=uhd --bench-res=2560x1440
```
Profiller: low, medium, high, ultra, uhd (= EXTREME). Bitince oyun kapanır.

## Çıktı
`Belgeler\SOKAK_Benchmark\` ve `%APPDATA%\Godot\app_userdata\SOKAK- Operasyon\benchmarks\`:
- `bench_<harita>_<profil>_<tarih>.json` — GPU/CPU modeli, sürücü, işletim sistemi, RAM, harita, profil, pencere ve
  3D çizim çözünürlüğü, ölçekleyici, tüm grafik ayarları, ortalama FPS, %1 ve %0.1 düşük FPS, ortalama / medyan / p99 /
  en uzun kare süresi, Godot VRAM (anlık + tepe, doku + tampon), çizim çağrısı / nesne / üçgen sayısı.
- `benchmarks.csv` — her çalıştırma bir satır.

## VRAM notu
Godot yalnız kendi ayırdığı belleği (doku + tampon + diğer) raporlar; sürücü, Windows, ekran tamponları ve diğer
uygulamalar dahil değildir. Tam değer için test sırasında Görev Yöneticisi → Performans → GPU → "Ayrılmış GPU belleği"
ya da `nvidia-smi --query-gpu=memory.used --format=csv -l 1` ile birlikte ölçün.

## Bulut testi (geliştirme sunucusu)
Sunucuda ekran kartı yoktur (Vulkan 1.4 + llvmpipe, 2 çekirdek, 7 GB RAM). Burada yalnız aracın çalıştığı doğrulanır;
çıkan FPS (~1 FPS) gerçek donanım hakkında bilgi vermez. RTX 4050 sonuçları ayrı raporlanır.
