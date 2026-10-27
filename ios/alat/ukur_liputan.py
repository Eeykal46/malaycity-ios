"""Ukur liputan source gtasa-android-sourcecode (isweikton).

Menjawab: adakah ini enjin GTA SA YANG BOLEH JALAN, atau himpunan fungsi yg
disalin untuk rujukan?

Penanda yang disemak:
  - D3D9 / Direct3D  -> Windows sahaja dalam amalan (iOS tiada)
  - librw            -> enjin render boleh alih
  - stub             -> fail < 200 bait (fungsi belum ditulis)
  - main()           -> ada titik masuk

Jalankan: python ios/alat/ukur_liputan.py <folder-repo>
"""
import os
import sys


def kira(folder):
    d3d9 = []
    librw = []
    stub = 0
    isi = 0
    main_cpp = None

    for dirpath, _dirs, files in os.walk(folder):
        if '.git' in dirpath:
            continue
        for fn in files:
            if not fn.endswith(('.cpp', '.h', '.hpp', '.c')):
                continue
            p = os.path.join(dirpath, fn)
            try:
                with open(p, 'r', encoding='utf-8', errors='replace') as f:
                    txt = f.read()
            except Exception:
                continue
            low = txt.lower()
            if 'd3d' in low or 'direct3d' in low or 'idirect3d' in low:
                d3d9.append(os.path.relpath(p, folder))
            if 'librw' in low or 'rwcore' in low or 'rwd3d' in low:
                librw.append(os.path.relpath(p, folder))
            if fn == 'main.cpp' and 'wWinMain' in txt or 'int main(' in txt:
                main_cpp = p
            if p.endswith('.cpp'):
                if os.path.getsize(p) < 200:
                    stub += 1
                else:
                    isi += 1
    return d3d9, librw, stub, isi, main_cpp


def main():
    if len(sys.argv) < 2:
        print('Guna: python ukur_liputan.py <folder-repo>')
        return 1
    folder = sys.argv[1]
    if not os.path.isdir(folder):
        print('Folder tak wujud: %s' % folder)
        return 1

    d3d9, librw, stub, isi, main_cpp = kira(folder)

    print('folder: %s' % folder)
    print()
    print('  .cpp berisi (>200 bait) : %d' % isi)
    print('  .cpp stub  (<200 bait)  : %d' % stub)
    print('  fail guna D3D9/Direct3D : %d' % len(d3d9))
    print('  fail guna librw         : %d' % len(librw))
    print('  ada main()              : %s' % ('ya' if main_cpp else 'tidak'))
    print()

    if d3d9:
        print('  Fail D3D9 (Windows sahaja - iOS tiada Direct3D):')
        for f in d3d9[:15]:
            print('      %s' % f)
        if len(d3d9) > 15:
            print('      ... dan %d lagi' % (len(d3d9) - 15))
        print()

    # kesimpulan
    print('KESIMPULAN:')
    if len(d3d9) > 0:
        print('  Source ini ditulis untuk DIRECT3D 9 (Windows).')
        print('  iOS tiada Direct3D sama sekali -> semua fail D3D9 mesti ditulis')
        print('  semula untuk Metal. Ini bukan "port", ini tulis semula renderer.')
    if librw:
        print('  Ada librw (%d fail) - enjin render boleh alih. Ini satu-satunya')
        print('  bahagian yang mungkin dipindah, TETAPI librw pun tiada backend Metal.')
    if stub > isi:
        print('  Majoriti .cpp ialah stub - kod belum ditulis.')
    else:
        print('  Majoriti .cpp berisi (ada kod sebenar), tetapi lihat amaran D3D9.')
    print()
    print('  Saiz keseluruhan kod: %.2f MB' % (
        sum(os.path.getsize(os.path.join(dp, f))
            for dp, _d, fs in os.walk(folder) if '.git' not in dp
            for f in fs if f.endswith(('.cpp', '.h', '.c'))) / 1024**2))
    print('  (Enjin GTA SA sebenar > 100 MB kod C++.)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
