"""Kaji enjin iOS (IPA ReSA) - protokol rangkaian & keupayaan sambung server.

Jalankan: python ios/alat/kaji_resa.py <laluan .ipa>

Menjawab SATU soalan: boleh tak enjin ini disambung ke server SA-MP kita
(hanya tukar IP/port), atau ia guna protokol lain sepenuhnya?
"""
import os
import re
import struct
import sys
import zipfile

PENANDA = {
    'RakNet (protokol SA-MP)': [b'RakNet', b'raknet', b'BitStream'],
    'RPC SA-MP': [b'RPC_', b'ScriptRPC'],
    'QUIC (protokol lain)': [b'QUIC', b'quic', b'quinn'],
    'open.mp': [b'open.mp', b'omp.rs'],
    'ENet': [b'enet_', b'ENet'],
    'versi SA-MP': [b'0.3.7', b'0.3.DL', b'0.3z', b'0.3x'],
    'Metal (render)': [b'MTLDevice', b'MTLCommandQueue'],
    'librw': [b'librw'],
    'Android (sisa)': [b'libGTASA', b'/system/lib', b'jni.h'],
}

# teks UI yg menunjukkan ada skrin sambung server manual
UI = [b'CONNECTION', b'CONNECT', b'server address', b'Server Address',
      b'hostname', b'nickname', b'SA-MP VERSION']


def baca_ipa(path):
    """Pulangkan (nama, bait) bagi binari utama dlm Payload/*.app/Frameworks/*.framework."""
    hasil = []
    with zipfile.ZipFile(path) as z:
        nama_semua = z.namelist()
        for n in nama_semua:
            if '/Frameworks/' in n and n.endswith('.framework/' + os.path.basename(n)):
                pass
        # cari binari framework: .../X.framework/X
        for n in nama_semua:
            m = re.search(r'/Frameworks/([^/]+)\.framework/([^/]+)$', n)
            if m and m.group(1) == m.group(2):
                with z.open(n) as f:
                    hasil.append((m.group(1), f.read()))
    return hasil


def utama():
    if len(sys.argv) < 2:
        print('Guna: python kaji_resa.py <fail.ipa>')
        return 1
    path = sys.argv[1]
    if not os.path.isfile(path):
        print('Tiada fail: %s' % path)
        return 1

    print('IPA: %s (%.1f MB)' % (os.path.basename(path),
                                 os.path.getsize(path) / 1024**2))
    print()

    bins = baca_ipa(path)
    if not bins:
        print('Tiada framework dijumpai dlm IPA.')
        return 1

    for nama, data in bins:
        if len(data) < 1024 * 1024:
            continue        # hanya binari besar
        print('=' * 68)
        print('%s.framework  (%.2f MB)' % (nama, len(data) / 1024**2))
        print('=' * 68)
        for k, pats in PENANDA.items():
            c = sum(data.count(p) for p in pats)
            tanda = 'ADA' if c else '-'
            print('  %-28s %-5s %d' % (k, tanda, c))

        # teks UI sambung server
        ui = [(p, data.count(p)) for p in UI if data.count(p)]
        if ui:
            print()
            print('  teks UI sambung server:')
            for p, c in ui:
                print('      %-22s %d' % (p.decode('latin-1'), c))
        print()

    return 0


if __name__ == '__main__':
    sys.exit(utama())
