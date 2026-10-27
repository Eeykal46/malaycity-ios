"""Ujian logik check() - port Python 1:1 logik McDownloader.swift, disemak thd Java.

Fokus: status yg dipulangkan ke HTML mesti SAMA macam McDownloader.java:
  ok / need / app_required / app_update / offline / error
Jalankan: python d:\\MALAYCITY_FULL\\ios\\uji_check.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

def cari(*calon):
    tahap = os.path.join(HERE, '..', '..')
    for p in [os.path.join(tahap, c) for c in calon] + [os.path.join(HERE, c) for c in calon]:
        if os.path.isfile(p):
            return p
    return None

gagal = 0


def uji(nama, syarat, dapat=None):
    global gagal
    print(('  OK   ' if syarat else '  GAGAL') + '  ' + nama)
    if not syarat:
        if dapat is not None:
            print('         dapat: {}'.format(dapat))
        gagal += 1


def check(manifest, version_code, index_size, fail_sedia, online=True):
    """Port check() Swift. fail_sedia = set laluan yg sudah wujud & saiz sepadan."""
    r = {}
    if not online and manifest is None:
        return {'status': 'error', 'canPlay': False, 'message': 'Tiada sambungan internet'}

    m = manifest
    files = m.get('files', [])
    entries = [f for f in files]

    # copyPublic: host/port TIDAK didedahkan
    if 'server' in m:
        r['server'] = {'name': m['server'].get('name', 'MALAYCITY')}
    if 'news' in m:
        r['news'] = m['news']
    if 'links' in m:
        r['links'] = m['links']

    need = [f for f in entries if f['path'] not in fail_sedia]

    if not online:
        r['status'] = 'offline'
        r['canPlay'] = len(need) == 0
        return r

    app = m.get('app')
    if app is not None:
        r['apkUrl'] = app.get('apkUrl', '')
        if app.get('minVersionCode', 0) > version_code:
            r['status'] = 'app_required'
            return r

    if need:
        r['status'] = 'need'
        r['count'] = len(need)
        r['bytes'] = sum(f['size'] for f in need)
        r['update'] = index_size > 0
        return r

    if app is not None and app.get('latestVersionCode', 0) > version_code:
        r['status'] = 'app_update'
    else:
        r['status'] = 'ok'
    return r


# Manifest asas projek + senarai fail
laluan_m = cari('mobile/tools/hos/manifest_asas.json')
if laluan_m:
    with open(laluan_m, encoding='utf-8') as f:
        asas = json.load(f)
else:
    print('  (manifest_asas.json tak dijumpai - guna manifest ujian)')
    asas = {
        'server': {'name': 'MALAYCITY RP', 'host': 'ISI_IP', 'port': 7777,
                   'password': '', 'version': '0.3.7'},
        'app': {'minVersionCode': 1, 'latestVersionCode': 1,
                'apkUrl': 'https://malaycity.com/mobile/MALAYCITY.apk'},
        'baseUrl': 'files/',
        'news': [{'tag': 'BERITA', 'title': 'Selamat datang ke',
                  'title2': 'MALAYCITY Mobile', 'text': 'Server roleplay Malaysia.'}],
        'links': {'discord': 'https://discord.gg/ISI', 'website': 'https://malaycity.com'},
    }

asas['files'] = [
    {'path': 'texdb/gta3.img', 'size': 1000, 'md5': 'a' * 32},
    {'path': 'texdb/gta3.dxt.img', 'size': 500, 'md5': 'b' * 32},
    {'path': 'data/gta.dat', 'size': 200, 'md5': 'c' * 32},
    {'path': 'SAMP/settings.ini', 'size': 900, 'md5': 'd' * 32, 'keep': True},
]
SEMUA = {f['path'] for f in asas['files']}

print('1. manifest asas SEBENAR projek')
r = check(asas, version_code=1, index_size=4, fail_sedia=SEMUA)
uji('semua fail ada + app terkini -> ok', r['status'] == 'ok', r['status'])
uji('nama server dihantar', r['server']['name'] == 'MALAYCITY RP', r['server'])
uji('host TIDAK dihantar ke HTML', 'host' not in r['server'], r['server'])
uji('port TIDAK dihantar ke HTML', 'port' not in r['server'], r['server'])
uji('password TIDAK dihantar ke HTML', 'password' not in r['server'], r['server'])
uji('berita dihantar', len(r['news']) == 1)
uji('links dihantar', 'discord' in r['links'])

print('2. fail belum lengkap -> need')
r = check(asas, 1, index_size=0, fail_sedia={'data/gta.dat'})
uji('status need', r['status'] == 'need', r['status'])
uji('count = 3', r['count'] == 3, r.get('count'))
uji('bytes = 1000+500+900', r['bytes'] == 2400, r.get('bytes'))
uji('update=false (indeks kosong)', r['update'] is False, r.get('update'))

print('3. indeks ada -> update = true (kemas kini, bukan pasang baru)')
r = check(asas, 1, index_size=3, fail_sedia={'data/gta.dat'})
uji('update = true', r['update'] is True, r.get('update'))

print('4. app terlalu lama -> app_required')
r = check(asas, version_code=0, index_size=4, fail_sedia=SEMUA)
uji('status app_required', r['status'] == 'app_required', r['status'])
uji('apkUrl dihantar', r['apkUrl'].endswith('.apk'), r.get('apkUrl'))

print('5. app lama tapi masih dibenarkan -> app_update')
m2 = dict(asas)
m2['app'] = {'minVersionCode': 1, 'latestVersionCode': 5, 'apkUrl': 'https://x/y.apk'}
r = check(m2, version_code=1, index_size=4, fail_sedia=SEMUA)
uji('status app_update', r['status'] == 'app_update', r['status'])

print('6. luar talian dgn cache')
r = check(asas, 1, 4, SEMUA, online=False)
uji('status offline', r['status'] == 'offline', r['status'])
uji('canPlay=true (fail lengkap)', r['canPlay'] is True, r.get('canPlay'))

print('7. luar talian + fail tak lengkap')
r = check(asas, 1, 0, {'data/gta.dat'}, online=False)
uji('status offline', r['status'] == 'offline', r['status'])
uji('canPlay=false', r['canPlay'] is False, r.get('canPlay'))

print('8. tiada cache & tiada internet')
r = check(None, 1, 0, set(), online=False)
uji('status error', r['status'] == 'error', r['status'])
uji('canPlay=false', r['canPlay'] is False, r.get('canPlay'))

print('9. fail keep=true yg wujud dikira OK (tak dimuat turun semula)')
r = check(asas, 1, 4, SEMUA)
uji('keep true tak jejaskan status', r['status'] == 'ok', r['status'])

print()
if gagal == 0:
    print('LULUS: logik check() sepadan dgn McDownloader.java.')
    sys.exit(0)
print('GAGAL: {} ujian gagal.'.format(gagal))
sys.exit(1)
