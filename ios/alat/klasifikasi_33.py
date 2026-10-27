"""Klasifikasi 33 alamat: KOD atau DATA? Adakah ia dalam komen?

Ini soalan penentu:
  - alamat dalam segmen KOD  -> boleh dicari melalui simbol fungsi
  - alamat dalam segmen DATA -> dlsym TIDAK menolong; offset data tidak
                                stabil merentas binari (Android vs iOS)
  - alamat dalam KOMEN       -> tiada kerja diperlukan

Jalankan: python ios/alat/klasifikasi_33.py
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

PT_LOAD = 1
PF_X = 1
PF_W = 2


def segmen(path):
    """[(vaddr, memsz, flags)] bagi PT_LOAD."""
    with open(path, 'rb') as f:
        b = f.read()
    e_phoff, = struct.unpack_from('<Q', b, 0x20)
    e_phentsize, e_phnum = struct.unpack_from('<HH', b, 0x36)
    out = []
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        p_type, p_flags = struct.unpack_from('<II', b, o)
        p_vaddr, = struct.unpack_from('<Q', b, o + 16)
        p_memsz, = struct.unpack_from('<Q', b, o + 40)
        if p_type == PT_LOAD:
            out.append((p_vaddr, p_memsz, p_flags))
    return out


def dalam_segmen(segs, addr):
    for vaddr, memsz, flags in segs:
        if vaddr <= addr < vaddr + memsz:
            if flags & PF_X:
                return 'KOD'
            if flags & PF_W:
                return 'DATA'
            return 'RODATA'
    return 'LUAR'


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


def kumpul():
    guna = {}
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
                for m in RE_BASE.finditer(ln):
                    a = int(m.group(1), 16)
                    k = ln.strip()
                    guna.setdefault(a, []).append((rel, i, k))
    return guna


def main():
    so = os.path.join(JNILIBS, 'arm64-v8a', 'libGTASA.so')
    if not os.path.isfile(so):
        print('TIADA:', so)
        return 1
    segs = segmen(so)
    syms = dynsyms(so)
    guna = kumpul()

    tanpa = [a for a in sorted(guna)
             if not any(s[0] <= a < s[0] + max(s[1], 1) for s in syms)]

    print('segmen PT_LOAD (vaddr, saiz, flags):')
    for v, m, f in segs:
        jenis = 'KOD' if f & PF_X else ('DATA' if f & PF_W else 'RODATA')
        print('  0x%-9X 0x%-9X %-7s flags=%d' % (v, m, jenis, f))
    print()

    print('%-11s %-7s %-6s %-30s %s'
          % ('ALAMAT', 'SEGMEN', 'KOMEN', 'FAIL:BARIS', 'SIMPULAN'))
    print('-' * 108)

    kira = {}
    for a in tanpa:
        seg = dalam_segmen(segs, a)
        senarai = guna[a]
        semua_komen = all(s[2].startswith('//') for s in senarai)
        f0, l0, _ = senarai[0]
        lokasi = '%s:%d' % (f0, l0)

        if semua_komen:
            simp = 'KOMEN SAHAJA - tiada kerja'
        elif seg == 'KOD':
            simp = 'KOD - boleh jadi simbol (perlu semak manual)'
        elif seg == 'DATA':
            simp = 'DATA - dlsym tak menolong, offset var perlu cari'
        elif seg == 'RODATA':
            simp = 'RODATA - data tetap, pemetaan berasingan'
        else:
            simp = 'LUAR segmen - semak'

        print('0x%-9X %-7s %-6s %-30s %s'
              % (a, seg, 'YA' if semua_komen else 'tidak', lokasi, simp))
        kira[simp.split(' - ')[0]] = kira.get(simp.split(' - ')[0], 0) + 1

    print()
    print('=' * 70)
    print('RINGKASAN')
    print('=' * 70)
    for k, v in sorted(kira.items(), key=lambda x: -x[1]):
        print('  %-12s %d' % (k, v))
    print()
    print('Nota: alamat DATA (cth 0xA7C264 vertex buffer) TIDAK boleh dicari')
    print('melalui dlsym. Ia mesti dipetakan semula untuk setiap binari, atau')
    print('client mesti buat sendiri apa yang enjin buat (cth jana vertex).')
    return 0


if __name__ == '__main__':
    sys.exit(main())

