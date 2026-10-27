"""Pengawal: pastikan TIADA dlopen berisiko dalam kod iOS.

CRASH 28 Okt: app tidak boleh dibuka kerana dlopen() dipanggil pada dylib
sintetik / fail ELF. dyld iOS boleh crash (bukan pulangkan nil) untuk fail
bukan-Mach-O atau dylib tanpa kod.

Peraturan selepas ini:
  - dlopen HANYA dibenarkan pada:
      * laluan sistem (/usr/lib/...)
      * fail yang SUDAH disahkan Mach-O melalui magic 4 bait
  - dlopen pada fail ELF / sintetik = GAGAL build

Jalankan: python ios/alat/uji_dlopen_selamat.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT_DIR = os.path.join(HERE, '..', 'McLauncher')

HARAM = [
    # (corak, sebab)
    (r'dlopen\s*\(\s*elfPath',
     'dlopen pada fail ELF - dyld akan crash'),
    (r'dlopen\s*\(\s*dylibPath',
     'dlopen pada dylib sintetik - tiada kod/tandatangan, crash'),
    (r'dlopen\s*\(\s*copyPath',
     'dlopen pada salinan executable - bukan dylib sah'),
    (r'dlopen\s*\([^)]*probe',
     'dlopen pada fail ujian - guna semakan magic sahaja'),
]


def main():
    gagal = 0
    fail_disemak = 0

    print('semak dlopen berisiko dlm %s' % os.path.relpath(SWIFT_DIR, HERE))
    print()

    for fn in sorted(os.listdir(SWIFT_DIR)):
        if not fn.endswith('.swift'):
            continue
        fail_disemak += 1
        p = os.path.join(SWIFT_DIR, fn)
        with open(p, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()

        for i, ln in enumerate(lines, 1):
            # buang komen
            kod = ln.split('//')[0]
            if not kod.strip():
                continue
            for pat, sebab in HARAM:
                if re.search(pat, kod):
                    print('  GAGAL  %s:%d' % (fn, i))
                    print('         %s' % ln.strip()[:88])
                    print('         sebab: %s' % sebab)
                    gagal += 1

    print()
    print('fail disemak: %d' % fail_disemak)

    # kira dlopen yang tinggal (mesti hanya pada laluan sistem)
    jumlah_dlopen = 0
    for fn in sorted(os.listdir(SWIFT_DIR)):
        if not fn.endswith('.swift'):
            continue
        with open(os.path.join(SWIFT_DIR, fn), 'r',
                  encoding='utf-8', errors='replace') as f:
            for ln in f:
                kod = ln.split('//')[0]
                if 'dlopen(' in kod:
                    jumlah_dlopen += 1
    print('dlopen tinggal: %d (mesti pada laluan sistem atau selepas semakan magic)'
          % jumlah_dlopen)
    print()

    if gagal:
        print('GAGAL: %d dlopen berisiko -> app akan crash pada peranti.' % gagal)
        return 1
    print('LULUS: tiada dlopen berisiko.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
