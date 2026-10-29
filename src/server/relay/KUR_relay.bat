@echo off
REM SOKAK relay sunucusunu Cloudflare'e kurar. Gerekli: Node.js (https://nodejs.org)
REM Kullanim: bu dosyaya cift tikla, istenince Cloudflare API token'ini yapistir.
cd /d %~dp0
set /p CLOUDFLARE_API_TOKEN=Cloudflare API token: 
call npx --yes wrangler@4 deploy
echo.
echo Yukaridaki workers.dev adresini Claude.a gonder.
pause
