// Ujian tab Diagnostik: pastikan renderTab("d") berfungsi dgn data sebenar.
// Jalankan: node ios/uji_diagnostik.js
const fs = require('fs');
const path = require('path');

const HTML = path.join(__dirname, 'launcher', 'index.html');
const src = fs.readFileSync(HTML, 'utf8');

let gagal = 0;
function uji(nama, ok) {
  console.log((ok ? '  OK   ' : '  GAGAL') + '  ' + nama);
  if (!ok) gagal++;
}

// --- 1. Struktur HTML ---
uji('tab Diagnostik wujud', src.includes('{id:"d",name:"Diagnostik"'));
uji('tiada glBox di skrin utama (dipindah ke Tetapan)', !src.includes('id="glBox"'));
uji('jenis "din" dikendalikan', src.includes('o.t==="din"'));
uji('jenis "pre" dikendalikan', src.includes('o.t==="pre"'));
uji('handle huskProbe wujud', src.includes('huskProbe: function(d)'));
uji('tab d dirender semula bila data tiba',
    src.includes('S.tab==="d") renderTab("d")'));
uji('nilai dinamik disegarkan dlm renderTab',
    src.includes('S.settings.__huskreport ='));
uji('ujian GLES lama dibuang', !src.includes('GLES BERFUNGSI'));
uji('ujian ELF lama dibuang', !src.includes('MUAT ENJIN'));

// --- 2. Simulasi render sebenar (DOM minimum) ---
function buatDom() {
  const els = {};
  function el(tag) {
    return {
      tagName: tag, children: [], style: {}, classList: { add(){}, remove(){}, toggle(){}, contains(){ return false; } },
      innerHTML: '', textContent: '', className: '',
      appendChild(c) { this.children.push(c); return c; },
      setAttribute(){}, addEventListener(){},
    };
  }
  return {
    els, el,
    getElementById(id) { return els[id] || (els[id] = el('div')); },
    createElement(t) { return el(t); },
  };
}

const dom = buatDom();
global.document = {
  getElementById: dom.getElementById,
  createElement: dom.createElement,
  addEventListener(){},
};
global.window = { MCNative: null };
global.setInterval = () => 0;
global.clearInterval = () => {};
global.setTimeout = (f) => 0;
global.localStorage = { getItem(){ return null; }, setItem(){} };
const logAsal = console.log;

// jalankan skrip HTML
const script = src.split('<script>')[1].split('</script>')[0];
try {
  // buang bahagian init yg perlukan DOM penuh
  const bersih = script.replace(/\(function init\(\)\{[\s\S]*?\}\)\(\);/, '');
  const fn = new Function('window', 'document', 'localStorage', 'setInterval',
                          'clearInterval', 'setTimeout', 'console', bersih + '\nreturn {S:S,TABS:TABS,renderTab:renderTab,H:H};');
  const api = fn(global.window, global.document, global.localStorage,
                 global.setInterval, global.clearInterval, global.setTimeout, global.console);

  // suntik data ujian seperti yg Swift hantar
  api.S.ios = { platform: 'ios', engine: false };
  api.S.platform = 'iOS 27.0.1';
  api.S.query = { online: true, hostname: 'MALAYCITY RP', players: 128, max: 500, ping: 42 };
  api.S.husk = {
    ada: true,
    report: '=== TRANSLATION LAYER (HUSK) ===\nAPI dilink : YA\nUJIAN PERANTI: [x18 ok, page ok]',
  };
  api.S.settings = {};

  // render tab Diagnostik
  api.renderTab('d');
  const body = dom.getElementById('setBody');
  const teks = JSON.stringify(body.children, (k, v) => k === 'children' ? v : v);

  uji('tab d render tanpa ralat', Array.isArray(body.children) && body.children.length >= 4);
  uji('nilai __huskreport diisi', !!api.S.settings.__huskreport && api.S.settings.__huskreport.includes('HUSK'));
  uji('nilai __srv diisi', String(api.S.settings.__srv).includes('128/500'));
  uji('nilai __plat diisi', String(api.S.settings.__plat).includes('iOS'));

} catch (e) {
  logAsal('  GAGAL  skrip HTML gagal dihurai: ' + e.message);
  gagal++;
}

console.log();
if (gagal === 0) {
  console.log('LULUS: tab Diagnostik berfungsi.');
  process.exit(0);
}
console.log('GAGAL: ' + gagal + ' isu.');
process.exit(1);
