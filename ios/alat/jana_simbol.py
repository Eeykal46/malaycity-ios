"""Jana mc_simbol.h - peta alamat -> (nama simbol, offset).

Untuk setiap `g_libGTASA + 0xNNN` dalam client, kita hasilkan:
    MC_ADDR_0x2BD618  ->  { "_Z20RpGeometryStreamReadP8RwStream", 0x18 }

Maka kod client boleh ditukar daripada:
    g_libGTASA + 0x2BD618
kepada:
    MC_ADDR(0x2BD618)
dan MC_ADDR mencari simbol melalui dlsym + tambah offset. Itu menjadikan
client MUDAH ALIH: Android guna alamat, iOS guna simbol - kod sama.

Jalankan: python ios/alat/jana_simbol.py
Hasil  : ios/enjin/mc_simbol.h
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
JNILIBS = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'jniLibs')
CPP = os.path.join(ROOT, 'mobile', 'app', 'src', 'main', 'cpp', 'samp')
OUT = os.path.join(HERE, '..', 'enjin', 'mc_simbol.h')

RE_BASE = re.compile(r'g_libGTASA\s*\+\s*(0x[0-9A-Fa-f]+)')
SRC_EXT = ('.cpp', '.h', '.hpp', '.c')
SKIP_DIRS = {'vendor', 'opus', 'imgui', 'armhook'}


def dynsyms(so_path):
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


def alamat_kod():
    hasil = set()
    for dirpath, dirnames, filenames in os.walk(CPP):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(SRC_EXT):
                continue
            try:
                with open(os.path.join(dirpath, fn), 'r',
                          encoding='utf-8', errors='replace') as f:
                    txt = f.read()
            except Exception:
                continue
            for m in RE_BASE.finditer(txt):
                hasil.add(int(m.group(1), 16))
    return sorted(hasil)


def main():
    so = os.path.join(JNILIBS, 'arm64-v8a', 'libGTASA.so')
    if not os.path.isfile(so):
        print('TIADA:', so)
        return 1
    syms = sorted(dynsyms(so))
    if not syms:
        print('TIADA .dynsym')
        return 1

    adr = alamat_kod()
    print('alamat unik: %d' % len(adr))

    entries = []       # (addr, nama, offset) atau (addr, None, 0)
    for a in adr:
        cand = [s for s in syms if s[0] <= a < s[0] + max(s[1], 1)]
        if not cand:
            entries.append((a, None, 0))
            continue
        # pilih simbol paling hampir di bawah (paling spesifik)
        s = max(cand, key=lambda x: x[0])
        entries.append((a, s[2], a - s[0]))

    ada = sum(1 for e in entries if e[1])
    print('boleh dipetakan: %d / %d (%.0f%%)'
          % (ada, len(entries), 100.0 * ada / len(entries)))

    lines = []
    lines.append('// mc_simbol.h - DIJANA AUTOMATIK oleh ios/alat/jana_simbol.py')
    lines.append('// JANGAN EDIT TANGAN. Jana semula selepas libGTASA.so berubah.')
    lines.append('//')
    lines.append('// Tujuan: buat client SA-MP MUDAH ALIH. Dulu client guna alamat keras')
    lines.append('// (g_libGTASA + 0x2BD618) yang sah untuk SATU binari sahaja. Sekarang')
    lines.append('// ia guna (nama simbol, offset) yang boleh dicari melalui dlsym, jadi')
    lines.append('// binari Android DAN iOS boleh guna kod yang sama.')
    lines.append('//')
    lines.append('// %d/%d alamat dipetakan. %d tiada simbol -> perlu semak manual.'
                 % (ada, len(entries), len(entries) - ada))
    lines.append('')
    lines.append('#ifndef MC_SIMBOL_H')
    lines.append('#define MC_SIMBOL_H')
    lines.append('')
    lines.append('#define MC_SIMBOL_JUMLAH %d' % len(entries))
    lines.append('#define MC_SIMBOL_BERJAYA %d' % ada)
    lines.append('')
    lines.append('typedef struct {')
    lines.append('    unsigned int  alamat;   // g_libGTASA + alamat (Android)')
    lines.append('    const char*   simbol;   // nama dieksport, NULL jika tiada')
    lines.append('    unsigned int  offset;   // bait dari pangkal simbol')
    lines.append('} McSimbol;')
    lines.append('')
    lines.append('static const McSimbol MC_SIMBOL[] = {')
    for a, nm, off in entries:
        if nm:
            lines.append('    { 0x%X, "%s", 0x%X },' % (a, nm, off))
        else:
            lines.append('    { 0x%X, 0, 0 },   // TIADA SIMBOL' % a)
    lines.append('};')
    lines.append('')
    lines.append('#endif // MC_SIMBOL_H')

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')

    print('ditulis: %s (%d baris)' % (os.path.relpath(OUT, HERE), len(lines)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

