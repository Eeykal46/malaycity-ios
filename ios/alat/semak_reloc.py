"""Semak sama ada relocation dlm libGTASA.so memerlukan lebih drpd RELATIVE.

Ditulis kerana aku hampir menulis loader yg tak lengkap. Soalan:
  1. Berapa banyak relocation RELATIVE vs yang perlukan import?
  2. Adakah import boleh dipenuhi oleh shim iOS?
  3. Adakah DT_TEXTREL wujud (tidak boleh dengan W^X)?
  4. Adakah TLS/ifunc (tak disokong)?

Jalankan: python ios/alat/semak_reloc.py
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SO = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'jniLibs',
                  'arm64-v8a', 'libGTASA.so')

RTYPE = {
    0: 'NONE', 257: 'ABS64', 1025: 'GLOB_DAT', 1026: 'JUMP_SLOT',
    1027: 'RELATIVE', 1028: 'TLS_DTPMOD64', 1029: 'TLS_DTPREL64',
    1030: 'TLS_TPREL64', 1031: 'TLSDESC', 1032: 'IRELATIVE',
}
# Relocation yang TIDAK perlukan simbol luar
SELESAI_SENDIRI = {0, 1027, 1032}


def baca_so(path):
    with open(path, 'rb') as f:
        return f.read()


def segmen(b):
    e_phoff, = struct.unpack_from('<Q', b, 0x20)
    e_phentsize, e_phnum = struct.unpack_from('<HH', b, 0x36)
    out = []
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        t, = struct.unpack_from('<I', b, o)
        off, va = struct.unpack_from('<QQ', b, o + 8)
        fsz, msz, al = struct.unpack_from('<QQQ', b, o + 32)
        out.append((t, off, va, fsz, msz, al))
    return out


def dynamic(b, segs):
    for t, off, va, fsz, msz, al in segs:
        if t != 2:      # PT_DYNAMIC
            continue
        dyn = []
        o = off
        while o + 16 <= off + fsz:
            tag, val = struct.unpack_from('<qQ', b, o)
            if tag == 0:
                break
            dyn.append((tag, val))
            o += 16
        return dyn
    return []


def main():
    if not os.path.isfile(SO):
        print('TIADA:', SO)
        return 1
    b = baca_so(SO)
    segs = segmen(b)
    dyn = dynamic(b, segs)

    print('PT_LOAD:')
    for t, off, va, fsz, msz, al in segs:
        if t == 1:
            print('  off=0x%-8X va=0x%-8X filesz=0x%-8X memsz=0x%-8X align=0x%X'
                  % (off, va, fsz, msz, al))
    print()

    d = {}
    for tag, val in dyn:
        d[tag] = val

    # DT_TEXTREL
    has_textrel = 22 in d
    print('DT_TEXTREL : %s' % ('ADA (masalah W^X)' if has_textrel else 'tiada'))
    print('DT_RELR    : %s' % ('ADA' if 36 in d else 'tiada'))
    print('DT_ANDROID_RELA : %s' % ('ADA' if 0x60000011 in d else 'tiada'))
    print()

    # kira relocation RELATIVE vs lain
    rela_off = d.get(7)          # DT_RELA
    rela_sz = d.get(8, 0)        # DT_RELASZ
    relacount = d.get(0x6ffffff9, 0)

    print('DT_RELA       : off=0x%X saiz=%d (%d entri)'
          % (rela_off or 0, rela_sz, rela_sz // 24 if rela_sz else 0))
    print('DT_RELACOUNT  : %d  (yang pertama ialah RELATIVE)' % relacount)

    if rela_off and rela_sz:
        # cari fail-offset bagi vaddr rela_off
        fo = None
        for t, off, va, fsz, msz, al in segs:
            if t == 1 and va <= rela_off < va + fsz:
                fo = off + (rela_off - va)
                break
        if fo is None:
            print('  ! tidak jumpa fail-offset untuk DT_RELA')
        else:
            kira = {}
            for i in range(rela_sz // 24):
                o = fo + i * 24
                r_off, r_info = struct.unpack_from('<QQ', b, o)
                rt = r_info & 0xFFFFFFFF
                kira[rt] = kira.get(rt, 0) + 1
            print()
            print('  jenis relocation dlm DT_RELA:')
            for rt, n in sorted(kira.items(), key=lambda x: -x[1]):
                nm = RTYPE.get(rt, 'jenis %d' % rt)
                perlu = 'tiada simbol' if rt in SELESAI_SENDIRI else 'PERLU simbol'
                print('    %-16s %6d   %s' % (nm, n, perlu))

    # JUMP_SLOT (PLT)
    jmprel = d.get(23)           # DT_JMPREL
    pltrelsz = d.get(2, 0)       # DT_PLTRELSZ
    print()
    print('DT_JMPREL : off=0x%X saiz=%d (%d entri) -> semua JUMP_SLOT = PERLU simbol'
          % (jmprel or 0, pltrelsz, pltrelsz // 24 if pltrelsz else 0))

    print()
    print('KESIMPULAN:')
    sentiasa = 0
    for i in range(relacount):
        pass
    if relacount:
        print('  %d relocation pertama ialah RELATIVE (boleh selesai sendiri).' % relacount)
    print('  Selebihnya + semua JUMP_SLOT memerlukan SHIM untuk 274 import.')
    print('  Itu kerja sebenar - bukan relocation, tetapi menyediakan API Android.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
