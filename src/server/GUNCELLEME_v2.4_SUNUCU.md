# SOKAK v2.4 — Sunucu güncellemesi (bir kez yapılır, ~3 dakika)

Bu sürümle oyunun ekonomisi (altın, malzeme, silahlar, kasa, yükseltme, maç ödülleri) **sunucuya** taşındı.
Hile programlarıyla (Cheat Engine vb.) para / silah / seviye değiştirmek ve mod paketiyle silah hasarını
yükseltip online maçta kullanmak artık işe yaramaz. Bunun için iki adım gerekiyor:

## 1) Supabase: güvenlik SQL'i
1. https://supabase.com → projen → sol menü **SQL Editor** → **New query**
2. `server/supabase/v2_guvenlik.sql` dosyasının **tamamını** kopyala, yapıştır → **RUN**
3. "Success. No rows returned" görürsen tamam.

Ne değişir?
- Oyuncular profillerindeki altın/malzeme/silah/seviye alanlarına doğrudan yazamaz.
- Satın alma, kasa açma, yükseltme, görev ve maç ödülleri yalnızca sunucudaki `sokak_act` fonksiyonuyla olur.
  Fiyatlar, kasa çekilişi, yükseltme şansı ve ödül sınırları sunucuda hesaplanır.
- Maç ödülü, maçın gerçek süresiyle sınırlıdır (dakikada en fazla 10 öldürme, maç başına en fazla 50).
- Yeni hesaplar sunucunun verdiği başlangıç profiliyle açılır.

Not: Bu SQL çalıştırılmadan da oyun çalışır (eski kayıt yöntemine geri döner) ama hile koruması olmaz.

## 2) Cloudflare: maç sunucusu (relay)
`server/relay` klasöründe daha önce kullandığın **KUR_relay.bat** dosyasını tekrar çalıştır
(veya o klasörde `npx wrangler deploy`). Yeni sürüm her vuruşu gerçek silah tablosuyla karşılaştırır:
- Silahın gerçek hasarından fazla gelen vuruşlar karşı oyuncuya ulaşmaz.
- Silahın atış hızından fazla vuruş gönderen oyuncu 6. ihlalde odadan atılır.

## Mevcut hesaplar
Eski sürümde hile yapılmış hesaplar varsa Supabase > Table Editor > profiles'tan o satırı silebilirsin
(veya oyuncu Ayarlar > Profil > PROFİLİ SIFIRLA ile sunucuda sıfırlayabilir).
