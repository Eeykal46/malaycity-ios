"""Siasat kenapa 18 alamat hanya padan ke $d.N (SPCL) dlm dump.

SPCL = "special" symbol (compiler/linker). $d.12 dsb ialah nama sintetik.
Kemungkinan: dump ini dari binari SEDIKIT BERBEZA (versi build lain), atau
alamat kita datang dari fungsi yg di-inline.

Ujian: cari alamat yang SAMA dalam dump 32-bit (kalau layout sepadan) dan
semak jarak antara simbol FUNC sebenar di sekitar alamat kita.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

TANPA_FUNC = [
    0x6D008, 0x1984A5, 0x1A3A69, 0x1AE8DE, 0x1B2558, 0x1BC269,
    0x1C2C90, 0x1DB9B0, 0x1DBA64, 0x1DBABC, 0x1E3A28, 0x1E9BC8,
    0x1E9C64, 0x1E9C80, 0x1EAC8C, 0x26B03C, 0x26B046,
    0x362E02, 0x5C9014, 0x5C9120,
]

RE_BARIS = re.compile(
    r'^\s*\d+\s+(0x[0-9A-Fa-f]+|-+)\s+(0x[0-9A-Fa-f]+)\s+'
    r'(\w+)\s+(\w+)\s+(\d+)\s+(\S+)')


def baca(path, hanya_func=True):
    out = []
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for ln in f:
            m = RE_BARIS.match(ln)
            if not m:
                continue
            paddr, vaddr, bind, typ, size, name = m.groups()
            if hanya_func and typ != 'FUNC':
                continue
            out.append((int(vaddr, 16), int(size), bind, name))
    return sorted(out)


def main():
    p64 = r'd:\DUMP\d64.txt'
    if not os.path.isfile(p64):
        print('TIADA:', p64)
        return 1

    funcs = baca(p64, hanya_func=True)
    print('simbol FUNC sebenar dlm dump : %d' % len(funcs))
    print()

    # untuk setiap alamat, cari FUNC terdekat atas dan bawah
    print('%-11s %-42s %-42s %s'
          % ('ALAMAT', 'FUNC DI BAWAH', 'FUNC DI ATAS', 'JURANG'))
    print('-' * 128)

    dalam_func = 0
    for a in TANPA_FUNC:
        bawah = [f for f in funcs if f[0] <= a]
        atas = [f for f in funcs if f[0] > a]
        b = max(bawah, key=lambda x: x[0]) if bawah else None
        t = min(atas, key=lambda x: x[0]) if atas else None

        if b and a < b[0] + max(b[1], 1):
            dalam_func += 1
            j = 'DALAM +0x%X' % (a - b[0])
        elif b and t:
            j = 'antara (0x%X)' % (t[0] - b[0])
        else:
            j = '-'

        nb = ('0x%X %s' % (b[0], b[3][:32])) if b else '(tiada)'
        nt = ('0x%X %s' % (t[0], t[3][:32])) if t else '(tiada)'
        print('0x%-9X %-42s %-42s %s' % (a, nb, nt, j))

    print()
    print('RINGKASAN:')
    print('  dalam FUNC sebenar : %d / %d' % (dalam_func, len(TANPA_FUNC)))
    print()
    if dalam_func == 0:
        print('  KESIMPULAN: tiada satu pun berada dalam FUNC bernama.')
        print('  Ini bermakna dump ini dari BINARI LAIN (build berbeza),')
        print('  ATAU alamat kita menunjuk ke wilayah kod tanpa simbol')
        print('  (cth PLT stub, thunk, atau fungsi di-strip sepenuhnya).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
