"""Semak simbol dlm binari Mach-O - adakah shim kita benar-benar dilink?

Jalankan: python ios/alat/semak_simbol_binari.py <binari> [kata-kunci]

Contoh:
    python ios/alat/semak_simbol_binari.py McLauncher AAsset __android_log slCreate

Menjawab: adakah mc_ios_shim.mm masuk ke dlm binari akhir, atau di-strip?
"""
import struct
import sys

LC_SYMTAB = 0x2


def main():
    if len(sys.argv) < 2:
        print('Guna: python semak_simbol_binari.py <binari> [kata kunci...]')
        return 1
    path = sys.argv[1]
    keys = sys.argv[2:]

    with open(path, 'rb') as f:
        b = f.read()

    magic, = struct.unpack_from('<I', b, 0)
    if magic != 0xFEEDFACF:
        print('bukan Mach-O 64: 0x%08X' % magic)
        return 1

    ncmds, = struct.unpack_from('<I', b, 16)
    off = 32
    symtab = None
    for _ in range(ncmds):
        cmd, sz = struct.unpack_from('<II', b, off)
        if cmd == LC_SYMTAB:
            symtab = struct.unpack_from('<IIII', b, off + 8)
        off += sz
    if not symtab:
        print('TIADA symtab')
        return 1

    symoff, nsyms, stroff, strsize = symtab
    strtab = b[stroff:stroff + strsize]
    names = []
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
        names.append(strtab[n_strx:end].decode('latin-1', 'replace'))

    print('binari : %s' % path)
    print('simbol : %d' % len(names))
    print()

    if not keys:
        print('(tiada kata kunci - senarai 30 simbol pertama)')
        for n in names[:30]:
            print('  %s' % n)
        return 0

    for k in keys:
        hit = [n for n in names if k in n]
        print('%-22s %d padanan' % (k, len(hit)))
        for h in hit[:8]:
            print('    %s' % h)
        if len(hit) > 8:
            print('    ... dan %d lagi' % (len(hit) - 8))
    return 0


if __name__ == '__main__':
    sys.exit(main())
