"""Jalankan SEMUA ujian iOS launcher (Windows, tanpa Mac/Xcode).

  python d:\\MALAYCITY_FULL\\ios\\uji_semua.py

Ujian ini mengesahkan logik yg diport ke Swift dengan menjalankan semula logik
yang SAMA dalam Python dan membandingkannya dengan tingkah laku Java/HTML asal.
Ia TIDAK menggantikan build sebenar - sintaks Swift hanya disahkan oleh
GitHub Actions (macOS + Xcode).
"""
import subprocess
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))

UJIAN = [
    ('Jambatan JS <-> Swift (11 arahan, 11 event)', ['node', os.path.join(HERE, 'semak_bridge.js')]),
    ('Tab Diagnostik (render + nilai dinamik)', ['node', os.path.join(HERE, 'uji_diagnostik.js')]),
    ('Shim iOS meliputi 20 simbol Android', [sys.executable, os.path.join(HERE, 'alat', 'uji_shim.py')]),
    ('Peta alamat -> simbol (166/199)', [sys.executable, os.path.join(HERE, 'alat', 'uji_peta.py')]),
    ('McIni - settings.ini (komen kekal, round-trip)', [sys.executable, os.path.join(HERE, 'uji_ini.py')]),
    ('McQuery - paket SA-MP UDP i', [sys.executable, os.path.join(HERE, 'uji_query.py')]),
    ('check() - status manifest', [sys.executable, os.path.join(HERE, 'uji_check.py')]),
]

hasil = []
for nama, cmd in UJIAN:
    print('=' * 70)
    print(nama)
    print('=' * 70)
    p = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace')
    print(p.stdout.rstrip())
    if p.stderr.strip():
        print('--- stderr ---')
        print(p.stderr.rstrip())
    hasil.append((nama, p.returncode == 0))
    print()

print('=' * 70)
print('RINGKASAN')
print('=' * 70)
for nama, ok in hasil:
    print(('  LULUS  ' if ok else '  GAGAL  ') + nama)

gagal = sum(1 for _, ok in hasil if not ok)
print()
if gagal == 0:
    print('SEMUA {} ujian LULUS.'.format(len(hasil)))
    print('Langkah seterusnya: push ke GitHub -> Actions "Bina IPA iOS".')
    sys.exit(0)
print('{} daripada {} ujian GAGAL.'.format(gagal, len(hasil)))
sys.exit(1)
