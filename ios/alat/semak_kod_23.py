"""Semak 23 alamat KOD tanpa simbol - cari fungsi yang mengandunginya.

Jalankan: python ios/alat/semak_kod_23.py

Untuk setiap alamat KOD tanpa simbol:
  1. Lihat arahan mesin di alamat itu (ARM64) - adakah ia pangkal fungsi?
  2. ARM64: pangkal fungsi biasa = STP x29,x30,[sp,#-N]! atau SUB sp,sp,#N
     atau BTI/PACIASP. Jika ya, alamat itu = fungsi tanpa nama.
  3. Cari simbol terdekat di ATAS - mungkin ia fungsi statik.
  4. Kira jarak ke simbol sebelum.

Tujuan: tentukan sama ada alamat ini BOLEH dipetakan ke simbol terdekat
(dgn offset) atau benar-benar tiada simbol.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
JNILIBS = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'jniLibs')

TANPA = [
    0x6D008, 0x1984A5, 0x1A3A69, 0x1AE8DE, 0x1B2558, 0x1BC269,
    0x1C2C90, 0x1DB9B0, 0x1DBA64, 0x1DBABC, 0x1E3A28, 0x1E9BC8,
    0x1E9C64, 0x1E9C80, 0x1EAC8C, 0x26B03C, 0x26B046, 0x2B0D5C,
    0x2CB7C8, 0x2CC144, 0x362E02, 0x5C9014, 0x5C9120,
]

PT_LOAD = 1
PF_X = 1


def baca_so(path):
    with open(path, 'rb') as f:
        return f.read()


def segmen_kod(b):
    e_phoff, = struct.unpack_from('<Q', b, 0x20)
    e_phentsize, e_phnum = struct.unpack_from('<HH', b, 0x36)
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        p_type, p_flags = struct.unpack_from('<II', b, o)
        if p_type != PT_LOAD or not (p_flags & PF_X):
            continue
        p_offset, = struct.unpack_from('<Q', b, o + 8)
        p_vaddr, = struct.unpack_from('<Q', b, o + 16)
        p_filesz, = struct.unpack_from('<Q', b, o + 32)
        return p_vaddr, p_offset, p_filesz
    return 0, 0, 0


def insn_degil(b, vaddr, fileoff, vbase):
    """Bait 4 pada alamat maya."""
    fi = fileoff + (vaddr - vbase)
    if fi < 0 or fi + 4 > len(b):
        return None
    return struct.unpack_from('<I', b, fi)[0]


def hurai_pangkal_fungsi(insn):
    """Cuba teka sama ada arahan ini pangkal fungsi ARM64."""
    if insn is None:
        return 'tiada data'
    # STP x29, x30, [sp, #-N]!   prologue biasa
    if (insn & 0xFFC07FFF) == 0xA9807BFD:
        return 'STP x29,x30 (prologue)'
    # SUB sp, sp, #N
    if (insn & 0xFF8003FF) == 0xD10003FF:
        return 'SUB sp (prologue)'
    # BTI c
    if insn == 0xD503245F:
        return 'BTI c (pangkal fungsi)'
    # PACIASP
    if insn == 0xD503233F:
        return 'PACIASP (pangkal fungsi)'
    # RET
    if insn == 0xD65F03C0:
        return 'RET (hujung fungsi)'
    # NOP
    if insn == 0xD503201F:
        return 'NOP'
    # B (tak bersyarat)
    if (insn & 0xFC000000) == 0x14000000:
        return 'B (lompat)'
    return 'bukan pangkal fungsi'


def dynsyms(b):
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


def main():
    so = os.path.join(JNILIBS, 'arm64-v8a', 'libGTASA.so')
    if not os.path.isfile(so):
        print('TIADA:', so)
        return 1
    b = baca_so(so)
    vbase, fileoff, filesz = segmen_kod(b)
    syms = dynsyms(b)

    print('segmen kod: vaddr=0x%X fileoff=0x%X saiz=0x%X' % (vbase, fileoff, filesz))
    print()
    pangkal = 0
    tiada_simbol_langsung = 0
    print('%-11s %-30s %-46s %s'
          % ('ALAMAT', 'ARAHAN', 'SIMBOL SEBELUM', 'JARAK'))
    print('-' * 116)
    for a in TANPA:
        ins = insn_degil(b, a, fileoff, vbase)
        jenis = hurai_pangkal_fungsi(ins)
        if 'pangkal' in jenis or 'prologue' in jenis:
            pangkal += 1

        bawah = [s for s in syms if s[0] < a]
        if bawah:
            s = max(bawah, key=lambda x: x[0])
            nm = s[2][:42]
            jarak = a - s[0]
            jt = '0x%X' % jarak
            saiz = max(s[1], 1)
            if jarak < saiz:
                jt += ' (DALAM)'
            elif jarak < 0x200:
                jt += ' (dekat)'
            else:
                jt += ' (jauh)'
        else:
            nm = '(tiada simbol < alamat)'
            jt = '-'
            tiada_simbol_langsung += 1

        print('0x%-9X %-30s %-46s %s' % (a, jenis, nm, jt))

    print()
    print('RINGKASAN:')
    print('  alamat dalam segmen KOD          : %d' % len(TANPA))
    print('  kelihatan PANGKAL fungsi ARM64   : %d' % pangkal)
    print('  tiada simbol langsung di bawah   : %d' % tiada_simbol_langsung)
    print('  (termasuk alamat +1 di hujung - lihat nota)')
    print()
    print('NOTA PENTING: banyak client guna `g_libGTASA + 0xADDR + 1`.')
    print('  +1 = bit Thumb pada ARM32. Pada ARM64 ia TIADA makna - alamat ganjil')
    print('  bermakna kita sedang baca bait salah. Semak satu per satu:')
    print('  alamat GENAP = mungkin pangkal fungsi sebenar dan patut dipakai.')
    print()
    print('IMPLIKASI: dlsym TIDAK boleh mencari fungsi tanpa nama.')
    print('  Pilihan: (1) peta alamat relatif dgn binari iOS,')
    print('           (2) signature scan (corak bait) - kekal merentas versi.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
