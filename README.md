<p align="center"><img src="docs/img/emblem.png" width="120"><br><img src="docs/img/logo.png" width="420"></p>

<p align="center"><b>Türkiye'nin sokaklarında taktik çatışma — ücretsiz online FPS (Godot 4.5.1)</b></p>

<p align="center">
  <a href="https://raw.githubusercontent.com/taha123123224/sokak/main/indir/SOKAK_Kurulum.exe"><b>⬇ SOKAK_Kurulum.exe indir (Windows 10/11)</b></a> ·
  <a href="https://taha123123224.github.io/sokak/">Web sitesi</a>
</p>

## Depo düzeni

- `indir/SOKAK_Kurulum.exe` — Windows kurulum programı. Oyunu `%LOCALAPPDATA%\SOKAK` klasörüne kurar, güncel oyun paketini indirir, masaüstü ve Başlat menüsü kısayolu ekler.
- `version.json` — oyunun içindeki güncelleyicinin ve kurulum programının okuduğu sürüm bilgisi. Yeni sürüm yayınlanınca `build` artar; oyuncular giriş ekranında **GÜNCELLE** düğmesini görür. Hesap verileri bulutta kaldığı için kaybolmaz.
- `dist` dalı — oyun paketi (SOKAK_vNN.pck.partXX, 90 MB'lık parçalar).
- `docs/` — web sitesi (GitHub Pages).
- `src/` — kaynak kod (scriptler, araçlar, sunucu). Büyük model/doku/ses dosyaları depoda tutulmaz.
- `src/server/supabase/schema.sql` — hesap, arkadaş, davet, oda tabloları (Supabase).
- `src/server/relay/` — maç sunucusu (Cloudflare Workers + Durable Objects).
- `src/server/installer/` — kurulum programının NSIS betiği.
