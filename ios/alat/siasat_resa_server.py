"""Siasat apa yang ReSA perlukan untuk sambung ke server - dan sama ada
open.mp boleh memenuhinya.

Jalankan: python ios/alat/siasat_resa_server.py <ipa>

Menyemak dlm binari ReSA:
  - URL/nama domain yg tertanam (server rasmi mereka, API)
  - format alamat server (ip:port? domain?)
  - penanda auth (token, key, login)
  - protokol (QUIC/open.mp/RakNet)
  - tetapan yg boleh diubah pengguna
"""
import os
import re
import sys
import zipfile

# corak menarik
CORAK = {
    'URL https': rb'https?://[A-Za-z0-9._\-/:%?=&~]{6,80}',
    'IPv4:port': rb'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}\b',
    'domain .com/.net/.io': rb'\b[a-z0-9\-]{3,30}\.(?:com|net|io|gg|xyz|app|rs)\b',
    'auth/token': rb'(?i)(bearer|token|api[_\-]?key|auth[_\-]?key|secret)',
}


def baca_binari(ipa):
    out = []
    with zipfile.ZipFile(ipa) as z:
        for n in z.namelist():
            m = re.search(r'/Frameworks/([^/]+)\.framework/([^/]+)$', n)
            if m and m.group(1) == m.group(2):
                with z.open(n) as f:
                    out.append((m.group(1), f.read()))
        # binari utama app
        for n in z.namelist():
            if re.match(r'Payload/[^/]+\.app/[^/]+$', n):
                with z.open(n) as f:
                    out.append(('APP', f.read()))
    return out


def utama():
    if len(sys.argv) < 2:
        print('Guna: python siasat_resa_server.py <fail.ipa>')
        return 1
    ipa = sys.argv[1]
    print('IPA: %s' % os.path.basename(ipa))
    print()

    for nama, data in baca_binari(ipa):
        if len(data) < 500 * 1024:
            continue
        print('=' * 66)
        print('%s (%.1f MB)' % (nama, len(data) / 1024**2))
        print('=' * 66)

        for label, pat in CORAK.items():
            hits = re.findall(pat, data)
            if not hits:
                continue
            uniq = []
            for h in hits:
                s = h.decode('latin-1', 'replace') if isinstance(h, bytes) else h
                if isinstance(h, tuple):
                    s = ' '.join(x.decode('latin-1', 'replace') if isinstance(x, bytes) else x for x in h)
                if s not in uniq:
                    uniq.append(s)
            print('  %s: %d unik' % (label, len(uniq)))
            for s in uniq[:20]:
                print('      %s' % s[:100])
            if len(uniq) > 20:
                print('      ... dan %d lagi' % (len(uniq) - 20))
        print()
    return 0


if __name__ == '__main__':
    sys.exit(utama())
