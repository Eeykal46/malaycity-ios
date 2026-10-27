"""Petakan ALAMAT KERAS dlm client ke NAMA SIMBOL dlm libGTASA.so.

MASALAH: client SA-MP menyentuh enjin melalui `g_libGTASA + 0x2BD618`.
Alamat itu sah HANYA untuk satu binari (libGTASA arm64 Android). Binari iOS
berlainan -> setiap satu mesti dipetakan semula (kerja besar).

JALAN KELUAR: kalau alamat boleh dipadankan ke NAMA SIMBOL yang dieksport,
client boleh guna dlsym() dan jadi mudah alih.

Jalankan: python ios/alat/peta_alamat_simbol.py
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


def dynsyms(so_path):
    """[(value, size, name)] bagi simbol dieksport."""
    with open(so_path, 'rb') as f:
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
    return out


def alamat_dlm_kod():
    hasil = []
    for dirpath, dirnames, filenames in os.walk(CPP):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(SRC_EXT):
                continue
            p = os.path.join(dirpath, fn)
            try:
                with open(p, 'r', encoding='utf-8', errors='replace') as f:
                    txt = f.read()
            except Exception:
                continue
            for m in RE_BASE.finditer(txt):
                hasil.append((int(m.group(1), 16), os.path.relpath(p, CPP)))
    return hasil


def cari_simbol(syms, addr):
    tepat = [s for s in syms if s[0] == addr]
    if tepat:
        return ('tepat', tepat[0])
    dalam = [s for s in syms if s[0] < addr < s[0] + max(s[1], 1)]
    if dalam:
        return ('dalam', dalam[0])
    bawah = [s for s in syms if s[0] < addr]
    if bawah:
        return ('bawah', max(bawah, key=lambda s: s[0]))
    return (None, None)


def main():
    so = os.path.join(JNILIBS, 'arm64-v8a', 'libGTASA.so')
    if not os.path.isfile(so):
        print('TIADA:', so)
        print('(jalankan dalam repo penuh)')
        return 1

    syms = dynsyms(so)
    if not syms:
        print('TIADA .dynsym dlm', so)
        return 1
    syms.sort()
    print('libGTASA.so : %d simbol dieksport' % len(syms))

    adr = alamat_dlm_kod()
    uniq = sorted({a for a, _ in adr})
    print('sumber C++  : %d rujukan, %d alamat unik' % (len(adr), len(uniq)))
    print()

    kira = {'tepat': 0, 'dalam': 0, 'bawah': 0, None: 0}
    tiada = []
    contoh = []
    for a in uniq:
        jenis, s = cari_simbol(syms, a)
        kira[jenis] += 1
        if jenis is None:
            tiada.append(a)
        elif len(contoh) < 15:
            contoh.append((a, jenis, s[2], s[0]))

    print('HASIL PEMETAAN')
    print('  tepat (alamat = simbol)   : %d' % kira['tepat'])
    print('  dalam (dlm julat simbol)  : %d' % kira['dalam'])
    print('  bawah (simbol terdekat)   : %d' % kira['bawah'])
    print('  TIADA padanan             : %d' % kira[None])
    print()

    boleh = kira['tepat'] + kira['dalam']
    jumlah = len(uniq)
    peratus = (100.0 * boleh / jumlah) if jumlah else 0
    print('  BOLEH dipetakan tepat     : %d / %d (%.0f%%)'
          % (boleh, jumlah, peratus))
    print()

    if contoh:
        print('CONTOH (alamat -> simbol):')
        for a, jenis, nm, sval in contoh:
            print('  0x%-8X %-6s %s' % (a, jenis, nm[:66]))
        print()

    if tiada:
        print('ALAMAT TIADA SIMBOL (%d) - kerja manual:' % len(tiada))
        for a in tiada[:20]:
            print('  0x%X' % a)
        if len(tiada) > 20:
            print('  ... dan %d lagi' % (len(tiada) - 20))
        print()

    print('KESIMPULAN:')
    if jumlah == 0:
        print('  tiada alamat dikesan - semak laluan sumber.')
    elif boleh == jumlah:
        print('  SEMUA alamat boleh jadi nama simbol -> client boleh mudah alih!')
        print('  Langkah seterusnya: jana mc_simbol.h dgn MC_ADDR().')
    elif boleh >= jumlah * 0.8:
        print('  %.0f%% boleh dipetakan. Baki %d perlu semak manual.'
              % (peratus, jumlah - boleh))
        print('  Masih berbaloi: majoriti kerja hilang.')
    else:
        print('  Kurang 80%% boleh dipetakan (%.0f%%).' % peratus)
        print('  dlsym TIDAK cukup; peta alamat manual masih perlu.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

