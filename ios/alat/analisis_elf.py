"""Analisis ELF arm64 Android untuk menilai kebolehlaksanaan port ke iOS.

Jalankan:
    python d:\\MALAYCITY_FULL\\ios\\alat\\analisis_elf.py [fail.so ...]
    (tanpa argumen: analisis semua lib dlm mobile/app/src/main/jniLibs/arm64-v8a)

Semua angka EXACT kecuali x18 (heuristik - angka sebenar lebih tinggi).
"""
import struct
import sys
import os
from collections import Counter, defaultdict

SHT_DYNSYM = 11
SHT_RELA = 4
DT_NEEDED = 1

RELOC = {
    257: 'R_AARCH64_ABS64',
    1024: 'R_AARCH64_COPY',
    1025: 'R_AARCH64_GLOB_DAT',
    1026: 'R_AARCH64_JUMP_SLOT',
    1027: 'R_AARCH64_RELATIVE',
    1028: 'R_AARCH64_TLS_TPREL64',
    1031: 'R_AARCH64_TLSDESC',
}

# Import yg ada di Android tetapi TIADA (atau berbeza) di iOS
ANDROID_ONLY = {
    '__android_log_print', '__android_log_write', '__android_log_vprint',
    '__android_log_assert', '__android_log_buf_write',
    '__system_property_get', '__system_property_find', '__system_property_read',
    'AAssetManager_open', 'AAssetManager_fromJava', 'AAsset_getBuffer',
    'AAsset_close', 'AAsset_read', 'AAsset_getLength',
    'ANativeWindow_fromSurface', 'ANativeWindow_release',
    'android_get_device_api_level', 'android_set_abort_message',
    'getprop', 'setprop', 'property_get',
}


class Elf:
    def __init__(self, path):
        self.path = path
        self.size = os.path.getsize(path)
        with open(path, 'rb') as f:
            self.raw = f.read()

        b = self.raw
        if b[:4] != b'\x7fELF':
            raise ValueError('bukan ELF')
        if b[4] != 2:
            raise ValueError('bukan ELF64 (kelas %d)' % b[4])
        (self.e_type, self.e_machine, self.e_version, self.e_entry,
         self.e_phoff, self.e_shoff, self.e_flags, self.e_ehsize,
         self.e_phentsize, self.e_phnum, self.e_shentsize, self.e_shnum,
         self.e_shstrndx) = struct.unpack_from('<HHIQQQIHHHHHH', b, 16)

        self.sections = []
        for i in range(self.e_shnum):
            off = self.e_shoff + i * self.e_shentsize
            (name, typ, flags, addr, offset, size, link, info,
             align, entsize) = struct.unpack_from('<IIQQQQIIQQ', b, off)
            self.sections.append(dict(i=i, name_off=name, type=typ, flags=flags,
                                      addr=addr, offset=offset, size=size,
                                      link=link, info=info, align=align,
                                      entsize=entsize))

        shstr = self.sections[self.e_shstrndx]
        base = shstr['offset']
        for s in self.sections:
            end = b.index(b'\0', base + s['name_off'])
            s['name'] = b[base + s['name_off']:end].decode('latin-1')

    def sec(self, name):
        for s in self.sections:
            if s['name'] == name:
                return s
        return None

    def data(self, s):
        return self.raw[s['offset']:s['offset'] + s['size']]

    def dynamic(self):
        s = self.sec('.dynamic')
        if not s:
            return []
        out = []
        d = self.data(s)
        for o in range(0, len(d) - 15, 16):
            tag, val = struct.unpack_from('<qQ', d, o)
            if tag == 0:
                break
            out.append((tag, val))
        return out

    def dynstr_at(self, off):
        s = self.sec('.dynstr')
        if not s:
            return ''
        d = self.data(s)
        end = d.index(b'\0', off)
        return d[off:end].decode('latin-1')

    def imports(self):
        sym = self.sec('.dynsym')
        if not sym:
            return []
        d = self.data(sym)
        entsize = sym['entsize'] or 24
        out = []
        for o in range(0, len(d) - entsize + 1, entsize):
            st_name, st_info, st_other, st_shndx, st_value, st_size = \
                struct.unpack_from('<IBBHQQ', d, o)
            if st_shndx == 0 and st_name != 0:      # SHN_UNDEF
                out.append(self.dynstr_at(st_name))
        return out

    def symstats(self):
        sym = self.sec('.dynsym')
        if not sym:
            return 0, 0
        d = self.data(sym)
        entsize = sym['entsize'] or 24
        total = len(d) // entsize
        exp = 0
        for o in range(0, len(d) - entsize + 1, entsize):
            st_name, st_info, st_other, st_shndx, st_value, st_size = \
                struct.unpack_from('<IBBHQQ', d, o)
            if st_shndx != 0 and st_info != 0:
                exp += 1
        return total, exp

    def relocs(self):
        counts = Counter()
        for s in self.sections:
            if s['type'] != SHT_RELA:
                continue
            d = self.data(s)
            entsize = s['entsize'] or 24
            for o in range(0, len(d) - entsize + 1, entsize):
                r_offset, r_info, r_addend = struct.unpack_from('<QQq', d, o)
                counts[r_info & 0xFFFFFFFF] += 1
        return counts

    def count_x18(self):
        """Anggaran penggunaan x18. Apple simpan x18 untuk OS -> MESTI ditukar.

        Hanya 4 kelas arahan disemak, jadi angka sebenar LEBIH TINGGI.
        """
        s = self.sec('.text')
        if not s:
            return 0, 0
        d = self.data(s)
        n = len(d) // 4
        hits = 0
        for i in range(n):
            insn = struct.unpack_from('<I', d, i * 4)[0]
            if (insn & 0x7F800000) == 0x11000000:      # ADD/SUB imm 64
                if (insn & 0x1F) == 18 or ((insn >> 5) & 0x1F) == 18:
                    hits += 1
            elif (insn & 0x7FE00000) == 0x0B000000:    # ADD/SUB reg 64
                if 18 in (insn & 0x1F, (insn >> 5) & 0x1F, (insn >> 16) & 0x1F):
                    hits += 1
            elif (insn & 0x3B000000) == 0x39000000:    # LDR/STR uoff 64
                if (insn & 0x1F) == 18 or ((insn >> 5) & 0x1F) == 18:
                    hits += 1
            elif (insn & 0x7FE0FC00) == 0x2A000000:    # ORR/MOV reg
                if 18 in (insn & 0x1F, (insn >> 5) & 0x1F, (insn >> 16) & 0x1F):
                    hits += 1
        return hits, n

    def android_paths(self):
        found = Counter()
        for pat in (b'/system/', b'/data/', b'/proc/', b'/sdcard', b'/vendor/',
                    b'/apex/', b'/dev/', b'ro.build', b'libGTASA', b'libsamp'):
            c = self.raw.count(pat)
            if c:
                found[pat.decode('latin-1')] = c
        return found

    def init_array_size(self):
        n = 0
        for nm in ('.init_array', '.fini_array'):
            s = self.sec(nm)
            if s:
                n += s['size'] // 8
        return n



