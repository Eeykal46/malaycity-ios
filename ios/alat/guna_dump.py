"""Guna DUMP simbol (blazervng/gta-2.10) untuk selesaikan 23 alamat tanpa simbol.

Format dump:
  nth  paddr      vaddr      bind   type  size  lib name  demangled
  3    0x0068f490 0x0068f490 GLOBAL FUNC  80    _ZN20CSpecialPlateHandler3AddEiPc
  1    0x00231aa0 0x00231aa0 LOCAL  SECT  0     .text
  8    ---------- 0x00baba16 GLOBAL OBJ   1     _ZN20CAERadioTrackManager23...

PENTING: dump ada simbol LOCAL (statik) - itulah yg .dynsym TIDAK ada.
Jika 23 alamat kita ada dlm dump, ia boleh dinamakan!

Jalankan: python ios/alat/guna_dump.py [laluan dump]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))

TANPA = [
    0x6D008, 0x1984A5, 0x1A3A69, 0x1AE8DE, 0x1B2558, 0x1BC269,
    0x1C2C90, 0x1DB9B0, 0x1DBA64, 0x1DBABC, 0x1E3A28, 0x1E9BC8,
    0x1E9C64, 0x1E9C80, 0x1EAC8C, 0x26B03C, 0x26B046, 0x2B0D5C,
    0x2CB7C8, 0x2CC144, 0x362E02, 0x5C9014, 0x5C9120,
    0xA7C264,   # DATA
]

# baris dump: nth paddr vaddr bind type size name
RE_BARIS = re.compile(
    r'^\s*\d+\s+(0x[0-9A-Fa-f]+|-+)\s+(0x[0-9A-Fa-f]+)\s+'
    r'(\w+)\s+(\w+)\s+(\d+)\s+(\S+)')


def baca_dump(path):
    """[(vaddr, size, bind, type, name)]"""
    syms = []
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for ln in f:
            m = RE_BARIS.match(ln)
            if not m:
                continue
            paddr, vaddr, bind, typ, size, name = m.groups()
            syms.append((int(vaddr, 16), int(size),
                         bind, typ, name))
    return syms


def cari(syms, a):
    """Simbol yg mengandungi alamat, atau yg paling hampir di bawah."""
    dalam = [s for s in syms if s[0] <= a < s[0] + max(s[1], 1)]
    if dalam:
        s = max(dalam, key=lambda x: x[0])
        return ('DALAM', s, a - s[0])
    bawah = [s for s in syms if s[0] <= a]
    if bawah:
        s = max(bawah, key=lambda x: x[0])
        return ('BAWAH', s, a - s[0])
    return (None, None, 0)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else r'd:\DUMP\d64.txt'
    if not os.path.isfile(path):
        print('TIADA dump:', path)
        print('Muat turun:')
        print('  https://raw.githubusercontent.com/blazervng/gta-2.10/main/')
        print('  dumps_libGTASA_32and64/DUMP%202.1%20(64).txt')
        return 1

    syms = baca_dump(path)
    print('dump: %s' % path)
    print('simbol: %d (termasuk LOCAL/statik)' % len(syms))
    print()

    jenis_kira = {}
    for s in syms:
        jenis_kira[s[3]] = jenis_kira.get(s[3], 0) + 1
    print('ikuts jenis:', ', '.join('%s=%d' % (k, v)
                                   for k, v in sorted(jenis_kira.items())))
    print()

    print('%-11s %-7s %-9s %-6s %s'
          % ('ALAMAT', 'PADAN', 'OFFSET', 'JENIS', 'NAMA'))
    print('-' * 100)

    selesai = 0
    for a in TANPA:
        j, s, off = cari(syms, a)
        if j == 'DALAM':
            selesai += 1
            print('0x%-9X %-7s +0x%-6X %-6s %s'
                  % (a, j, off, s[3], s[4][:56]))
        elif j == 'BAWAH':
            print('0x%-9X %-7s +0x%-6X %-6s %s (jauh)'
                  % (a, j, off, s[3], s[4][:44]))
        else:
            print('0x%-9X %-7s %-8s %-6s %s' % (a, '-', '-', '-', '(tiada)'))

    print()
    print('RINGKASAN:')
    print('  %d / %d alamat kini ada simbol dari dump' % (selesai, len(TANPA)))
    print()
    if selesai == len(TANPA):
        print('  SEMUA 24 diselesaikan! Gabung dump dgn jadual simbol.')
    elif selesai > 0:
        print('  Gabung simbol dump ke mc_simbol.h untuk yg berjaya.')
    else:
        print('  Dump tidak membantu - alamat mungkin dari binari lain.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
