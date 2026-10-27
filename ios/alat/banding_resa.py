"""Bandingkan simbol ReSAEngine (iOS, librw+Metal) dgn libGTASA.so (Android).

SOALAN: ReSA tulis semula enjin GTA SA untuk iOS. Adakah ia guna NAMA FUNGSI
yg sama seperti libGTASA Android? Jika ya, kita boleh rujuk penamaan mereka
untuk 21 alamat yg belum selesai.

Jalankan: python ios/alat/banding_resa.py <ReSAEngine> <libGTASA.so>
"""
import os
import struct
import sys


def macho_syms(path):
    """Simbol dlm Mach-O (dylib)."""
    with open(path, 'rb') as f:
        b = f.read()
    magic, = struct.unpack_from('<I', b, 0)
    if magic != 0xFEEDFACF:
        return []
    ncmds, = struct.unpack_from('<I', b, 16)
    off = 32
    symtab = None
    for _ in range(ncmds):
        cmd, sz = struct.unpack_from('<II', b, off)
        if cmd == 0x2:
            symtab = struct.unpack_from('<IIII', b, off + 8)
        off += sz
    if not symtab:
        return []
    symoff, nsyms, stroff, strsize = symtab
    strtab = b[stroff:stroff + strsize]
    out = []
    for i in range(nsyms):
        o = symoff + i * 16
        if o + 16 > len(b):
            break
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', b, o)
        if n_strx == 0 or n_strx >= len(strtab):
            continue
        end = strtab.find(b'\0', n_strx)
        if end < 0:
            continue
        out.append(strtab[n_strx:end].decode('latin-1', 'replace'))
    return out


def elf_syms(path):
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
        out.append(ds[st_name:end].decode('latin-1'))
    return out


def main():
    if len(sys.argv) < 3:
        print('Guna: python banding_resa.py <ReSAEngine> <libGTASA.so>')
        return 1
    resa_path, gtasa_path = sys.argv[1], sys.argv[2]

    resa = macho_syms(resa_path)
    gtasa = elf_syms(gtasa_path)
    print('ReSAEngine : %d simbol' % len(resa))
    print('libGTASA   : %d simbol' % len(gtasa))
    print()

    # bina set nama C++ (mangled) sahaja
    def mangled(lst):
        return {s for s in lst if s.startswith('_Z')}

    r = mangled(resa)
    g = mangled(gtasa)
    print('nama C++ di-mangle (mula _Z):')
    print('  ReSAEngine : %d' % len(r))
    print('  libGTASA   : %d' % len(g))
    print()

    sama = r & g
    print('SIMBOL C++ SAMA (ada di KEDUA-DUA): %d' % len(sama))
    print()
    for s in sorted(sama)[:40]:
        print('  %s' % s[:90])
    if len(sama) > 40:
        print('  ... dan %d lagi' % (len(sama) - 40))
    print()

    # nama kelas GTA yang kita perlukan (21 alamat tanpa simbol)
    KELAS = ['openglAtomicAllInOnePipelineInit', 'openglWorldSectorAllInOne',
             'CPed', 'CVehicle', 'RQTexture', 'SelectScreen',
             'CGenericGameStorage', 'CPlayerPed', 'CEventNewGangMember',
             'CPools', 'CTimer', 'CGame']
    print('CARI KELAS GTA YANG KITA PERLUKAN dlm ReSAEngine:')
    for k in KELAS:
        hit = [s for s in resa if k.lower() in s.lower()]
        print('  %-40s %d' % (k, len(hit)))
        for h in hit[:4]:
            print('      %s' % h[:86])

    print()
    print('KESIMPULAN:')
    if len(sama) > 100:
        print('  ReSA guna penamaan C++ YANG SAMA. Simbol mereka boleh jadi')
        print('  rujukan untuk 21 alamat kita.')
    elif len(sama) > 0:
        print('  Sebahagian kecil nama sama (%d). ReSA tulis semula, penamaan' % len(sama))
        print('  berbeza. Rujukan terhad.')
    else:
        print('  TIADA nama sama. ReSA tulis semula sepenuhnya (librw), jadi')
        print('  simbolnya tidak boleh dijadikan rujukan untuk alamat kita.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
