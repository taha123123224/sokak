# SOKAK: Operasyon - oyun dosyasini (SOKAK.pck) GitHub'dan parca parca indirir ve birlestirir.
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "SOKAK: Operasyon - Oyun dosyalari indiriliyor"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifest = "https://raw.githubusercontent.com/taha123123224/sokak/main/version.json"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host ""
Write-Host "  SOKAK: OPERASYON" -ForegroundColor Yellow
Write-Host "  Oyun dosyalari indiriliyor, lutfen bu pencereyi kapatmayin..." -ForegroundColor Gray
Write-Host ""
try {
    $v = Invoke-RestMethod -Uri ($manifest + "?t=" + [DateTimeOffset]::Now.ToUnixTimeSeconds()) -UseBasicParsing
} catch {
    Write-Host "  Surum bilgisi alinamadi. Internet baglantinizi kontrol edin." -ForegroundColor Red
    Start-Sleep 6; exit 2
}
$parts = $v.parts
$total = ($parts | Measure-Object -Property size -Sum).Sum
$out = Join-Path $dir "SOKAK.pck.new"
if (Test-Path $out) { Remove-Item $out -Force }
$fs = [System.IO.File]::Open($out, [System.IO.FileMode]::Create)
$done = 0
$i = 0
foreach ($p in $parts) {
    $i++
    $tmp = Join-Path $env:TEMP ("sokak_part" + $i)
    $ok = $false
    for ($try = 1; $try -le 4 -and -not $ok; $try++) {
        try {
            Start-BitsTransfer -Source $p.url -Destination $tmp -DisplayName ("SOKAK parca $i / " + $parts.Count) -Description "SOKAK: Operasyon" -ErrorAction Stop
            if ((Get-Item $tmp).Length -eq [int64]$p.size) { $ok = $true }
        } catch {
            try {
                $wc = New-Object System.Net.WebClient
                $wc.DownloadFile($p.url, $tmp)
                if ((Get-Item $tmp).Length -eq [int64]$p.size) { $ok = $true }
            } catch { Start-Sleep 2 }
        }
    }
    if (-not $ok) {
        $fs.Close(); Remove-Item $out -Force -ErrorAction SilentlyContinue
        Write-Host "  Indirme basarisiz oldu (parca $i). Kurulumu tekrar calistirin." -ForegroundColor Red
        Start-Sleep 8; exit 3
    }
    $bytes = [System.IO.File]::ReadAllBytes($tmp)
    $fs.Write($bytes, 0, $bytes.Length)
    Remove-Item $tmp -Force
    $done += [int64]$p.size
    Write-Host ("  Parca {0}/{1} tamam  ({2:N0} / {3:N0} MB)" -f $i, $parts.Count, ($done / 1MB), ($total / 1MB)) -ForegroundColor Green
}
$fs.Close()
$pck = Join-Path $dir "SOKAK.pck"
if (Test-Path $pck) { Remove-Item $pck -Force }
Rename-Item $out "SOKAK.pck"
Write-Host ""
Write-Host "  Tamamlandi! Oyun baslatiliyor..." -ForegroundColor Yellow
Start-Sleep 1
exit 0
