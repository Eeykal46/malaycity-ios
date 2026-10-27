# bundle_apk.ps1 - Salin APK Android ke dalam projek iOS sebagai resource.
#
# Tujuan: SATU app iOS yang mengandungi enjin + client + assets Android.
# Husk menjalankannya terus - tiada APK berasingan, tiada muat turun.
#
# Jalankan selepas setiap kali bina APK Android baru:
#   powershell -File ios\alat\bundle_apk.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$apk = Join-Path $root 'mobile\app\build\outputs\apk\debug\app-debug.apk'
$dst = Join-Path $root 'ios\enjin\bundel\MALAYCITY.apk'

if (-not (Test-Path $apk)) {
    Write-Host "APK tidak dijumpai: $apk" -ForegroundColor Red
    Write-Host "Bina dulu di Android Studio: Build > Build Bundle(s)/APK(s) > Build APK(s)" -ForegroundColor Yellow
    exit 1
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
Copy-Item $apk $dst -Force

$src = (Get-FileHash $apk).Hash
$out = (Get-FileHash $dst).Hash
$mb = [math]::Round((Get-Item $dst).Length / 1MB, 1)

if ($src -eq $out) {
    Write-Host "OK: APK disalin ($mb MB) -> ios/enjin/bundel/MALAYCITY.apk" -ForegroundColor Green
} else {
    Write-Host "GAGAL: hash tidak sepadan" -ForegroundColor Red
    exit 1
}
