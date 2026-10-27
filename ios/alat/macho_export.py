"""Senarai API & kelas dlm framework Mach-O (iOS) - nilai kebolehan guna semula.

Jalankan: python ios/alat/macho_export.py <binari> [kata-kunci ...]

Contoh:
    python ios/alat/macho_export.py ReSAEngine samp raknet net connect

Tujuan: kalau kita mahu guna semula binari orang lain, ia mesti ada API yg
didokumen/dieksport. Kalau ia hanya simbol dalaman tanpa header, ia tidak
boleh dipanggil tanpa reverse-engineering penuh.
"""
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2

CPU = {0x0100000C: 'arm64', 0x01000007: 'x86_64'}
FT = {1: 'MH_OBJECT', 2: 'MH_EXECUTE', 6: 'MH_DYLIB', 8: 'MH_BUNDLE'}


def slices(b):
    """Bagi fat/lipo binary, pulangkan [(offset, size)]. Selain itu [(0, len)]."""
    magic = struct.unpack_from('>I', b, 0)[0]
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        n = struct.unpack_from('>I', b, 4)[0]
        out = []
        wide = magic == 0xCAFEBABF
        for i in range(n):
            o = 8 + i * (32 if wide else 20)
            if wide:
                _cpu, _sub, off, size = struct.unpack_from('>IIQQ', b, o)
            else:
                _cpu, _sub, off, size = struct.unpack_from('>IIII', b, o)
            out.append((off, size))
        return out
    return [(0, len(b))]


def parse(b, base):
    magic = struct.unpack_from('<I', b, base)[0]
    if magic != MH_MAGIC_64:
        raise ValueError('bukan Mach-O 64 (magic 0x%08X)' % magic)
    cputype, cpusub, filetype, ncmds, sizeofcmds, flags, _r = \
        struct.unpack_from('<IIIIIII', b, base + 4)

    off = base + 32
    symtab = None
    sections = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', b, off)
        if cmd == LC_SYMTAB:
            symoff, nsyms, stroff, strsize = struct.unpack_from('<IIII', b, off + 8)
            symtab = (symoff, nsyms, stroff, strsize)
        elif cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from('<I', b, off + 64)[0]
            so = off + 72
            for _s in range(nsects):
                sect = b[so:so + 16].rstrip(b'\0').decode('latin-1')
                seg = b[so + 16:so + 32].rstrip(b'\0').decode('latin-1')
                _addr, size = struct.unpack_from('<QQ', b, so + 32)
                offset = struct.unpack_from('<I', b, so + 48)[0]
                sections.append((seg, sect, size, offset))
                so += 80
        off += cmdsize
    return cputype, filetype, symtab, sections


def symbols(b, base, symtab):
    symoff, nsyms, stroff, strsize = symtab
    strtab = b[base + stroff: base + stroff + strsize]
    out = []
    for i in range(nsyms):
        o = base + symoff + i * 16
        if o + 16 > len(b):
            break
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', b, o)
        if n_strx == 0 or n_strx >= len(strtab):
            continue
        end = strtab.find(b'\0', n_strx)
        if end < 0:
            continue
        name = strtab[n_strx:end].decode('latin-1', 'replace')
        external = (n_type & 0x01) != 0
        out.append((name, external, n_sect, n_value))
    return out


def main():
    if len(sys.argv) < 2:
        print('Guna: python macho_export.py <binari> [kata-kunci ...]')
        return 1
    path = sys.argv[1]
    keys = [k.lower() for k in sys.argv[2:]]

    with open(path, 'rb') as f:
        b = f.read()

    print('fail: %s (%.2f MB)' % (path, len(b) / 1024**2))
    for idx, (off, size) in enumerate(slices(b)):
        try:
            cputype, filetype, symtab, sections = parse(b, off)
        except Exception as e:
            print('  slice %d: %s' % (idx, e))
            continue
        print()
        print('slice %d: %s, %s' % (idx, CPU.get(cputype, hex(cputype)),
                                     FT.get(filetype, filetype)))
        print('  seksyen: %d, symtab: %s' % (len(sections), 'ada' if symtab else 'TIADA'))
        if not symtab:
            continue
        syms = symbols(b, off, symtab)
        ext = [s for s in syms if s[1]]
        print('  simbol jumlah: %d (dieksport: %d)' % (len(syms), len(ext)))
        if not keys:
            continue
        print()
        print('  padanan kata kunci:')
        for k in keys:
            hit = [s[0] for s in ext if k in s[0].lower()]
            print('    %-12s %d' % (k, len(hit)))
            for h in hit[:12]:
                print('        %s' % h)
            if len(hit) > 12:
                print('        ... dan %d lagi' % (len(hit) - 12))
    return 0


if __name__ == '__main__':
    sys.exit(main())
