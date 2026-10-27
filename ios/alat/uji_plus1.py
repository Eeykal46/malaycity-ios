"""Uji hipotesis: adakah alamat "+1" itu artifak ARM32 (Thumb bit)?

Client banyak guna `g_libGTASA + 0xADDR + 1`. Pada ARM32, bit 0 = Thumb.
Pada ARM64 ia TIADA makna. Jika alamat GANJIL, kita baca bait salah.

Ujian: bandingkan pemetaan alamat (a) vs (a+1) vs (a-1).
Jika a+1 memberi simbol yang jauh lebih baik, itu bukti hipotesis.

Jalankan: python ios/alat/uji_plus1.py
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
JNILIBS = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'jniLibs')
CPP = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'cpp', 'samp')

RE_PLUS1 = re.compile(r'g_libGTASA\s*\+\s*(0x[0-9A-Fa-f]+)\s*\+\s*1')
RE_BASE = re.compile(r'g_libGTASA\s*\+\s*(0x[0-9A-Fa-f]+)')
SRC_EXT = ('.cpp', '.h', '.hpp', '.c')
SKIP_DIRS = {'vendor', 'opus', 'imgui', 'armhook'}


def dynsyms(path):
    with open(path, 'rb') as f:
        b = f.read()
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


def kira_plus1():
    n = 0
    lokasi = []
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
                if ln.strip().startswith('//'):
                    continue
                for m in RE_PLUS1.finditer(ln):
                    n += 1
                    lokasi.append((int(m.group(1), 16), rel, i))
    return n, lokasi


def cari(syms, a):
    dalam = [s for s in syms if s[0] <= a < s[0] + max(s[1], 1)]
    if dalam:
        s = max(dalam, key=lambda x: x[0])
        return ('DALAM', s[2], a - s[0])
    return (None, None, 0)


def main():
    so = os.path.join(JNILIBS, 'arm64-v8a', 'libGTASA.so')
    if not os.path.isfile(so):
        print('TIADA:', so)
        return 1
    syms = dynsyms(so)

    n, lokasi = kira_plus1()
    print('rujukan dgn pola `+ 0xADDR + 1` (bukan komen): %d' % n)
    print()

    print('%-11s %-11s %-11s %-30s %s'
          % ('ASAL', 'ASAL+1', 'ASAL-1', 'SIMBOL (pada a+1)', 'NOTA'))
    print('-' * 104)

    ok0 = ok1 = okm1 = 0
    for a, f, ln in lokasi[:40]:
        j0, s0, o0 = cari(syms, a)
        j1, s1, o1 = cari(syms, a + 1)
        jm, sm, om = cari(syms, a - 1)
        if j0:
            ok0 += 1
        if j1:
            ok1 += 1
        if jm:
            okm1 += 1
        nama = (s1[:28] + ' +0x%X' % o1) if s1 else '(tiada)'
        nota = ''
        if not j0 and j1:
            nota = 'a SAHAJA gagal, a+1 BERJAYA'
        print('0x%-9X 0x%-9X 0x%-9X %-30s %s'
              % (a, a + 1, a - 1, nama, nota))

    print()
    print('RINGKASAN (%d rujukan +1 disemak):' % min(40, len(lokasi)))
    print('  alamat ASAL   dlm simbol: %d' % ok0)
    print('  alamat ASAL+1 dlm simbol: %d' % ok1)
    print('  alamat ASAL-1 dlm simbol: %d' % okm1)
    print()
    if ok1 > ok0:
        print('KESIMPULAN: +1 MEMBANTU. Ini artifak ARM32 (Thumb) yg tidak')
        print('  sepatutnya ada pada ARM64. Buang +1 untuk ARM64.')
    elif ok1 == ok0:
        print('KESIMPULAN: +1 TIADA kesan pada pemetaan simbol.')
    else:
        print('KESIMPULAN: +1 MEROSAKKAN. Jangan guna +1.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
