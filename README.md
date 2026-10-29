# SOKAK: Operasyon

Zula tarzı Türkçe FPS (Godot 4.5.1).

- `version.json` — oyunun içindeki güncelleyicinin okuduğu sürüm bilgisi. Yeni sürüm yayınlanınca `build` artar ve oyuncular giriş ekranında **GÜNCELLE** butonunu görür.
- Sürümler (SOKAK.pck) **Releases** bölümündedir.
- `src/` — oyunun kaynak kodu (scriptler, araçlar, sunucu). Büyük model/doku/ses dosyaları depoda tutulmaz.
- `src/server/supabase/schema.sql` — hesap, arkadaş, davet, oda tabloları (Supabase).
- `src/server/relay/` — maç sunucusu (Cloudflare Workers + Durable Objects).
