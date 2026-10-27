"""Senarai import yg perlu di-shim, tepat dari binari.

Jalankan: python ios/alat/senarai_shim.py [folder jniLibs/arm64-v8a]

Menghasilkan senarai simbol ELF yg TIADA di iOS, supaya mc_ios_shim.mm
boleh ditulis padan dengannya. Tiada tekaan.
"""
import os
import struct
import sys

ANDROID_PREFIX = ("AAsset", "ANativeWindow", "__android_log", "__system_property",
                  "android_", "ALooper", "AInputQueue", "AMotionEvent")


def imports(path):
    with open(path, "rb") as f:
        b = f.read()
    if b[:4] != b'\x7fELF' or b[4] != 2:
        return []
    e_shoff, = struct.unpack_from('<Q', b, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHH', b, 0x3A)

    secs = []
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        name, typ, flags, addr, off, size, link, info, align, ent = \
            struct.unpack_from('<IIQQQQIIQQ', b, o)
        secs.append(dict(name=name, type=typ, off=off, size=size,
                         link=link, ent=ent))

    def secname(s):
        base = secs[e_shstrndx]['off']
        end = b.index(b'\0', base + s['name'])
        return b[base + s['name']:end].decode('latin-1')

    for s in secs:
        s['n'] = secname(s)

    dynsym = next((s for s in secs if s['n'] == '.dynsym'), None)
    dynstr = next((s for s in secs if s['n'] == '.dynstr'), None)
    if not dynsym or not dynstr:
        return []

    ds = b[dynstr['off']:dynstr['off'] + dynstr['size']]
    ent = dynsym['ent'] or 24
    out = []
    for o in range(dynsym['off'], dynsym['off'] + dynsym['size'] - ent + 1, ent):
        st_name, st_info, st_other, st_shndx, st_value, st_size = \
            struct.unpack_from('<IBBHQQ', b, o)
        if st_shndx != 0 or st_name == 0:
            continue
        end = ds.index(b'\0', st_name)
        out.append(ds[st_name:end].decode('latin-1'))
    return out


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', '..', 'mobile',
        'app', 'src', 'main', 'jniLibs', 'arm64-v8a')
    if not os.path.isdir(base):
        print('Folder tak jumpa:', base)
        return 1

    semua = {}
    for fn in sorted(os.listdir(base)):
        if not fn.endswith('.so'):
            continue
        imps = imports(os.path.join(base, fn))
        perlu = sorted({s for s in imps
                        if s.startswith(ANDROID_PREFIX)
                        or s.startswith('sl') or s.startswith('SL_IID')})
        semua[fn] = perlu

    print('SENARAI SIMBOL YG PERLU DI-SHIM (tepat dari .so)\n')
    jumlah = set()
    for fn, perlu in semua.items():
        if not perlu:
            continue
        print('%s : %d' % (fn, len(perlu)))
        for s in perlu:
            print('    %s' % s)
            jumlah.add(s)
        print()
    print('JUMLAH UNIK: %d simbol' % len(jumlah))
    print()
    print('Semua ini mesti ada dlm mc_ios_shim.mm:')
    for s in sorted(jumlah):
        print('  - %s' % s)
    return 0


if __name__ == '__main__':
    sys.exit(main())
