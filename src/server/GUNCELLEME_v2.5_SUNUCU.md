# SOKAK v2.5 — Sunucu güncellemesi (1 dakika)

Bu sürüm **süreli kasa silahlarını** getiriyor. Kasadan çıkan silah artık
SÜRESİZ (%15), 30 GÜN, 7 GÜN veya 3 GÜN olabilir. Süresi biten silah envanterden düşer
ama seviyesi ve stilleri saklanır; tekrar çıkarsa / satın alınırsa geri gelir.
Süreli bir silahı markette satın almak onu süresiz yapar.

## 1) Supabase: SQL'i yeniden çalıştır
1. https://supabase.com → projen → **SQL Editor** → **New query**
2. `server/supabase/v2_guvenlik.sql` dosyasının **tamamını** yapıştır → **RUN**
3. "Success" görürsen tamam. (Eski veriler silinmez; sadece fonksiyonlar güncellenir.)

Bu adım yapılmazsa eski kasa kuralları geçerli kalır (silahlar hep süresiz çıkar).

## 2) Relay (Cloudflare)
`server/relay` klasöründe **KUR_relay.bat**'ı tekrar çalıştır. Silah tablosu yeni
silahlarla (Remington 870, FN 502) güncellendi; çalıştırmazsan bu iki silahla online
vuruşlar sunucu tarafından reddedilebilir.

Not: Supabase gizli anahtarını (sb_secret...) kimseyle paylaşma, oyuna da koyma.
