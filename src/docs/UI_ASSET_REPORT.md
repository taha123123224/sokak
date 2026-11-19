# SOKAK v4.18 — UI/UX Kaynak Araştırması, İndirme ve Entegrasyon Raporu

Tarih: 19 Kasım 2026. Bu rapor yalnızca **gerçekten indirilen ve oyunda kullanılan** dosyaları listeler.
İncelenip kullanılmayan içerik ayrıca ve nedeniyle belirtildi. Sahte indirme/entegrasyon kaydı yoktur.

İndirme yolu: bulut çalışma alanının ağı kenney.nl, itch.io, opengameart.org, sonniss.com, lucide.dev,
game-icons.net ve fonts.google.com'a kapalı. Bu yüzden:
- Google Fonts → GitHub `google/fonts` deposu (aynı dosyalar), Lucide → npm `lucide-static@1.76.0`,
  game-icons.net → GitHub `game-icons/icons` deposu (sitenin kaynağı).
- Kenney, OpenGameArt, itch.io, Sonniss → Claude tarayıcı paneliyle kullanıcının Downloads klasörüne indirildi,
  oradan projeye alındı. Sonniss'te 7,47 GB'lık paketin yalnızca UI kütüphaneleri, zip'in içindekiler
  dizini okunarak 12 MB'lık parça halinde çekildi.

## Klasörler

| Klasör | İçerik |
|---|---|
| `assets/fonts/` | Rajdhani-Bold.ttf, RobotoCondensed-VF.ttf, Inter-VF.ttf + OFL lisansları |
| `assets/icons/lucide/` | 31 Lucide SVG (beyaz, renklendirilebilir) + LICENSE_lucide_ISC.txt |
| `assets/icons/game/` | 14 game-icons.net SVG + LICENSE_game-icons_CC-BY-3.0.txt |
| `assets/ui/kenney/` | onay kutusu / radyo / açılır ok glifleri (UI Pack), köşesi kesik cam paneller (UI Pack Sci-Fi) |
| `assets/ui/crosshairs/` | 17 hazır nişangah (Kenney 10, OGA hc 4, OGA para 3) + lisanslar |
| `assets/ui/ranks/` | 18 Naro seviye kalkanı (`bronze_1` … `galaxy_6`) — mevcut rütbe amblemleri r0–r17 korunur |
| `assets/audio/ui/` | 26 arayüz sesi (.ogg, mono, ses yüksekliği eşitlenmiş) + Kenney / Sonniss lisans metinleri |
| `assets/audio/announcer/` | 2 anons sesi (Sonniss / Epic Stock Media) |
| `assets/backgrounds/` | oluşturulmadı: listedeki kaynaklarda CS2 diline uyan arka plan yok; mevcut harita görselleri kullanılıyor |

## Kod bağlantıları (Godot)

| Dosya | Ne yapıyor |
|---|---|
| `scripts/ui.gd` | `UI.font()` rol eşlemesi (FontVariation ile ağırlık), `build_theme()` içinde type variation'lar (H1, H2, H3, StatValue, StatLabel, Body, Caption, NavButton), Kenney onay kutusu/ok ikonları, Popup/AcceptDialog için 9-slice panel, `UI.icon()`, `UI.icon_tex()`, `UI.ibtn()`, `UI.notch_sb()` |
| `scripts/ui_sfx.gd` (autoload **UiSfx**) | Her ekranda oluşan her BaseButton / CheckBox / OptionButton / Slider / TabBar / LineEdit / Window'a hover-tık-geçiş-açılış sesi bağlar; `UI.btn` ile gelenleri atlar |
| `scripts/sfx.gd` | `assets/audio/ui` ve `assets/audio/announcer` klasörlerini arar; UI seslerini **UI** ses kanalına yönlendirir; `SFX.ui()` |
| `scripts/gs.gd` | `vol_ui`, `ui_sounds`, `out_device`, `xh_img` ayarları; `level_icon()`, `XH_IMAGES`, `xh_tex()`; CREDITS listesine v4.18 atıfları |
| `scripts/settings_ui.gd` | İkonlu sekmeler, Inter ile ayar satırları, Arayüz Sesleri kaydırıcısı, ses çıkış aygıtı seçimi, nişangah galerisi |
| `scripts/menu.gd` | Lucide üst çubuk/arkadaş rayı ikonları, Naro seviye kalkanı, yeni bildirim (toast), sayfa geçiş sesi, çanta/market sekme ikonları, profil istatistik ikonları, OYNA ikonu, çıkış diyaloğu |
| `scripts/menu_online.gd` | Maç arama sesleri, sıralama başlığı ikonu |
| `scripts/login.gd` | Lucide kullanıcı/kilit/göz ikonları, Kenney panelli diyalog, **gerçek** sunucu gecikmesi ölçümü (sabit "18 ms" kaldırıldı) |
| `scripts/online.gd` | `measure_ping()` — `/auth/v1/health` gidiş-dönüş süresi; ulaşılamazsa -1 |
| `scripts/hud.gd` | Skor tablosu ikonları, MVP madalyası, **gerçek** ping (bot = "BOT", bilinmiyor = "—"; isimden türetilen sahte ping kaldırıldı), öldürme akışında headshot ikonu, maç sonu istatistik/ödül ikonları ve sesleri, hazır nişangah çizimi |
| `scripts/match.gd`, `ctf.gd`, `sabotage.gd` | "10 kills remaining" ve "Objective completed" anonsları; yükleme bitiş sesi; test kancası 141 (maç sonu ekranı) |