def analyse(path):
    print('=' * 72)
    print(os.path.basename(path))
    print('=' * 72)
    try:
        e = Elf(path)
    except Exception as ex:
        print('  GAGAL hurai: %s' % ex)
        print()
        return

    kind = {1: 'REL (boleh pindah)', 2: 'EXEC (tetap)', 3: 'DYN (kongsi/PIE)'}
    mach = {183: 'AArch64 (arm64)'}
    print('  saiz         : %.2f MB' % (e.size / 1024**2))
    print('  jenis        : %s' % kind.get(e.e_type, e.e_type))
    print('  mesin        : %s' % mach.get(e.e_machine, e.e_machine))
    print('  seksyen      : %d' % len(e.sections))

    needed = [e.dynstr_at(v) for t, v in e.dynamic() if t == DT_NEEDED]
    print('  perlu lib    : %s' % (', '.join(needed) if needed else '(tiada)'))

    total, exp = e.symstats()
    imp = e.imports()
    print('  dynsym       : %d simbol (%d dieksport, %d diimport)'
          % (total, exp, len(imp)))
    print('  ada .symtab  : %s'
          % ('ya' if e.sec('.symtab') else 'TIDAK (stripped)'))

    rc = e.relocs()
    print('  relocations  : %d' % sum(rc.values()))
    for t, c in rc.most_common():
        print('      %-24s %d' % (RELOC.get(t, 'jenis %d' % t), c))

    print('  init/fini    : %d entri (iOS perlu __mod_init_func)'
          % e.init_array_size())

    # klasifikasi import
    grp = defaultdict(list)
    for s in imp:
        if s in ANDROID_ONLY or s.startswith('__android_log'):
            grp['ANDROID KHAS - tiada di iOS'].append(s)
        elif s.startswith(('gl', 'egl')) and s not in ('glibc',):
            grp['GL/EGL - perlu lapisan'].append(s)
        elif s.startswith(('SL_IID', 'slCreate', 'SLES')):
            grp['OpenSL ES - perlu CoreAudio'].append(s)
        elif s.startswith(('JNI', 'Java_')):
            grp['JNI - perlu jambatan'].append(s)
        elif s.startswith('pthread') or s in ('dlopen', 'dlsym', 'dlclose', 'dlerror'):
            grp['POSIX/Darwin - kebanyakannya ada'].append(s)
        else:
            grp['libc/STL lain'].append(s)

    print()
    print('  IMPORT IKUT KATEGORI')
    for k in sorted(grp, key=lambda x: -len(grp[x])):
        v = grp[k]
        print('    %-36s %3d' % (k, len(v)))
        if k.startswith(('ANDROID', 'GL/EGL', 'OpenSL', 'JNI')):
            for s in sorted(set(v))[:12]:
                print('        - %s' % s)
            if len(set(v)) > 12:
                print('        ... dan %d lagi' % (len(set(v)) - 12))

    hits, total_i = e.count_x18()
    print()
    print('  x18 (anggaran HEURISTIK) : %d / %d arahan .text' % (hits, total_i))
    print('      angka sebenar lebih tinggi (hanya 4 kelas arahan disemak)')

    ap = e.android_paths()
    if ap:
        print()
        print('  RUJUKAN LALUAN/NAMA ANDROID (perlu ditukar)')
        for k, c in ap.most_common(10):
            print('      %-14s %d kali' % (k, c))
    print()


def main():
    if len(sys.argv) < 2:
        base = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            '..', '..', 'mobile', 'app', 'src', 'main',
                            'jniLibs', 'arm64-v8a')
        args = []
        for n in ('libGTASA.so', 'libSCAnd.so', 'libOpenAL64.so',
                  'libluajit-5.1.so', 'libmonetloader.so'):
            p = os.path.abspath(os.path.join(base, n))
            if os.path.isfile(p):
                args.append(p)
        if not args:
            print('Guna: python analisis_elf.py <fail.so> ...')
            return 1
    else:
        args = sys.argv[1:]

    for p in args:
        analyse(p)
    return 0


if __name__ == '__main__':
    sys.exit(main())

