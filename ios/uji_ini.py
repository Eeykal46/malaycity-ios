"""Ujian McIni.swift (port Python 1:1) - sahkan get/put/remove kekalkan komen & susunan.

Jalankan: python d:\\MALAYCITY_FULL\\ios\\uji_ini.py
Fail sebenar: ios/McLauncher/McIni.swift
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

def cari(*calon):
    """Cari fail pertama yg wujud (repo penuh -> repo slim)."""
    tahap = os.path.join(HERE, '..', '..')
    pilihan = [os.path.join(tahap, c) for c in calon] + [os.path.join(HERE, c) for c in calon]
    for p in pilihan:
        if os.path.isfile(p):
            return p
    return None

# ---- Port 1:1 logik McIni.swift ----
def is_section(s):
    t = s.strip()
    if t.startswith('[') and t.endswith(']'):
        return t[1:-1]
    return None

def key_value(s):
    i = s.find('=')
    if i < 0:
        return None
    k = s[:i].strip()
    v = s[i+1:].strip()
    return None if not k else (k, v)

class McIni:
    def __init__(self, lines, url='test.ini'):
        self.lines = lines
        self.url = url

    def index_of(self, section, key):
        cur = ''
        for i, raw in enumerate(self.lines):
            sec = is_section(raw)
            if sec is not None:
                cur = sec
                continue
            if cur != section:
                continue
            kv = key_value(raw)
            if kv and kv[0] == key:
                return i
        return -1

    def index_of_section(self, section):
        for i, raw in enumerate(self.lines):
            if is_section(raw) == section:
                return i
        return -1

    def get(self, section, key):
        i = self.index_of(section, key)
        if i < 0:
            return None
        kv = key_value(self.lines[i])
        return kv[1] if kv else None

    def put(self, section, key, value):
        line = '{} = {}'.format(key, value)
        i = self.index_of(section, key)
        if i >= 0:
            self.lines[i] = line
            return True
        sec = self.index_of_section(section)
        if sec < 0:
            if self.lines and self.lines[-1] != '':
                self.lines.append('')
            self.lines.append('[{}]'.format(section))
            self.lines.append(line)
            return True
        insert_at = sec + 1
        j = sec + 1
        while j < len(self.lines):
            if is_section(self.lines[j]) is not None:
                break
            if key_value(self.lines[j]) is not None:
                insert_at = j + 1
            j += 1
        self.lines.insert(insert_at, line)
        return True

    def remove(self, section, key):
        i = self.index_of(section, key)
        if i >= 0:
            self.lines.pop(i)

gagal = 0

def uji(nama, syarat):
    global gagal
    print(('  OK   ' if syarat else '  GAGAL') + '  ' + nama)
    if not syarat:
        gagal += 1

# ---- 1. Fail SEBENAR dari projek ----
print('1. settings.ini sebenar (assets/settings.ini)')
laluan_ini = cari('mobile/app/src/main/assets/settings.ini')
if not laluan_ini:
    print('  LANGKAU: settings.ini tak dijumpai (repo slim tanpa mobile/)')
    asal = ['[client]', 'name = Nick_Name', 'autoaim = 0', '',
            '[gui]', 'Font = Arial.ttf', 'ChatMaxMessages = 9',
            'HealthBarWidth = 60.0', 'androidkeyboard = 0']
    asal_komen = False
else:
    print('  fail:', laluan_ini)
    with open(laluan_ini, encoding='utf-8') as f:
        asal = f.read().split('\n')
    asal_komen = True

ini = McIni(list(asal))
uji('baca ChatMaxMessages = 9', ini.get('gui', 'ChatMaxMessages') == '9')
uji('baca androidkeyboard = 0', ini.get('gui', 'androidkeyboard') == '0')
uji('baca client/name = Nick_Name', ini.get('client', 'name') == 'Nick_Name')
uji('baca client/autoaim = 0', ini.get('client', 'autoaim') == '0')
uji('kunci tak wujud -> None', ini.get('gui', 'FPSLimit') is None)
uji('seksyen tak wujud -> None', ini.get('tiada', 'x') is None)

# ---- 2. Tukar nilai SEDIA ADA: komen mesti kekal ----
print('2. put() pada kunci sedia ada')
ini.put('gui', 'ChatMaxMessages', '4')
uji('nilai baru dibaca', ini.get('gui', 'ChatMaxMessages') == '4')
if asal_komen:
    uji('komen # by x1y2z kekal', any('x1y2z' in l for l in ini.lines))
    uji('komen client/host kekal', any('IP/port/password server TIDAK' in l for l in ini.lines))
uji('bilangan baris berisi SAMA',
    len([l for l in ini.lines if l.strip()]) == len([l for l in asal if l.strip()]))
uji('kunci lain tak terjejas (HealthBarWidth)', ini.get('gui', 'HealthBarWidth') == '60.0')

# ---- 3. Tambah kunci BARU dlm seksyen sedia ada ----
print('3. put() kunci baru dlm seksyen sedia ada')
ini.put('gui', 'FPSLimit', '60')
uji('FPSLimit dibaca', ini.get('gui', 'FPSLimit') == '60')
i_gui = next(k for k in range(len(ini.lines)) if is_section(ini.lines[k]) == 'gui')
i_nxt = next((k for k in range(i_gui + 1, len(ini.lines))
              if is_section(ini.lines[k]) is not None), len(ini.lines))
i_fps = ini.lines.index('FPSLimit = 60')
uji('diletak DALAM seksyen gui', i_gui < i_fps < i_nxt)

# ---- 4. Seksyen BARU ----
print('4. put() seksyen baru')
ini.put('baru', 'kunci', 'nilai')
uji('seksyen baru dibaca', ini.get('baru', 'kunci') == 'nilai')
uji('seksyen baru di HUJUNG fail', is_section(ini.lines[-2]) == 'baru')
uji('seksyen gui asal tak rosak', ini.get('gui', 'Font') == 'Arial.ttf')

# ---- 5. remove() (padanan writeClient) ----
print('5. remove() - host/port/password dibuang')
ini.put('client', 'host', '1.2.3.4')
ini.put('client', 'port', '7777')
ini.put('client', 'password', 'rahsia')
ini.remove('client', 'host')
ini.remove('client', 'port')
ini.remove('client', 'password')
uji('host dibuang', ini.get('client', 'host') is None)
uji('port dibuang', ini.get('client', 'port') is None)
uji('password dibuang', ini.get('client', 'password') is None)
uji('name KEKAL', ini.get('client', 'name') == 'Nick_Name')

# ---- 6. Nilai aksara khas (setEscape(false) dlm Java) ----
print('6. nilai aksara khas (nama tag klan)')
ini.put('client', 'name', '[MC]Ali_Bakar')
uji('nama tag klan kekal apa adanya', ini.get('client', 'name') == '[MC]Ali_Bakar')

# ---- 7. Round-trip ----
print('7. round-trip (tulis -> baca semula)')
teks = '\n'.join(ini.lines)
ini2 = McIni(teks.split('\n'))
uji('nilai sama selepas baca semula', ini2.get('client', 'name') == '[MC]Ali_Bakar')
uji('FPSLimit sama selepas baca semula', ini2.get('gui', 'FPSLimit') == '60')

print()
if gagal == 0:
    print('LULUS: semua ujian McIni lulus.')
    sys.exit(0)
print('GAGAL: {} ujian gagal.'.format(gagal))
sys.exit(1)

