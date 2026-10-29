; SOKAK: Operasyon - Windows kurulum programi (NSIS)
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!define APPNAME "SOKAK: Operasyon"
!define APPKEY "SOKAK"
!ifndef VERSION
  !define VERSION "2.2.0"
!endif
Name "${APPNAME}"
OutFile "SOKAK_Kurulum.exe"
InstallDir "$LOCALAPPDATA\SOKAK"
InstallDirRegKey HKCU "Software\${APPKEY}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "SOKAK: Operasyon ${VERSION}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileDescription" "${APPNAME} Kurulum"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "SOKAK"
VIAddVersionKey "LegalCopyright" "SOKAK"

!define MUI_ICON "sokak.ico"
!define MUI_UNICON "sokak.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "header.bmp"
!define MUI_HEADERIMAGE_RIGHT
!define MUI_WELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "SOKAK: Operasyon Kurulumuna Hoş Geldin"
!define MUI_WELCOMEPAGE_TEXT "Türkiye'nin sokaklarında taktik çatışma!$\r$\n$\r$\nBu sihirbaz oyunu bilgisayarına kuracak, masaüstüne ve Başlat menüsüne kısayol ekleyecek.$\r$\n$\r$\nKurulumdan sonra SOKAK Başlatıcı açılır ve oyun dosyalarını (yaklaşık 330 MB) indirir. İndirme bitince BAŞLAT düğmesiyle oyuna girersin. Güncellemeler de başlatıcıdan otomatik gelir; oyuncu verilerin silinmez."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Turkish"

Section "Oyun" SecMain
  SetOutPath "$INSTDIR"
  ; close a running game before replacing files
  nsExec::Exec 'taskkill /IM SOKAK.exe /F'
  nsExec::Exec 'taskkill /IM SOKAKBaslatici.exe /F'
  File "payload\SOKAK.exe"
  File "payload\OKU_BENI.txt"
  File "sokak.ico"
  File "payload\SOKAKBaslatici.exe"
  Delete "$INSTDIR\indir.ps1"
  SetOutPath "$INSTDIR\mods"
  File /r "payload\mods\*.*"
  SetOutPath "$INSTDIR"
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\SOKAKBaslatici.exe" "" "$INSTDIR\sokak.ico"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\Kaldır.lnk" "$INSTDIR\Kaldir.exe"
  Delete "$DESKTOP\${APPNAME}.lnk"
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\SOKAKBaslatici.exe" "" "$INSTDIR\sokak.ico"
  WriteUninstaller "$INSTDIR\Kaldir.exe"
  WriteRegStr HKCU "Software\${APPKEY}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}" "DisplayIcon" "$INSTDIR\sokak.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}" "Publisher" "SOKAK"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}" "UninstallString" '"$INSTDIR\Kaldir.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}" "NoRepair" 1
  ; kurulum penceresi kapanır, başlatıcı indirmeyi yapar ve BAŞLAT düğmesini gösterir
  Exec '"$INSTDIR\SOKAKBaslatici.exe"'
  SetAutoClose true
SectionEnd

Section "Uninstall"
  nsExec::Exec 'taskkill /IM SOKAK.exe /F'
  Delete "$INSTDIR\SOKAK.exe"
  Delete "$INSTDIR\SOKAK.pck"
  Delete "$INSTDIR\SOKAK.pck.new"
  Delete "$INSTDIR\OKU_BENI.txt"
  Delete "$INSTDIR\sokak.ico"
  Delete "$INSTDIR\indir.ps1"
  Delete "$INSTDIR\SOKAKBaslatici.exe"
  Delete "$INSTDIR\surum.txt"
  RMDir /r "$INSTDIR\indirilenler"
  Delete "$INSTDIR\sokak_guncelle.bat"
  Delete "$INSTDIR\Kaldir.exe"
  RMDir /r "$INSTDIR\mods"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${APPNAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APPNAME}"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}"
  DeleteRegKey HKCU "Software\${APPKEY}"
SectionEnd
