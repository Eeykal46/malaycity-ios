"""Cari alamat asas libGTASA dlm C++ client (net/), untuk menilai sama ada
alamat GTA perlu ditulis semula untuk iOS.

Kenapa ini kritikal:
  Client SA-MP menyentuh memori enjin GTA melalui alamat MUTLAK, cth:
      *(float*)0x9A1AB0 = 12.0f;
  Alamat sedemikian SAH untuk satu binari SAHAJA (libGTASA.so arm64 Android).
  Binari iOS pula berlainan sepenuhnya -> setiap alamat mesti diubah.
  Kalau bilangannya beribu, ini bukan kerja minggu - ini kerja bulan.
"""
import os
import re
import sys
from collections import Counter

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    '..', '..', 'mobile', 'app', 'src', 'main', 'cpp', 'samp'))

SRC_EXT = ('.cpp', '.h', '.hpp', '.c', '.cc')
SKIP_DIRS = {'vendor', 'opus', 'imgui', 'armhook', 'android-inline-hook'}

# g_libGTASA ialah asas (dlopen). Semua alamat = g_libGTASA + 0xOFFSET
RE_BASE = re.compile(r'g_libGTASA\s*\+\s*(0x[0-9A-Fa-f]+)')
# alamat mutlak mentah (kurang biasa tetapi wujud)
RE_ABS = re.compile(r'\*\([^)]*\)\s*(0x[0-9A-Fa-f]{5,})')


def main():
    if not os.path.isdir(ROOT):
        print('Folder tak dijumpai: %s' % ROOT)
        print('(Skrip ini perlu dijalankan dalam repo penuh, bukan repo slim.)')
        return 1

    offsets = Counter()
    files_with = Counter()
    abs_hits = 0
    nfiles = 0

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(SRC_EXT):
                continue
            p = os.path.join(dirpath, fn)
            nfiles += 1
            try:
                with open(p, 'r', encoding='utf-8', errors='replace') as f:
                    txt = f.read()
            except Exception:
                continue

            found = RE_BASE.findall(txt)
            for h in found:
                offsets[h.lower()] += 1
            if found:
                files_with[os.path.relpath(p, ROOT)] = len(found)

            abs_hits += len(RE_ABS.findall(txt))

    print('Folder      : %s' % ROOT)
    print('Fail sumber : %d' % nfiles)
    print()
    print('ALAMAT BERASAS g_libGTASA (perlu ditulis semula untuk iOS)')
    print('  rujukan unik  : %d' % len(offsets))
    print('  jumlah rujukan: %d' % sum(offsets.values()))
    print('  fail terlibat : %d' % len(files_with))
    print()
    if abs_hits:
        print('ALAMAT MUTLAK MENTAH *(type*)0x... : %d' % abs_hits)
        print()

    print('15 fail dgn rujukan terbanyak:')
    for f, c in files_with.most_common(15):
        print('  %5d  %s' % (c, f))

    print()
    print('15 alamat paling kerap:')
    for o, c in offsets.most_common(15):
        print('  %-12s %d kali' % (o, c))

    print()
    # Skala kerja
    u = len(offsets)
    if u == 0:
        print('KESIMPULAN: tiada alamat keras -> client mungkin mudah dipindah!')
    elif u < 100:
        print('KESIMPULAN: %d alamat - boleh dikerjakan (hari/minggu).' % u)
    elif u < 500:
        print('KESIMPULAN: %d alamat - kerja besar (minggu/bulan).' % u)
    else:
        print('KESIMPULAN: %d alamat - skala sangat besar (bulan).' % u)
        print('  Ia mengikat client kepada SATU binari libGTASA sahaja.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
