import UIKit
import WebKit

/// Launcher MALAYCITY untuk iOS - ganti `LauncherActivity.java` (Android).
///
/// HTML yang SAMA digunakan (mobile/app/src/main/assets/launcher/index.html), jadi rupa
/// "Pulau Dinamik" tak perlu ditulis semula. Yang berbeza hanya jambatan:
///   Android: `web.addJavascriptInterface(new Bridge(), "MCNative")`  (panggilan Java segerak)
///   iOS    : `WKScriptMessageHandler` + shim JS yg memasang `window.MCNative`
///
/// Catatan jambatan:
///  - Semua kaedah JS (`ready`, `check`, `download`, `query`, `play`, ...) hanyalah
///    "hantar mesej" - tiada nilai pulangan, jadi async WKWebView tidak jadi masalah.
///  - SATU pengecualian: `getSettings()` dalam HTML dipanggil SECARA SEGERAK
///    (`var r=call("getSettings"); JSON.parse(r)`). Shim memulangkan cache
///    `window.__mcSettings` yang dikemas kini setiap kali tetapan berubah.
final class LauncherViewController: UIViewController {

    private var web: WKWebView!
    private let settings = McSettings(dataRoot: McConfig.dataRoot)
    private var dl: McDownloader?
    private let dlLock = NSLock()                 // lindungi `dl` (dibaca/ditulis merentas queue)

    private let bgQueue = DispatchQueue(label: "mc.bg", qos: .userInitiated)
    private let netQueue = DispatchQueue(label: "mc.net", qos: .userInitiated)

    private var destroyed = false
    private let prefs = UserDefaults.standard

    /// Hasil ujian GLES. Dijalankan SEKALI, dihantar bila HTML sudah bersedia.
    /// (Dulu dihantar sejurus selepas dijalankan -> HTML belum ada handler -> hilang.)
    private var glResult: GLProbe.Result?
    private var loadResult: MCLoadProbe.Result?
    private var htmlReady = false
    private let glLock = NSLock()

