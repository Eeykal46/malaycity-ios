"""Uji pembina dylib minimum: adakah ia menghasilkan Mach-O MH_DYLIB yang SAH?

Port 1:1 logik binaDylibMinimum() dlm MCLoadProbe.swift, kemudian hurai
semula dengan parser Mach-O (alat semak_simbol_binari.py) untuk sahkan.

Jalankan: python ios/alat/uji_dylib.py
"""
import os
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
MH_DYLIB = 6
LC_SEGMENT_64 = 0x19
LC_ID_DYLIB = 0xD


def bina_dylib():
    d = bytearray()

    def u32(v): d.extend(struct.pack('<I', v))
    def u64(v): d.extend(struct.pack('<Q', v))

    segSize = 72 + 80
    idName = b'mcprobe'
    idNamePadded = ((len(idName) + 1) + 7) // 8 * 8
    idSize = 24 + idNamePadded
    textOff = 0x1000
    textSize = 0x1000
    sizeofcmds = segSize + idSize

    # mach_header_64 (32 bait)
    u32(MH_MAGIC_64)
    u32(0x0100000C)      # cputype arm64
    u32(0)
    u32(MH_DYLIB)
    u32(2)               # ncmds
    u32(sizeofcmds)
    u32(0)
    u32(0)

    # LC_SEGMENT_64
    u32(LC_SEGMENT_64)
    u32(segSize)
    d.extend(b'__TEXT'.ljust(16, b'\0'))
    u64(textOff)         # vmaddr
    u64(textSize)        # vmsize
    u64(textOff)         # fileoff
    u64(0)               # filesize
    u32(5)               # maxprot
    u32(5)               # initprot
    u32(1)               # nsects
    u32(0)               # flags

    # section_64 (80 bait)
    d.extend(b'__text'.ljust(16, b'\0'))
    d.extend(b'__TEXT'.ljust(16, b'\0'))
    u64(textOff)
    u64(textSize)
    u32(textOff)
    u32(4)               # align
    u32(0)               # reloff
    u32(0)               # nreloc
    u32(0x80000400)      # flags
    u32(0); u32(0); u32(0)

    # LC_ID_DYLIB
    u32(LC_ID_DYLIB)
    u32(idSize)
    u32(0)
    u32(0)
    u32(0x10000)
    u32(0x10000)
    nm = idName + b'\0'
    d.extend(nm.ljust(idNamePadded, b'\0'))

    while len(d) < textOff:
        d.append(0)

    return bytes(d)


def main():
    b = bina_dylib()
    gagal = 0

    def uji(nama, ok, info=''):
        nonlocal gagal
        print(('  OK   ' if ok else '  GAGAL') + '  ' + nama + ('' if ok else '  ' + info))
        if not ok:
            gagal += 1

    print('saiz dylib: %d bait' % len(b))

    magic, = struct.unpack_from('<I', b, 0)
    cputype, cpusub, filetype, ncmds, sizeofcmds = struct.unpack_from('<IIIII', b, 4)
    uji('magic = MH_MAGIC_64 (0xFEEDFACF)', magic == MH_MAGIC_64, hex(magic))
    uji('cputype = arm64 (0x0100000C)', cputype == 0x0100000C, hex(cputype))
    uji('filetype = MH_DYLIB (6)', filetype == MH_DYLIB, str(filetype))
    uji('ncmds = 2', ncmds == 2, str(ncmds))
    uji('sizeofcmds munasabah', 0 < sizeofcmds <= len(b), str(sizeofcmds))

    # hurai command
    off = 32
    jumpa_seg = jumpa_id = False
    for _ in range(ncmds):
        if off + 8 > len(b):
            break
        cmd, sz = struct.unpack_from('<II', b, off)
        if cmd == LC_SEGMENT_64:
            jumpa_seg = True
            segname = b[off + 8:off + 24].rstrip(b'\0').decode('latin-1')
            uji('segname = __TEXT', segname == '__TEXT', segname)
            nsects, = struct.unpack_from('<I', b, off + 64)
            uji('nsects = 1', nsects == 1, str(nsects))
            uji('saiz LC_SEGMENT_64 = 152', sz == 152, str(sz))
        elif cmd == LC_ID_DYLIB:
            jumpa_id = True
            uji('saiz LC_ID_DYLIB = 32', sz == 32, str(sz))
        off += sz

    uji('LC_SEGMENT_64 ada', jumpa_seg)
    uji('LC_ID_DYLIB ada', jumpa_id)
    uji('jumlah command = sizeofcmds', off - 32 == sizeofcmds,
        '%d vs %d' % (off - 32, sizeofcmds))
    uji('fail cukup besar untuk textOff', len(b) >= 0x1000, str(len(b)))

    print()
    if gagal == 0:
        print('LULUS: dylib minimum sah (MH_DYLIB arm64).')
        return 0
    print('GAGAL: %d isu.' % gagal)
    return 1


if __name__ == '__main__':
    sys.exit(main())
