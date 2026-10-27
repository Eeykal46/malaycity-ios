"""Sahkan mc_ios_shim.mm meliputi SEMUA simbol Android yang .so perlukan.

Jalankan: python ios/alat/uji_shim.py

Ini ujian paling penting untuk Fasa 3: kalau satu simbol terlepas, enjin
GAGAL PAUT (link) dan tiada apa boleh dimuatkan. Tiada tekaan - senarai
diambil dari binari sebenar.
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHIM = os.path.join(HERE, '..', 'enjin', 'mc_ios_shim.mm')
JNILIBS = os.path.join(HERE, '..', '..', 'mobile', 'app', 'src', 'main',
                       'jniLibs', 'arm64-v8a')

ANDROID_PREFIX = ("AAsset", "ANativeWindow", "__android_log", "__system_property",
                  "android_", "ALooper", "slCreate", "SL_IID")


def imports_so(path):
    with open(path, 'rb') as f:
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
        secs.append(dict(name=name, type=typ, off=off, size=size, ent=ent))
    base = secs[e_shstrndx]['off']
    for s in secs:
        end = b.index(b'\0', base + s['name'])
        s['n'] = b[base + s['name']:end].decode('latin-1')
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
    if not os.path.isfile(SHIM):
        print('GAGAL: shim tak wujud:', SHIM)
        return 1

    perlu = set()
    if os.path.isdir(JNILIBS):
        for fn in os.listdir(JNILIBS):
            if fn.endswith('.so'):
                for s in imports_so(os.path.join(JNILIBS, fn)):
                    if s.startswith(ANDROID_PREFIX):
                        perlu.add(s)

    with open(SHIM, 'r', encoding='utf-8', errors='replace') as f:
        shim_src = f.read()

    # buang komen supaya pengisytiharan dlm komen tidak dikira
    kod = '\n'.join(l for l in shim_src.split('\n')
                    if not l.strip().startswith('//')
                    and not l.strip().startswith('*')
                    and not l.strip().startswith('/*'))

    print('shim : %s' % os.path.relpath(SHIM, HERE))
    print('lib  : %d simbol Android dikesan' % len(perlu))
    print()

    hilang = []
    for s in sorted(perlu):
        # simbol mesti muncul sebagai pengisytiharan/pelaksanaan, bukan komen
        pat = re.compile(r'\b' + re.escape(s) + r'\b')
        if not pat.search(kod):
            hilang.append(s)

    for s in sorted(perlu):
        tanda = 'HILANG' if s in hilang else 'ADA'
        print('  [%-6s] %s' % (tanda, s))

    print()
    if hilang:
        print('GAGAL: %d simbol tiada dlm shim -> enjin tak boleh paut.' % len(hilang))
        for s in hilang:
            print('   - %s' % s)
        return 1

    print('LULUS: semua %d simbol ada dlm shim.' % len(perlu))
    print('Nota: ADA != berfungsi. Audio (OpenSL) masih stub - lihat TODO.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
