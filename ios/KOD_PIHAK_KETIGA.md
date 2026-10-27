# Kod pihak ketiga

## Husk Translation Layer — GPL-2.0-or-later

Folder `husk/` mengandungi kod daripada **Husk** oleh Leviidev:

- Sumber: https://github.com/Leviidev/Husk
- Lesen: GNU General Public License v2.0 atau lebih baru
- Salinan lesen: `husk/LICENSE-HUSK-GPL2.txt`
- Fail asal: `src/translation-layer/` (22 fail, 672 KB)

**Apa yang Husk beri:** loader ELF arm64 (73 KB), shim bionic (40 KB),
parser ELF (25 KB), framework shim (112 KB), DEX runtime (88 KB).

**Kenapa ia digunakan:** `libGTASA.so` ialah ELF Android. `dyld` iOS hanya
menerima Mach-O (disahkan pada iPhone 13 Pro, 28 Okt 2026:
`slice is not valid mach-o file`). Husk menyelesaikan masalah ini dengan
memetakan ELF sendiri ke memori iOS pada page 16 KiB, dan memenuhi 274
import Android melalui shim — bukan dengan menukar binari.

## Kesan lesen kepada projek ini

Kerana kod GPL-2.0 disertakan, **keseluruhan app MALAYCITY iOS menjadi
GPL-2.0**. Itu bermakna:

- Sumber mesti disediakan kepada sesiapa yang menerima app
- Sesiapa boleh mengedar semula di bawah GPL-2.0
- App tidak boleh ke App Store (GPL + keperluan JIT/debugger)

Repo awam `Eeykal46/malaycity-ios` memenuhi syarat sumber (GPLv2 §3).

## Kod kita sendiri

Folder `McLauncher/` dan `enjin/` ialah kod asal MALAYCITY. Ia tidak
mengubah kod Husk — ia memanggilnya.
