SOKAK — EKLENTİ (MOD) REHBERİ
=============================
Her eklenti bir klasördür ve içinde mod.json bulunur. Klasörü şuraya koy:
  • Oyun klasörü/mods/<eklenti>/mod.json     (SOKAK.exe'nin yanındaki mods klasörü)
  • %APPDATA%/Godot/app_userdata/SOKAK/mods/<eklenti>/mod.json

mod.json alanları (hepsi isteğe bağlı):
  "weapons":    { "id": { "base": "ak47", "name": "...", "dmg": 33, "rpm": 600, "mag": 30, "price": 3000, "model": "silah.glb" } }
                base = hazır silah (model + animasyonlar), "model" verirsen kendi .glb modelin kullanılır.
  "skins":      { "id": { "name": "...", "price": 900, "rarity": 0-3, "texture": "desen.png", "color": "#ff0000" } }
  "characters": { "id": { "name": "...", "team": "a"|"b", "price": 0, "model": "karakter.glb" | "base": "takim" } }
  "maps":       { "id": { "name": "...", "glb": "harita.glb", "json": "harita.json" } }
                json: {"colliders":[{"c":[x,y,z],"s":[sx,sy,sz],"r":[rx,ry,rz]}], "spawns":[{"p":[x,y,z],"yaw":0,"team":"a"}], "env":{"preset":"day"}, "bounds":[x0,y0,x1,y1]}
  "crates":     { "id": { "name": "...", "price": 1500, "color": "#ffaa00", "skins": [...], "weapons": [...], "chars": [...] } }

Oyunda: Lobi > EKLENTİLER sayfasından eklentileri açıp kapatabilirsin (değişiklik yeniden başlatınca uygulanır).
