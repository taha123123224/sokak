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
set /p CLOUDFLARE_API_TOKEN=Cloudflare API token:
call npx --yes wrangler@4 deploy
echo.
echo Yukarida "https://....workers.dev" ile biten adresi Claude'a gonder (token'i GONDERME).
pause
