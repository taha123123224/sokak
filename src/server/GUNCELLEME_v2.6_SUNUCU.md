# SOKAK v2.6 — Sunucu güncellemesi (1 dakika)

Bu sürümde değişen sunucu kuralları:
- **Rütbe sistemi (RP):** Maç sonunda rütbe puanı sunucuda hesaplanır.
  Kazanınca +18…31, kaybedince −8…14 RP. Dereceli online maçlar tam puan, bot maçları yarım puan verir.
- **Kasa silahları:** Silahlar artık kasalardan çok daha sık çıkıyor. Yeni **Silah Kasası**'nda şans %60 civarında.
  Kasadan çıkan silahlar çoğunlukla süreli olur (3/7/30 gün), nadiren süresiz.
- **Satın alınan silahlar her zaman süresizdir.**
- Yeni silahlar ve stiller katalogda: AWM, RPK-16, PP-19 Vityaz, Micro UZI, BR-7 Kuzgun, M1911 ve 12 yeni stil.

## 0) ÖNCE: kurucu (yönetici) hesabını aç
Oyunu güncelledikten sonra **Çevrimiçi** moda geç ve **"sokakoperasyon"** kullanıcı adıyla KAYIT OL
(şifreni kendin belirle). Bu adımı SQL'den ÖNCE yap: SQL, bu adla kayıtlı hesabı yönetici yapar.
Şifre oyun dosyalarında yoktur; yalnızca Supabase'in güvenli giriş sisteminde saklanır.
Eğer bu ad başkası tarafından alınmışsa: Supabase > Table Editor > profiles'tan o satırı sil, sonra kayıt ol.

Yönetici olunca üst menüde kırmızı **◆ YÖNETİM** sekmesi çıkar:
- GENEL: anlık çevrimiçi oyuncu, maçtaki oyuncu, açık oda, toplam hesap, bugünkü kayıt, yasaklı sayısı
- OYUNCULAR: ara, 1 saat / 1 gün / 7 gün / süresiz yasakla, yasağı kaldır, hesabı sil, hediye gönder
  (altın, malzeme, kasa, süreli/süresiz silah, stil + mesaj)
- DUYURU: tüm oyuncuların ekranında anında çıkan duyuru
- TOPLU HEDİYE: herkese aynı anda hediye

## 1) Supabase: SQL'i yeniden çalıştır
1. https://supabase.com → projen → **SQL Editor** → **New query**
2. `server/supabase/v2_guvenlik.sql` dosyasının **tamamını** yapıştır → **RUN**
3. "Success" görürsen tamam. Mevcut veriler silinmez.

## 2) Relay (Cloudflare)
`server/relay` klasöründe **KUR_relay.bat**'ı tekrar çalıştır.
Yeni silahların hasar tablosu güncellendi. Çalıştırmazsan yeni silahlarla online vuruşlar reddedilebilir.

Not: Supabase gizli anahtarını (sb_secret...) kimseyle paylaşma, oyuna da koyma.
