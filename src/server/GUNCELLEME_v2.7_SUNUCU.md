# SOKAK v2.7 — Sunucu güncellemesi (2 dakika)

Bu sürümde sunucu tarafında değişenler:
- **Yönetim paneli hatası düzeldi** ("invalid input syntax for type integer: 54.0").
- **Yönetici işlem kaydı:** yasaklama, silme, duyuru ve hediye işlemleri sunucuda kayda geçer (İŞLEM KAYDI sekmesi).
- **Duyuru geçmişi ve duyuru silme**, yeni istatistikler (son 24 saat aktif, bu hafta kayıt, toplam altın, en iyi oyuncular).
- **Dereceli puan koruması:** tam rütbe puanı sadece içinde başka oyuncuların olduğu gerçek bir online odada verilir.
- **Maç sunucusu (relay) güvenliği:**
  - Her oyuncunun giriş bilgisi Supabase'den doğrulanır: başkasının adıyla / kimliğiyle bağlanılamaz.
  - Yasaklı hesap maça giremez.
  - Sohbette isim taklidi yapılamaz, mesaj yağdırma (spam) engellenir.
  - Maçı sadece oda kurucusu başlatıp bitirebilir; sahte sistem mesajı gönderilemez.
  - Saniyede 90'dan fazla paket gönderen bağlantı kesilir. Sesli sohbet paketleri gönderenin kimliğiyle kontrol edilir.

## Sıra önemli
1. **Supabase → SQL Editor → New query →** `supabase/v2_guvenlik.sql` dosyasının TAMAMINI yapıştır → **RUN**.
   Mevcut hesaplar ve eşyalar silinmez.
2. **relay** klasöründeki **KUR_relay.bat**'a çift tıkla, Cloudflare token'ını yapıştır.
   (Bu adım ŞART: v2.7 oyunu yeni güvenli bağlantıyı kullanır.)
3. Oyunu güncelle (GÜNCELLE düğmesi).

Not: Supabase gizli anahtarını (sb_secret...) ve Cloudflare token'ını kimseyle paylaşma, sohbete yazma.
Token'ı her kurulumdan sonra Cloudflare panelinden iptal edip (Revoke) lazım olunca yenisini oluşturmak en güvenlisi.