    /// Nama watak SA-MP: huruf/angka/underscore, boleh ada [ ] (tag klan). 1-24 aksara.
    /// Padanan `NICK.matcher(...)` dlm LauncherActivity.java.
    private static let nickPattern = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_\[\]]{1,24}$"#)

    // MARK: - Hayat

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 11/255, green: 5/255, blue: 8/255, alpha: 1)
        setupWebView()
        prepareDownloader()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    /// Ganti onDestroy() Android: hentikan muat turun bila app ditutup.
    /// Muat turun separuh kekal dlm .mcpart dan disambung pada buka berikutnya.
    /// NOTA: `destroyed` TIDAK disentuh di sini - iOS memanggil ini setiap kali app ke latar,
    /// bukan hanya bila activity dimusnahkan. Kalau `destroyed = true`, semua emit() mati
    /// selepas app dibuka semula.
    func pauseDownloads() {
        downloader()?.cancel()
    }

    deinit { downloader()?.cancel() }

    // MARK: - WebView

    private func setupWebView() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true                        // video latar (#bgVideo)
        cfg.mediaTypesRequiringUserActionForPlayback = []           // muzik muat turun tanpa ketik
        cfg.suppressesIncrementalRendering = false
        cfg.userContentController.add(self, name: "mcnative")
        cfg.userContentController.addUserScript(
            WKUserScript(source: LauncherViewController.bridgeShim,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))

        web = WKWebView(frame: view.bounds, configuration: cfg)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = self
        web.uiDelegate = self
        if #available(iOS 16.4, *) { web.isInspectable = true }      // Safari Web Inspector

        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        guard let index = Bundle.main.url(forResource: "index", withExtension: "html",
                                          subdirectory: "launcher") else {
            NSLog("[MC] launcher/index.html tiada dlm bundle!")
            showFatal("Fail launcher tiada dlm bundle app. Sila pasang semula app.")
            return
        }
        // benarkan akses baca ke folder launcher sahaja (media/bg.mp4, media/music.mp3)
        web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
    }

    private func showFatal(_ msg: String) {
        let tv = UILabel()
        tv.text = msg
        tv.textColor = .white
        tv.numberOfLines = 0
        tv.textAlignment = .center
        tv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tv.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            tv.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7),
        ])
    }

    /// Shim JS: pasang `window.MCNative` supaya index.html SAMA boleh guna tanpa diubah.
    /// Setiap kaedah = satu mesej ke Swift; `getSettings` pulangkan cache (HTML panggil segerak).
    private static let bridgeShim = """
    (function(){
      if (window.MCNative) { return; }
      var post = function(fn, args){
        try {
          window.webkit.messageHandlers.mcnative.postMessage({ fn: fn, args: args || [] });
        } catch (e) { console.log("MCNative." + fn + ": " + e); }
      };
      window.MCNative = {
        ready:        function(){ post("ready"); },
        check:        function(){ post("check"); },
        download:     function(){ post("download"); },
        verifyAll:    function(){ post("verifyAll"); },
        query:        function(){ post("query"); },
        setNick:      function(n){ post("setNick", [n]); },
        setSetting:   function(k, v){ post("setSetting", [k, String(v)]); },
        getSettings:  function(){ return window.__mcSettings || "{}"; },
        iosInfo:      function(){ post("iosInfo"); },
        copyText:     function(t){ post("copyText", [String(t)]); },
        openUrl:      function(u){ post("openUrl", [u]); },
        exitApp:      function(){ post("exitApp"); },
        play:         function(n){ post("play", [n]); }
      };
    })();
    """

    /// Java -> JS: `MCL.on(event, data)` - sama seperti `emit()` dlm LauncherActivity.java.
    private func emit(_ event: String, _ data: [String: Any]? = nil) {
        if destroyed { return }
        let json = LauncherViewController.jsonString(data ?? [:])
        let ev = LauncherViewController.jsStringLiteral(event)
        let js = "window.MCL&&MCL.on(\(ev),\(json))"
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.destroyed, let web = self.web else { return }
            web.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private static func jsonString(_ v: Any) -> String {
        guard JSONSerialization.isValidJSONObject(v),
              let d = try? JSONSerialization.data(withJSONObject: v),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Petik satu String jadi literal JS (`JSONSerialization` enggan terima String mentah).
    private static func jsStringLiteral(_ s: String) -> String {
        let wrapped: [String] = [s]
        guard let d = try? JSONSerialization.data(withJSONObject: wrapped),
              let all = String(data: d, encoding: .utf8) else { return "\"\"" }
        // "[\"...\"]" -> "\"...\""
        return String(all.dropFirst().dropLast())
    }

    // MARK: - Persediaan launcher

    private func prepareDownloader() {
        bgQueue.async { [weak self] in
            guard let self = self else { return }
            let gpu = McConfig.allGPUTextures ? "" : (self.prefs.string(forKey: "gpu") ?? McGPU.detect())
            if !McConfig.allGPUTextures, self.prefs.string(forKey: "gpu") == nil {
                self.prefs.set(gpu, forKey: "gpu")
            }
            NSLog("[MC] GPU=%@ data=%@", McGPU.describe, McConfig.dataRoot.path)

            // UJIAN GLES: jawab soalan paling kritikal projek (lihat GLProbe.swift).
            // SIMPAN hasilnya - jangan emit sekarang, HTML belum bersedia.
            let gl = GLProbe.run()
            NSLog("%@", GLProbe.report(gl))
            self.glLock.lock(); self.glResult = gl; self.glLock.unlock()
            self.simpanLaporanGl(gl)

            // UJIAN PENENTU: boleh tak iOS muatkan enjin ELF?
            let ld = MCLoadProbe.run()
            NSLog("%@", ld.report)
            self.glLock.lock(); self.loadResult = ld; self.glLock.unlock()

            self.sendGlProbeIfReady()

            let d = McDownloader(dataRoot: McConfig.dataRoot,
                                 privateDir: McConfig.privateRoot,
                                 gpuType: gpu)
            self.dlLock.lock(); self.dl = d; self.dlLock.unlock()
        }
    }

    /// McDownloader (nil jika belum siap). Selamat dari mana-mana queue.
    private func downloader() -> McDownloader? {
        dlLock.lock(); defer { dlLock.unlock() }
        return dl
    }

    /// Tunggu McDownloader siap dicipta (dipanggil di thread latar).
    private func waitDownloader() -> McDownloader? {
        for _ in 0..<50 {                                  // ~5 saat
            if let d = downloader() { return d }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return downloader()
    }

    /// Simpan laporan GLES ke Documents/gl_report.txt.
    /// Documents boleh dibuka dalam app Files (UIFileSharingEnabled=YES), jadi
    /// pemain boleh e-mel/AirDrop fail ini kalau tidak dapat salin teks.
    private func simpanLaporanGl(_ gl: GLProbe.Result) {
        let url = McConfig.dataRoot.appendingPathComponent("gl_report.txt")
        let teks = GLProbe.report(gl)
        do {
            try teks.write(to: url, atomically: true, encoding: .utf8)
            NSLog("[MC] laporan GLES disimpan: %@", url.path)
        } catch {
            NSLog("[MC] gagal simpan laporan GLES: %@", String(describing: error))
        }
    }

    /// Maklumat platform untuk HTML papar mesej yg betul.
    /// Enjin GTA SA untuk iOS belum wujud (lihat NOTA_PROJEK.txt Fasa 3-5),
    /// jadi launcher berterus-terang: main di Android buat masa ini.
    private func emitIosInfo() {
        emit("iosInfo", [
            "platform": "ios",
            "engine": false,
            "androidUrl": "https://malaycity.com/mobile/MALAYCITY.apk",
            "note": "Klien GTA SA untuk iOS sedang dibangunkan. Buat masa ini, main di Android.",
        ])
    }

    /// Hantar hasil ujian GLES bila HTML sudah bersedia DAN ujian sudah selesai.
    /// Dipanggil dari dua tempat: selepas GLProbe.run() dan selepas HTML hantar "ready".
    private func sendGlProbeIfReady() {
        glLock.lock()
        let gl = glResult
        let ld = loadResult
        let ready = htmlReady
        glLock.unlock()
        guard ready, let gl = gl else { return }

        emit("glProbe", [
            "ok": gl.ok,
            "render": gl.triangleRendered,
            "version": gl.version,
            "renderer": gl.renderer,
            "gl3": gl.gl3,
            "pvrtc": gl.pvrtc,
            "etc1": gl.etc1,
            "s3tc": gl.s3tc,
            "report": GLProbe.report(gl),
        ])

        if let ld = ld {
            emit("loadProbe", [
                "elfOK": ld.elfLoadOK,
                "machoOK": ld.machoStrukturSah,
                "controlOK": ld.controlOK,
                "report": ld.report,
            ])
        }
    }

    private func doCheck() {
        guard let d = waitDownloader() else { return }
        emit("checking", ["text": "Menyemak kemas kini…"])
        emit("check", d.check())
    }

    /// Server penuh (host/port/password) - hanya dlm app; HTML tak pernah nampak.
    private func serverInfo() -> [String: Any]? { waitDownloader()?.serverInfo }

    private func settingsJSON() -> [String: Any] {
        var o = settings.readAll()
        o["dataDir"] = McConfig.dataRoot.path
        o["version"] = "\(McConfig.versionName) (\(McConfig.versionCode))"
        return o
    }

    private func isNickValid(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return LauncherViewController.nickPattern.firstMatch(in: s, range: range) != nil
    }

    private func openExternal(_ urlString: String?) {
        guard let s = urlString?.trimmingCharacters(in: .whitespaces),
              let u = URL(string: s),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        DispatchQueue.main.async { UIApplication.shared.open(u, options: [:], completionHandler: nil) }
    }


    // MARK: - Arahan dari HTML

    private func handle(_ fn: String, _ args: [Any]) {
        switch fn {
        case "ready":
            // HTML siap: tandakan supaya hasil GLES (yg mungkin sudah selesai) dihantar.
            glLock.lock(); htmlReady = true; glLock.unlock()
            emitIosInfo()
            sendGlProbeIfReady()
            bgQueue.async { [weak self] in
                guard let self = self else { return }
                var st: [String: Any] = [
                    "version": McConfig.versionName,
                    "abi": McConfig.archLabel,
                    "platform": "iOS \(UIDevice.current.systemVersion)",
                ]
                let nick = self.settings.getNick()
                st["nick"] = nick.isEmpty ? (self.prefs.string(forKey: "nick") ?? "") : nick
                let set = self.settingsJSON()
                st["settings"] = set
                self.updateSettingsCache(set)
                self.emit("state", st)
                self.doCheck()
            }

        case "check":
            bgQueue.async { [weak self] in self?.doCheck() }

        case "download":
            bgQueue.async { [weak self] in
                guard let self = self, let d = self.waitDownloader() else { return }
                d.download(verifyAll: false) { [weak self] ev, data in
                    self?.emit(ev, data)
                }
            }

        case "verifyAll":
            bgQueue.async { [weak self] in
                guard let self = self, let d = self.waitDownloader() else { return }
                d.download(verifyAll: true) { [weak self] ev, data in
                    self?.emit(ev, data)
                }
            }

        case "query":
            netQueue.async { [weak self] in
                guard let self = self else { return }
                guard let srv = self.serverInfo() else {
                    self.emit("query", ["online": false])
                    return
                }
                let host = (srv["host"] as? String) ?? ""
                let port = (srv["port"] as? NSNumber)?.intValue ?? 7777
                self.emit("query", McQuery.query(host: host, port: port, timeoutMs: 2500))
            }

        case "iosInfo":
            emitIosInfo()

        case "setNick":
            let n = (args.first as? String) ?? ""
            let t = n.trimmingCharacters(in: .whitespaces)
            if isNickValid(t) { prefs.set(t, forKey: "nick") }

        case "setSetting":
            let k = (args.first as? String) ?? ""
            let v = args.count > 1 ? String(describing: args[1]) : ""
            bgQueue.async { [weak self] in
                guard let self = self else { return }
                _ = self.settings.set(k, v)
                let set = self.settingsJSON()
                self.updateSettingsCache(set)
                self.emit("settings", set)
            }

        case "openUrl":
            openExternal(args.first as? String)

        case "copyText":
            // WebView iOS tak selalu benarkan navigator.clipboard, jadi Swift buat.
            let t = (args.first as? String) ?? ""
            DispatchQueue.main.async {
                UIPasteboard.general.string = t
                NSLog("[MC] laporan disalin (%d aksara)", t.count)
            }

        case "exitApp":
            // Android: finishAndRemoveTask(). iOS tiada API "tutup app" rasmi.
            // HACK lazim: hantar aksi "suspend" ke UIApplication -> app masuk latar (tak dibunuh).
            // Nama pemilih dibina secara dinamik: `NSXPCConnection` itu macOS sahaja dan
            // `#selector(NSXPCConnection.suspend)` GAGAL compile untuk iOS.
            // `exit(0)` sengaja tidak dipakai (ditolak semasa review App Store).
            DispatchQueue.main.async {
                let sel = NSSelectorFromString("suspend")
                if UIApplication.shared.responds(to: sel) {
                    UIApplication.shared.perform(sel)
                }
            }

        case "play":
            let nick = ((args.first as? String) ?? "").trimmingCharacters(in: .whitespaces)
            play(nick)

        default:
            NSLog("[MC] arahan tak dikenali: %@", fn)
        }
    }


    /// Kemas kini cache yg dibaca oleh `MCNative.getSettings()` (panggilan segerak dlm HTML).
    private func updateSettingsCache(_ set: [String: Any]) {
        let payload = LauncherViewController.jsonString(set)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.destroyed, let web = self.web else { return }
            let js = "window.__mcSettings=\(LauncherViewController.jsStringLiteral(payload));"
            web.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// Tekan MAIN. Padanan `Bridge.play()` dlm LauncherActivity.java.
    /// Fasa 1 (launcher): server & nama disahkan dan disimpan, kemudian mesej jelas dipaparkan
    /// kerana enjin GTA SA untuk iOS belum wujud (Fasa 3-5 dlm NOTA_PROJEK.txt).
    private func play(_ nick: String) {
        bgQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isNickValid(nick) else {
                self.emit("playError", ["message": "Nama tidak sah"])
                return
            }
            guard let srv = self.serverInfo(),
                  !((srv["host"] as? String) ?? "").isEmpty else {
                self.emit("playError", ["message": "Maklumat server tiada - sambung internet & cuba lagi"])
                return
            }
            self.prefs.set(nick, forKey: "nick")
            do {
                try self.settings.writeClient(nick: nick)
            } catch {
                NSLog("[MC] play: gagal tulis settings.ini: %@", String(describing: error))
                self.emit("playError", ["message": "Gagal tulis settings.ini"])
                return
            }
            let host = (srv["host"] as? String) ?? ""
            let port = (srv["port"] as? NSNumber)?.intValue ?? 7777
            NSLog("[MC] play nick=%@ server=%@:%d", nick, host, port)

            // Enjin GTA SA iOS belum wujud. Nama & tetapan SUDAH disimpan (di atas),
            // jadi bila enjin siap, nama pemain sudah sedia. Sekarang: arahkan ke Android.
            self.emit("playError", [
                "message": "Klien iOS belum sedia. Nama disimpan. Muat turun app Android untuk main sekarang.",
                "androidUrl": "https://malaycity.com/mobile/MALAYCITY.apk",
                "offerAndroid": true,
            ])
        }
    }
}

// MARK: - Jambatan JS

extension LauncherViewController: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "mcnative",
              let body = message.body as? [String: Any],
              let fn = body["fn"] as? String else { return }
        handle(fn, body["args"] as? [Any] ?? [])
    }
}


// MARK: - Navigasi & media

extension LauncherViewController: WKNavigationDelegate, WKUIDelegate {

    /// Pautan luar -> Safari. Fail tempatan dlm bundle dibenarkan.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        if u.isFileURL {
            decisionHandler(.allow); return
        }
        if navigationAction.navigationType == .linkActivated {
            openExternal(u.absoluteString)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Renderer mati (padanan onRenderProcessGone Java): muat semula launcher, jangan biar app mati.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[MC] renderer launcher mati - dimuat semula")
        if destroyed { return }
        if let index = Bundle.main.url(forResource: "index", withExtension: "html",
                                       subdirectory: "launcher") {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
    }

    /// `alert()` dari HTML -> dialog asli.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: "MALAYCITY", message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    /// Dokumen selesai dimuat. `window.MCL` kini wujud, jadi hasil GLES boleh dihantar
    /// walaupun HTML belum panggil `ready` (jaring keselamatan kedua).
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[MC] HTML selesai dimuat")
        glLock.lock(); htmlReady = true; glLock.unlock()
        sendGlProbeIfReady()
    }
}

