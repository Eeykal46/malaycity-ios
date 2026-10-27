"""Semak 33 alamat yang TIADA simbol - satu per satu.

Jalankan: python ios/alat/semak_33.py [--penuh]

Untuk setiap alamat tanpa simbol, tunjuk:
  - fail & baris ia digunakan
  - konteks kod sekeliling (apa yg client cuba baca/tulis)
  - jika ada simbol terdekat: jarak & nama
  - pengelasan: fungsi statik? data? vtable?

Tujuan: tentukan sama ada setiap satu boleh diselesaikan atau mesti
dipetakan manual untuk iOS.
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
JNILIBS = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'jniLibs')
CPP = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'cpp', 'samp')

RE_BASE = re.compile(r'g_libGTASA\s*\+\s*(0x[0-9A-Fa-f]+)')
SRC_EXT = ('.cpp', '.h', '.hpp', '.c')
SKIP_DIRS = {'vendor', 'opus', 'imgui', 'armhook'}


def dynsyms(path):
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
        secs.append(dict(name=name, off=off, size=size, ent=ent))
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
        if st_shndx == 0 or st_name == 0:
            continue
        end = ds.index(b'\0', st_name)
        out.append((st_value, st_size, ds[st_name:end].decode('latin-1')))
    return sorted(out)


def kumpul_penggunaan():
    """{alamat: [(fail, baris, teks)]}"""
    guna = {}
    for dirpath, dirnames, filenames in os.walk(CPP):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(SRC_EXT):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, CPP)
            try:
                with open(p, 'r', encoding='utf-8', errors='replace') as f:
                    lines = f.readlines()
            except Exception:
                continue
            for i, ln in enumerate(lines, 1):
                for m in RE_BASE.finditer(ln):
                    a = int(m.group(1), 16)
                    guna.setdefault(a, []).append((rel, i, ln.strip()))
    return guna


def klasifikasi(addr, syms):
    """Cuba teka jenis alamat tanpa simbol."""
    if addr < 0x20000:
        return 'kod awal / header ELF'
    bawah = [s for s in syms if s[0] < addr]
    if not bawah:
        return 'tiada simbol sebelum'
    s = max(bawah, key=lambda x: x[0])
    jarak = addr - s[0]
    saiz = max(s[1], 1)
    if jarak < saiz:
        return 'DALAM %s +0x%X' % (s[2][:40], jarak)
    if jarak < 0x100:
        return 'selepas %s +0x%X (mungkin fungsi kecil)' % (s[2][:34], jarak)
    return 'jauh dari %s (0x%X)' % (s[2][:34], jarak)


def main():
    penuh = '--penuh' in sys.argv
    so = os.path.join(JNILIBS, 'arm64-v8a', 'libGTASA.so')
    if not os.path.isfile(so):
        print('TIADA:', so)
        return 1

    syms = dynsyms(so)
    guna = kumpul_penggunaan()
    semua = sorted(guna)

    tanpa = [a for a in semua
             if not any(s[0] <= a < s[0] + max(s[1], 1) for s in syms)]

    print('alamat unik   : %d' % len(semua))
    print('tanpa simbol  : %d' % len(tanpa))
    print()

    # kumpul ikut fail
    ikut_fail = {}
    for a in tanpa:
        for f, ln, txt in guna.get(a, []):
            ikut_fail.setdefault(f, []).append((a, ln, txt))

    print('=' * 70)
    print('IKUT FAIL SUMBER')
    print('=' * 70)
    for f in sorted(ikut_fail, key=lambda x: -len(ikut_fail[x])):
        print('%-34s %d alamat' % (f, len(ikut_fail[f])))
    print()

    print('=' * 70)
    print('BUTIRAN SETIAP ALAMAT')
    print('=' * 70)
    for a in tanpa:
        print()
        print('0x%X   %s' % (a, klasifikasi(a, syms)))
        for f, ln, txt in guna.get(a, []):
            print('    %s:%d' % (f, ln))
            if penuh or len(txt) < 140:
                print('        %s' % txt[:132])
            else:
                print('        %s...' % txt[:129])

    print()
    print('=' * 70)
    print('RINGKASAN')
    print('=' * 70)
    kira = {}
    for a in tanpa:
        k = klasifikasi(a, syms).split(' ')[0]
        kira[k] = kira.get(k, 0) + 1
    for k, v in sorted(kira.items(), key=lambda x: -x[1]):
        print('  %-24s %d' % (k, v))
    return 0


if __name__ == '__main__':
    sys.exit(main())
