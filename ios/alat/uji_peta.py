"""Uji jadual simbol + sahkan mc_peta.cpp boleh dikompil (secara struktur).

Jalankan: python ios/alat/uji_peta.py

Menyemak:
  1. mc_simbol.h dijana dan sah (199 entri, 166 ada simbol)
  2. setiap simbol yang dipilih BENAR-BENAR wujud dlm .dynsym libGTASA.so
  3. offset tidak melebihi saiz simbol
  4. mc_peta.cpp/h ada fungsi yang dijanjikan
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SO = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'jniLibs',
                  'arm64-v8a', 'libGTASA.so')
HDR = os.path.join(HERE, '..', 'enjin', 'mc_simbol.h')
PETA_CPP = os.path.join(HERE, '..', 'enjin', 'mc_peta.cpp')
PETA_H = os.path.join(HERE, '..', 'enjin', 'mc_peta.h')

gagal = 0


def uji(nama, ok, info=''):
    global gagal
    print(('  OK   ' if ok else '  GAGAL') + '  ' + nama + ('' if ok else '  ' + info))
    if not ok:
        gagal += 1


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
    out = {}
    for o in range(dynsym['off'], dynsym['off'] + dynsym['size'] - ent + 1, ent):
        st_name, st_info, st_other, st_shndx, st_value, st_size = \
            struct.unpack_from('<IBBHQQ', b, o)
        if st_shndx == 0 or st_name == 0:
            continue
        end = ds.index(b'\0', st_name)
        out[ds[st_name:end].decode('latin-1')] = (st_value, st_size)
    return out


def main():
    print('1. mc_simbol.h')
    uji('fail wujud', os.path.isfile(HDR))
    if not os.path.isfile(HDR):
        return 1
    src = open(HDR, encoding='utf-8').read()

    m_jum = re.search(r'#define MC_SIMBOL_JUMLAH (\d+)', src)
    m_ok = re.search(r'#define MC_SIMBOL_BERJAYA (\d+)', src)
    uji('MC_SIMBOL_JUMLAH = 199', m_jum and m_jum.group(1) == '199',
        m_jum.group(1) if m_jum else 'tiada')
    uji('MC_SIMBOL_BERJAYA = 166', m_ok and m_ok.group(1) == '166',
        m_ok.group(1) if m_ok else 'tiada')

    # dua bentuk baris: dgn simbol, dan tanpa simbol (komen TIADA SIMBOL)
    entri_ada = re.findall(r'\{ 0x([0-9A-Fa-f]+), "([^"]+)", 0x([0-9A-Fa-f]+) \}', src)
    entri_kosong = re.findall(r'\{ 0x([0-9A-Fa-f]+), 0, 0 \}', src)
    entri = [(a, n, o) for a, n, o in entri_ada] + [(a, None, None) for a in entri_kosong]
    uji('bilangan entri = 199', len(entri) == 199, str(len(entri)))
    uji('entri dgn simbol = 166', len(entri_ada) == 166, str(len(entri_ada)))
    uji('entri tanpa simbol = 33', len(entri_kosong) == 33, str(len(entri_kosong)))

    print()
    print('2. simbol benar-benar wujud dlm libGTASA.so')
    if not os.path.isfile(SO):
        print('  LANGKAU: libGTASA.so tiada (repo slim)')
    else:
        syms = dynsyms(SO)
        uji('banyak simbol', len(syms) > 20000, str(len(syms)))
        hilang = []
        offset_buruk = []
        for addr, nama, off in entri:
            if not nama:
                continue
            if nama not in syms:
                hilang.append(nama)
                continue
            base, size = syms[nama]
            o = int(off, 16)
            if size and o >= size:
                offset_buruk.append((nama, o, size))
        uji('semua simbol wujud dlm .dynsym', not hilang,
            '%d hilang: %s' % (len(hilang), hilang[:3]))
        uji('semua offset dlm julat simbol', not offset_buruk,
            str(offset_buruk[:3]))

    print()
    print('3. mc_peta.cpp / mc_peta.h')
    uji('mc_peta.h wujud', os.path.isfile(PETA_H))
    uji('mc_peta.cpp wujud', os.path.isfile(PETA_CPP))
    if os.path.isfile(PETA_CPP):
        p = open(PETA_CPP, encoding='utf-8').read()
        uji('ada mc_alamat()', 'uintptr_t mc_alamat(' in p)
        uji('ada mc_alamat_berjaya()', 'mc_alamat_berjaya' in p)
        uji('ada mc_alamat_jumlah()', 'mc_alamat_jumlah' in p)
        uji('ada mc_alamat_simbol()', 'mc_alamat_simbol' in p)
        uji('guna dlsym', 'dlsym' in p)
        # dlclose hanya boleh muncul dalam KOMEN (kita sengaja tidak memanggilnya)
        kod = '\n'.join(l for l in p.split('\n')
                        if not l.strip().startswith('//'))
        uji('dlclose TIDAK dipanggil', 'dlclose(' not in kod)
        uji('extern "C"', 'extern "C"' in p)
    if os.path.isfile(PETA_H):
        h = open(PETA_H, encoding='utf-8').read()
        uji('mc_peta.h ada extern C', 'extern "C"' in h)
        uji('mc_peta.h ada include guard', '#ifndef MC_PETA_H' in h)

    print()
    if gagal == 0:
        print('LULUS: jadual simbol sah dan peta boleh dikompil.')
        return 0
    print('GAGAL: %d isu.' % gagal)
    return 1


if __name__ == '__main__':
    sys.exit(main())
