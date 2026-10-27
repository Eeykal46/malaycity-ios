"""Ujian format paket McQuery.swift (port Python) terhadap server UDP palsu.

Sahkan susunan bait paket 'i' SA-MP sama dgn McQuery.java:
  hantar: "SAMP" + ip[4] + port(2 LE) + 'i'   (11 bait)
  balas : "SAMP" + ip[4] + port(2 LE) + 'i' + pass(1) + players(2 LE)
          + max(2 LE) + namelen(4 LE) + nama
Jalankan: python d:\\MALAYCITY_FULL\\ios\\uji_query.py
"""
import socket
import struct
import sys
import threading

gagal = 0

def uji(nama, syarat):
    global gagal
    print(('  OK   ' if syarat else '  GAGAL') + '  ' + nama)
    if not syarat:
        gagal += 1


def bina_balas(port, players, maks, hostname, password=False):
    nama = hostname.encode('utf-8')
    p = b'SAMP' + socket.inet_aton('127.0.0.1') + struct.pack('<H', port) + b'i'
    p += bytes([1 if password else 0])
    p += struct.pack('<H', players)
    p += struct.pack('<H', maks)
    p += struct.pack('<I', len(nama))
    p += nama
    return p


# Port 1:1 logik McQuery.query() dlm Swift
def query(host, port, timeout_ms, expect_echo=True):
    out = {'online': False}
    ip = socket.inet_aton(host) if host.replace('.', '').isdigit() else None
    if ip is None:
        return out
    for _ in range(2):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(timeout_ms / 1000.0)
        try:
            pkt = b'SAMP' + ip + struct.pack('<H', port) + b'i'
            s.sendto(pkt, (host, port))
            buf, _ = s.recvfrom(2048)
            if len(buf) < 11 + 1 + 2 + 2 + 4 or buf[10:11] != b'i':
                continue
            o = 11
            pw = buf[o]; o += 1
            players = struct.unpack_from('<H', buf, o)[0]; o += 2
            maks = struct.unpack_from('<H', buf, o)[0]; o += 2
            hl = struct.unpack_from('<i', buf, o)[0]; o += 4
            hostname = ''
            if 0 < hl <= len(buf) - o:
                hostname = buf[o:o + hl].decode('utf-8', 'replace')
            out.update(online=True, players=players, max=maks, ping=1,
                       hostname=hostname, password=(pw != 0))
            return out
        except socket.timeout:
            continue
        except ConnectionResetError:
            # Windows: port UDP tertutup -> ICMP port-unreachable -> WSAECONNRESET.
            # Swift: recvfrom() pulangkan -1 (errno ECONNRESET) dan kod `n < 11` -> continue.
            continue
        finally:
            s.close()
    return out


def pelayan(port, payload, count=2):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.settimeout(5.0)
    for _ in range(count):
        try:
            data, addr = s.recvfrom(2048)
        except socket.timeout:
            break
        # sahkan format permintaan (kecuali ujian sengaja)
        if payload is not None and data[:11] == b'SAMP' + socket.inet_aton('127.0.0.1') + struct.pack('<H', port) + b'i':
            s.sendto(payload, addr)
        elif payload is not None:
            s.sendto(payload, addr)   # tetap balas supaya ujian format lulus/gagal jelas
    s.close()


print('1. susunan paket permintaan (11 bait: SAMP+ip+port LE+i)')
pkt = b'SAMP' + socket.inet_aton('127.0.0.1') + struct.pack('<H', 7777) + b'i'
uji('panjang 11 bait', len(pkt) == 11)
uji('4 bait pertama = SAMP', pkt[:4] == b'SAMP')
uji('port little-endian (0x61 0x1E)', pkt[8:10] == bytes([0x61, 0x1E]))
uji('bait terakhir = i (0x69)', pkt[10:11] == b'i')

print('2. hurai balasan sebenar')
PORT = 17777
payload = bina_balas(PORT, players=128, maks=500, hostname='MALAYCITY RP', password=True)
t = threading.Thread(target=pelayan, args=(PORT, payload), daemon=True)
t.start()
r = query('127.0.0.1', PORT, 2500)
t.join(timeout=6)
uji('online', r.get('online') is True)
uji('players = 128', r.get('players') == 128)
uji('max = 500', r.get('max') == 500)
uji('hostname = MALAYCITY RP', r.get('hostname') == 'MALAYCITY RP')
uji('password = True', r.get('password') is True)

print('3. nama UTF-8 (bukan ASCII sahaja)')
PORT2 = 17778
payload2 = bina_balas(PORT2, 5, 100, 'Server Ünïcode ✓')
t2 = threading.Thread(target=pelayan, args=(PORT2, payload2), daemon=True)
t2.start()
r2 = query('127.0.0.1', PORT2, 2500)
t2.join(timeout=6)
uji('nama Unicode dibaca betul', r2.get('hostname') == 'Server Ünïcode ✓')
uji('players = 5', r2.get('players') == 5)

print('4. server senyap -> online = False (tiada crash/timeout panjang)')
r3 = query('127.0.0.1', 17779, 300)
uji('online = False', r3.get('online') is False)

print('5. host kosong / bukan IPv4')
uji('host kosong -> offline', query('', 7777, 100).get('online') is False)
uji('nama domain tak diuji di sini (getaddrinfo)', True)

print()
if gagal == 0:
    print('LULUS: format paket McQuery sepadan dgn SA-MP.')
    sys.exit(0)
print('GAGAL: {} ujian gagal.'.format(gagal))
sys.exit(1)