## Kaynak bazında rapor

### 1. Kenney UI Pack — https://kenney.nl/assets/ui-pack
1. Ziyaret: evet (tarayıcı). 2. Durum: indirildi, açıldı (1315 dosya).
3. İncelenen kategoriler: Grey/Blue/… paneller, butonlar, onay kutuları, oklar, kaydırıcılar.
4. Kullanılan: 3 kaynak (+ türetilmiş 5 dosya). 5. Dosyalar: `icon_checkmark.png`, `icon_circle.png`,
`arrow_basic_s_small.png` → `assets/ui/kenney/check_on.png`, `check_off.png`, `radio_on.png`, `radio_off.png`, `arrow_down.png`.
6. Lisans: CC0. 7. Ekranlar: Ayarlar, Giriş/Kayıt (koşullar ve "oturum açık kalsın" kutuları), tüm OptionButton'lar.
8. Entegrasyon: Theme (`CheckBox` checked/unchecked/radio, `OptionButton` arrow). 9. Kullanılmayan: renkli/parlak butonlar —
açık renkli, yuvarlak çizgileri CS2'nin düz koyu diline uymuyor.

**Ek: Kenney UI Pack Sci-Fi** (aynı sitede, CC0): `panel_glass_notch_tr.png`, `panel_glass_notches.png` → 9-slice,
grafit tonuna boyanarak bildirimler, çıkış diyaloğu, giriş diyaloğu, PopupPanel/AcceptDialog temasında.

