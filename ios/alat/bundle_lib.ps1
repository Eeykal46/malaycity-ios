# bundle_lib.ps1 - Salin lib Android dari folder lib/ ke dalam projek iOS.
#
# PENTING: skrip ini HANYA BACA dari lib/ dan TULIS ke ios/enjin/bundel/lib/.
# Ia TIDAK menyentuh mobile/ langsung.
#
# Tidak disertakan (arahan dia): libluajit-5.1.so, libmonetloader.so
# Tidak disertakan (arm32 sahaja): armeabi-v7a/*, libImmEmulatorJ.so
# Tidak disertakan (Firebase, bukan enjin): libcrashlytics*.so
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$src  = Join-Path $root 'lib\arm64-v8a'
$dst  = Join-Path $root 'ios\enjin\bundel\lib'

# libGTASA.so ditukar nama jadi libGame.so: Husk cari "libGame.so"
# (husk-tl-gtasa.c: tl_ld_find_lib("libGame.so")). Binari SAMA.
$peta = @{
    'libGTASA.so'     = 'libGame.so'
    'libsamp.so'      = 'libsamp.so'
    'libSCAnd.so'     = 'libSCAnd.so'
    'libOpenAL64.so'  = 'libOpenAL64.so'
    'libbass.so'      = 'libbass.so'
    'libshadowhook.so'= 'libshadowhook.so'
}

New-Item -ItemType Directory -Force -Path $dst | Out-Null

$jumlah = 0
foreach ($asli in $peta.Keys) {
    $p = Join-Path $src $asli
    if (-not (Test-Path $p)) {
        Write-Host "TIADA: $asli" -ForegroundColor Yellow
        continue
    }
    $out = Join-Path $dst $peta[$asli]
    Copy-Item $p $out -Force
    $mb = [math]::Round((Get-Item $out).Length / 1MB, 2)
    $jumlah += $mb
    Write-Host ("  {0,-20} -> {1,-20} {2} MB" -f $asli, $peta[$asli], $mb) -ForegroundColor Green
}

Write-Host ""
Write-Host "JUMLAH: $jumlah MB dalam ios/enjin/bundel/lib/" -ForegroundColor Cyan
Write-Host "(libluajit + libmonetloader TIDAK disertakan - arahan dia)"
