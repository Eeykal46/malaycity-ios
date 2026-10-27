// Semakan: setiap call("...") dlm index.html ada padanan dlm shim window.MCNative.
// Jalankan: node d:\MALAYCITY_FULL\ios\semak_bridge.js
//
// HTML dicari mengikut turutan (repo penuh, kemudian repo slim):
//   1. ../mobile/app/src/main/assets/launcher/index.html   (sumber kebenaran Android)
//   2. ./launcher/index.html                                (salinan yg dikomit)
const fs = require('fs');
const path = require('path');

const calon = [
  path.join(__dirname, 'launcher', 'index.html'),          // versi iOS (diubah untuk iOS)
  path.join(__dirname, '..', 'mobile', 'app', 'src', 'main', 'assets', 'launcher', 'index.html'),
];
const HTML = calon.find(p => fs.existsSync(p));
if (!HTML) {
  console.error('GAGAL: index.html tak dijumpai. Dicari:\n  ' + calon.join('\n  '));
  process.exit(1);
}
const SWIFT = path.join(__dirname, 'McLauncher', 'LauncherViewController.swift');
console.log('HTML :', HTML);

const html = fs.readFileSync(HTML, 'utf8');
const swift = fs.readFileSync(SWIFT, 'utf8');

const calls = [...new Set([...html.matchAll(/call\("(\w+)"/g)].map(m => m[1]))].sort();

// kaedah dlm objek window.MCNative (8 ruang inden diikuti nama: function)
const shimBlock = swift.split('window.MCNative = {')[1].split('})();')[0];
const shims = [...new Set([...shimBlock.matchAll(/^\s*(\w+):\s*function/gm)].map(m => m[1]))].sort();

console.log('HTML call()    :', calls.join(', '));
console.log('shim MCNative  :', shims.join(', '));

const missing = calls.filter(c => !shims.includes(c));
const extra = shims.filter(s => !calls.includes(s));

console.log(missing.length ? 'HILANG dlm shim : ' + missing.join(', ') : 'HILANG dlm shim : (tiada)');
console.log(extra.length ? 'LEBIH dlm shim  : ' + extra.join(', ') : 'LEBIH dlm shim  : (tiada)');

// setiap arahan shim mesti dikendalikan dlm switch handle() -
// KECUALI yg dikendalikan shim sendiri (tiada perjalanan ke Swift).
const SHIM_ONLY = ['getSettings'];   // pulangkan window.__mcSettings (HTML panggil segerak)
const handled = [...swift.matchAll(/case "(\w+)":/g)].map(m => m[1]);
const unhandled = shims.filter(s => !handled.includes(s) && !SHIM_ONLY.includes(s));
console.log(unhandled.length ? 'TAK DIENDALI Swift: ' + unhandled.join(', ') : 'TAK DIENDALI Swift: (tiada)');
console.log('SHIM_ONLY (sengaja): ' + SHIM_ONLY.join(', '));

// event Java->JS: setiap MCL.on/X dlm HTML mesti ada pemanggil emit() dgn nama sama
const inHtml = [...new Set([...html.matchAll(/^\s{2}(\w+):\s*function\(d\)/gm)].map(m => m[1]))].sort();
const emitted = [...new Set([...swift.matchAll(/emit\("(\w+)"/g)].map(m => m[1]))].sort();
// progress/done/dlerror/nospace datang dari McDownloader (dihantar melalui listener).
// Baris komen dibuang dahulu supaya contoh dlm dokumentasi tidak dikira.
const swiftCode = swift.split('\n').filter(l => !l.trim().startsWith('///') && !l.trim().startsWith('//')).join('\n');
const fromDownloader = [...new Set([
  ...swiftCode.matchAll(/listener\("(\w+)"/g),
  ...swiftCode.matchAll(/\bl\("(\w+)"/g),
].map(m => m[1]))];
const allEmitted = [...new Set([...emitted, ...fromDownloader])].sort();
console.log('event HTML     :', inHtml.join(', '));
console.log('emit() Swift   :', allEmitted.join(', '));
const orphan = allEmitted.filter(e => !inHtml.includes(e));
console.log(orphan.length ? 'EMIT tiada handler HTML: ' + orphan.join(', ') : 'EMIT tiada handler HTML: (tiada)');

const bad = missing.length + unhandled.length + orphan.length;
console.log(bad === 0 ? '\nLULUS: jambatan sepadan dgn HTML.' : '\nGAGAL: ' + bad + ' isu.');
process.exit(bad === 0 ? 0 : 1);