### 2. itch.io Free Game UI — https://itch.io/game-assets/tag-free/tag-user-interface
1. Ziyaret: evet; ilk 36 sonuç + "free/hud" etiketi tarandı (FPS ve sci-fi alt etiketleri boş döndü).
2–5. İndirilen: **Naro Rank Vector Icons** (TheColourfulSuit / @NarekArts), `NaroRankIcons.zip` (18 MB, 120 PNG).
Kullanılan 18 kalkan → `assets/ui/ranks/<renk>_<n>.png` (160 px'e küçültüldü).
6. Lisans: ücretsiz ("Name your own price", 0 TL ile alındı); kişisel ve ticari oyunlarda kullanım serbest; atıf rica ediliyor;
ham dosyaların depolara/marketlere yüklenmesi yasak → ham dosyalar **açık kaynak deposuna konmadı**, yalnızca oyun paketinde.
7. Ekranlar: üst çubuk ve profil seviye rozeti (her 5 seviyede bir kademe: bronz → gümüş → altın → elmas → ametist → yakut → galaksi).
8. Entegrasyon: `GS.level_icon()`, `LevelBadge`. Rütbe amblemleri r0–r17 (ay-yıldızlı askeri rozetler) korunur.
9. İncelenip kullanılmayan: *Free UI Hologram Interface*, *Dark Miko* (Wenrexa) — sayfada lisans yazmıyor, kural gereği alınmadı;
*SoupTonic UI menu sounds* — CC-BY benzeri ama retro/8-bit tarz, SOKAK'a uymuyor; diğerleri piksel-art/fantastik RPG.

### 3. OpenGameArt UI — https://opengameart.org/art-search-advanced?keys=UI
1. Ziyaret: evet. Not: sitede "UI" araması 3 harf kuralına takılıyor; "user interface", "gui", "hud" ile CC0 filtreli arandı.
2–5. İndirilen ve kullanılan: *Crosshairs and Reticles* (hc) `crosshairs.zip` → `oga_hc_4..7.png`;
*64 crosshairs pack* (para) `crosshairs64.png` → 3 hücre `oga_para_20/34/35.png` (siyah arka plan alfaya çevrildi).
6. Lisans: CC0 (sayfada ve paket içinde doğrulandı). 7. Ekran: Ayarlar > Nişangah > Hazır Şekil, oyun içi nişangah.
9. Kullanılmayan: *Sci-fi User Interface Elements* (yalnızca PSD), panel/buton paketlerinin neredeyse tamamı piksel/fantastik.

### 4. Lucide Icons — https://lucide.dev/icons/
1. Ziyaret: evet (lisans sayfası). 2. İndirme: npm `lucide-static@1.76.0` (2404 SVG). 4. Kullanılan: **31**.
5. house, settings, user, users, user-plus, shield, power, bell, trophy, circle-check, triangle-alert, info, monitor, crosshair,
keyboard, volume-2, sliders-horizontal, map, target, clock, swords, zap, coins, gem, package, backpack, gamepad-2, play,
lock, eye, eye-off. Çizgi rengi beyaz yapıldı, 64 px.
6. Lisans: ISC. 7. Ekranlar: üst çubuk, arkadaş rayı, ayarlar sekmeleri, bildirimler, skor tablosu başlığı, maç sonu,
profil istatistikleri, market/çanta sekmeleri, OYNA butonu, giriş formu.

### 5. Game-icons.net — https://game-icons.net/
1. Ziyaret: evet (hakkında/lisans). 2. İndirme: GitHub `game-icons/icons` (4239 SVG). 4. Kullanılan: **14**.
5. ak47 (Skoll), headshot (Skoll), bowie-knife→knife (Skoll), pistol-gun→pistol (John Colburn), grenade (sbed), death-skull→death (sbed),
kevlar (sbed), trophy (Lorc), laurel-crown→laurel (Lorc), medal (Lorc), skull-crossed-bones→skull (Lorc), star-medal (Delapouite),
podium (Delapouite), chest (Delapouite). Siyah arka plan kaldırıldı.
6. Lisans: CC BY 3.0 — yazarlar Ayarlar > Lisanslar'da. 7. Ekranlar: öldürme akışı (headshot), skor tablosu (MVP),
maç sonu, profil, çanta/market sekmeleri, sezon sayfası, sıralama başlığı.
**Stil tutarlılığı:** Lucide = arayüz ikonları (çizgi), game-icons = oyun nesneleri/madalyalar (dolu siluet); ikisi de beyaz,
tema rengiyle boyanıyor.

### 6–8. Rajdhani, Roboto Condensed, Inter — fonts.google.com
1. Ziyaret: evet (üç lisans sayfası). 2. İndirme: `google/fonts` deposu (Google Fonts'un kaynağı).
5. `Rajdhani-Bold.ttf`, `RobotoCondensed[wght].ttf` → `RobotoCondensed-VF.ttf`, `Inter[opsz,wght].ttf` → `Inter-VF.ttf`.
6. Lisans: SIL OFL 1.1 (dosyalar `assets/fonts/OFL_*.txt`).
7–8. Theme sistemine bağlı roller:
- **Rajdhani**: başlıklar, seviye/rütbe sayıları, skor tabelası rakamları (eski "RussoOne"/"Teko" çağrıları).
- **Roboto Condensed** (wght 400/600/700): üst menü, butonlar, skor ve istatistik etiketleri.
- **Inter**: Theme varsayılan fontu, ayar satırları ve açıklamaları, bildirimler, haber metni, giriş alanları, RichTextLabel.
Barlow eksik glif durumunda yedek font olarak kaldı. Sabit genişlikli yerleşimlerde metin taşmasın diye
bazı açıklamalar Roboto Condensed'de bırakıldı.

### 9. Kenney Audio — https://kenney.nl/assets?q=audio
İndirilen: *Interface Sounds* (100), *UI Audio* (50) — CC0. Kullanılan 11: ui_hover (select_002), ui_click (UI Audio click2),
ui_back, ui_tab (switch_002), ui_open (maximize_006), ui_close (minimize_006), ui_toggle, ui_scroll, inv_drop, ui_slider (switch7).
Ekranlar: her ekrandaki butonlar (UiSfx), ayarlar, sekmeler, diyaloglar.

### 10. Sonniss GDC Audio Bundle — https://gdc.sonniss.com/
1. Ziyaret: evet; parça listesi (Google Sheets, 347 dosya) okundu. Paket 5 zip, 7,47 GB.
2. UI kütüphaneleri 2. zip'te bulundu; zip'in merkez dizini HTTP Range ile okunup yalnızca 19 ses + lisans PDF'i indirildi (12 MB).
5. Kullanılan 9: ui_notify (Interface Pop High Short), ui_success (Interface Accept Glassy Snap), ui_error (Interface Deny Low Fat Dark),
ui_invite (Interface Sci-Fi Ping Down), inv_equip (Interface Percussion Snap), shop_buy (Ting Coins), reward (Button Arp Twinkle),
mm_found (Interface Arp Reveal Down Long); anons: ann_objective ("Objective Completed"), ann_ten_left ("Ten Kills Remaining").
6. Lisans: Sonniss GDC lisansı — telifsiz, atıfsız ticari kullanım; ham olarak satılamaz; yapay zekâ eğitimi yasak
(`assets/audio/ui/LICENSE_sonniss_gdc.txt`). Ham dosyalar açık kaynak deposuna konmadı.
9. Kullanılmayan: diğer 10 ses (Kalimba, Boing, "Happy" vb. çizgi film tonu).

### 11. OpenGameArt Interface Audio — https://opengameart.org/art-search-advanced?keys=interface+sound
İndirilen (hepsi CC0): *UI Sound Effects* (Robin Lamb), *GUI Sound Effects* (LokiF), *Interface beeps* (bart),
*5 Menu Screen Slides* (CleytonKauffman), *Accept/Decline UI Menu* (KarateStudios), *Hi-Tech Button Sound Pack I* (Circlerun).
Kullanılan 7: ui_page (slide 03), mm_accept, mm_decline, mm_search (beep-07), ui_save, ui_loaded (LokiF), friend_online (Ding),
levelup_chime (chimes). **Kullanılamayan:** Circlerun paketi RAR içinde; çalışma alanında RAR açıcı yok → kullanılmadı.
*51 UI sound effects* Kenney'in kendi paketinin kopyası olduğu için tekrar indirilmedi.

### 12. Godot 4.5 resmî belgeleri (8 sayfa)
Hepsi tarayıcıdan okundu. Uygulananlar: Theme **type variation** (`set_type_variation`), proje geneli tema + font **fallback**,
StyleBoxTexture 9-slice, `Button.icon` + `icon_*_color` sabitleri, Tween `set_parallel/set_trans/set_ease` (bildirim kayması),
Container boyut bayrakları (HFlowContainer nişangah galerisi), `Control.mouse_filter` (dekoratif ikonlar tıklamayı engellemiyor),
`AudioServer.output_device` (ses çıkış aygıtı). Odak (focus) navigasyonu: mevcut menü butonları `FOCUS_NONE` ile kurulu;
gamepad/klavye odak navigasyonu bu sürümde eklenmedi (aşağıda açık iş).

## Ekran bazında kullanım

| Ekran | Kullanılan yeni varlık |
|---|---|
| Açılış / yükleme | Rajdhani/Roboto fontları, `ui_loaded` sesi |
| Giriş / Kayıt | Lucide kullanıcı/kilit/göz, Kenney onay kutuları, Kenney panelli koşullar diyaloğu, Inter giriş alanları, hata/başarı sesleri, gerçek gecikme |
| Ana menü / Lobi | Lucide üst çubuk + arkadaş rayı, Naro seviye kalkanı, OYNA ikonu, yeni bildirimler, sayfa geçiş sesi |
| Matchmaking | mm_search / mm_found / mm_accept / mm_decline |
| Oyun modları, Harita seçimi | yalnızca fontlar + genel buton sesleri (özel ikon eklenmedi) |
| Envanter (Çanta) | game-icons kategori sekmeleri, `inv_equip` |
| Silah inspect | yalnızca fontlar (yeni varlık yok) |
| Mağaza | game-icons + Lucide sekme ikonları, `shop_buy` |
| Profil | Lucide + game-icons istatistik ikonları, seviye kalkanı |
| Sıralama | game-icons podium |
| Başarımlar | oyunda ayrı başarım ekranı yok; madalya ikonu profil "GALİBİYET" kutusunda |
| Arkadaşlar | Lucide users / user-plus, arkadaş çevrimiçi sesi |
| Ayarlar | ikonlu sekmeler, Inter metin, UI ses kaydırıcısı, çıkış aygıtı, nişangah galerisi |
| Oyun içi HUD | 17 hazır nişangah, headshot ikonu, 2 yeni anons |
| Scoreboard | harita/hedef/saat ikonları, MVP madalyası, gerçek ping |
| Maç sonu | istatistik ve ödül ikonları, ödül/terfi sesleri |
| Bildirimler / popup | Kenney köşe kesik panel + Lucide durum ikonu + kayma animasyonu + bildirim sesi |

## Açık kalanlar
- Gamepad/klavye odak navigasyonu (Godot gui_navigation) — menü butonları şu an fareye göre kurulu.
- Silah inspect, oyun modları ve harita seçimi ekranlarına özel ikon eklenmedi.
- Circlerun ses paketi (RAR) açılamadı.

## Yerleşim yenilemesi (CS2 referans görselleri)

Kullanıcının gönderdiği 4 CS2 görseline göre ekranların **düzeni** yeniden yapıldı:

| Referans | SOKAK ekranı | Ne değişti |
|---|---|---|
| Ana menü (karakter + sol alt kartlar + arkadaş rayı) | Lobi | Sol/sağ paneller ve büyük OYNA bloğu kaldırıldı. Karakter tek başına ortada; ayağının yanında dikey oyuncu kartı (ajan, rütbe amblemi, seviye kalkanı, XP çubuğu, eğik RP plakası). Sol altta kart yığını: haber, "Yeni & Popüler" (sahip olunmayan gerçek mağaza silahları + gerçek fiyat, ◀ ▶ ile gezilir), günlük görevler, hediye. |
| Üst menü INVENTORY · LOADOUT · PLAY · STORE · NEWS | Üst çubuk | ÇANTA · DONANIM · MAĞAZA · KASA · **OYNA** (ortada, büyük) · SEZON · SIRALAMA · ODALAR · EKLENTİLER. Lobi = ev ikonu. |
| Harita seçimi (dikey kartlar, amblem, onay kutusu, hap sekmeler) | Oyna | BOT MAÇI / ÇEVRİMİÇİ / ODALAR hap sekmeleri, altında mod hap sekmeleri; dikey harita kartları (yuvarlak amblem, isim, boyut, sağ üst onay kutusu); alt çubukta zorluk / bot / süre ve BAŞLAT. Eski düzende 1080p'de ekran dışında kalan BAŞLAT butonu sorunu giderildi. |
| Loadout (çerçeveli panel, ortada karakter, silah sütunları) | Donanım (yeni sayfa) | Mavi kenarlı panel, dikey set sekmeleri (1–5), solda bıçak / bomba / ajan, ortada karakter, sağda TABANCALAR ve ANA SİLAHLAR sütunları; kuşanılı silah köşe çerçeveli, nadirlik noktası; tıklayınca aktif sete gerçekten kuşanır. |
| Oyuncu kartı açılır penceresi | Lobi > oyuncu kartına tık | Ajan, isim, 7 başarım madalyası (profildeki gerçek istatistiklerden; ulaşılmamışlar soluk, üzerine gelince hedef ve ilerleme), rütbe + seviye çubuğu, RP plakası, maç/galibiyet/öldürme/kafadan, Profil ve Donanım butonları. |

Not: Oyunda ayrı bir "Başarımlar" sayfası yoktu; başarımlar artık oyuncu kartında gerçek verilerle gösteriliyor.
