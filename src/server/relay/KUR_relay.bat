@echo off
chcp 65001 >nul
REM SOKAK relay sunucusunu Cloudflare'e kurar. Gerekli: Node.js LTS (https://nodejs.org)
cd /d %~dp0
where npx >nul 2>nul
if errorlevel 1 (
  echo.
  echo [HATA] Node.js kurulu degil ^(npx bulunamadi^).
  echo 1^) https://nodejs.org adresinden "LTS" surumunu indirip kur.
  echo 2^) Kurulumdan sonra BILGISAYARI YENIDEN BASLAT ^(ya da bu pencereyi kapatip yeniden ac^).
  echo 3^) Bu dosyayi tekrar calistir.
  echo.
  start https://nodejs.org/
  pause
  exit /b 1
)
echo Node.js bulundu.
REM Token gerekmez: Cloudflare girisi tarayicida yapilir (bir kez), wrangler oturumu hatirlar.
call npx --yes wrangler@4 whoami >nul 2>nul
if errorlevel 1 (
  echo Tarayicida Cloudflare girisi acilacak, "Allow" ile onayla...
  call npx --yes wrangler@4 login
)
call npx --yes wrangler@4 deploy
echo.
echo Kurulum bitti. Yukarida "https://....workers.dev" ile biten adres gorunuyorsa her sey tamam.
pause
