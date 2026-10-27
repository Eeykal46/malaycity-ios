import Foundation
import CryptoKit

/// Enjin fail game MALAYCITY - cermin `McDownloader.java` (logik & API sama).
///
///  - manifest.json (website) = senarai fail {path, size, md5, gpu?, keep?} + server + berita + versi app.
///  - Fail yg sudah disahkan dicatat dlm .mc_index.json (path -> md5:size) -> semakan pantas tanpa hash.
///  - Muat turun bersambung (HTTP Range) ke fail .mcpart, disahkan saiz + MD5, baru ditukar nama.
///  - Fail ikut GPU (".dxt." / ".etc." / ".pvr." dlm nama) hanya untuk GPU peranti ini.
///
/// Perbezaan sengaja dari versi Android (bukan perubahan tingkah laku):
///  - URLSession + delegate yg menstrim ke cakera (Android guna HttpURLConnection + FileOutputStream).
///    Completion handler `dataTask(with:completionHandler:)` mengumpul seluruh fail dlm RAM -
///    cache beratus MB akan kehabisan memori.
///  - MD5 dibaca semula dari cakera selepas muat turun (hasil sama, tiada buffer besar).
final class McDownloader {

    struct Entry {
        let path: String
        let size: Int64
        let md5: String
        let gpu: String
        let keep: Bool
        let url: URL
    }

    typealias Listener = (String, [String: Any]) -> Void

    /// Keadaan kongsi antara worker + thread kemajuan (ganti AtomicLong/AtomicReference dlm Java).
    final class ProgressState {
        let lock = NSLock()
        var done: Int64 = 0
        var curFile = ""
        var phase = "download"
        var failMsg: String?
        var saveCounter = 0
        var progressRun = true

        func add(_ n: Int64) { lock.lock(); done += n; lock.unlock() }

        func set(file: String, phase: String) {
            lock.lock(); curFile = file; self.phase = phase; lock.unlock()
        }

        func snapshot() -> (done: Int64, file: String, phase: String) {
            lock.lock(); defer { lock.unlock() }
            return (done, curFile, phase)
        }

        func fail(_ msg: String) {
            lock.lock(); if failMsg == nil { failMsg = msg }; lock.unlock()
        }

        /// true jika sudah ada kegagalan direkod (ambil kunci sendiri).
        func hasFailed() -> Bool {
            lock.lock(); defer { lock.unlock() }
            return failMsg != nil
        }
    }

    private let root: URL
    private let privDir: URL
    private let gpuType: String

    private var index: [String: String] = [:]        // path -> "md5:size"
    private let indexLock = NSLock()

    private(set) var manifest: [String: Any]?
    private(set) var entries: [Entry] = []

    private let runLock = NSLock()
    private var running = false
    private var cancelled = false

    init(dataRoot: URL, privateDir: URL, gpuType: String) {
        self.root = dataRoot
        self.privDir = privateDir
        self.gpuType = gpuType
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: privateDir, withIntermediateDirectories: true)
        loadIndex()
    }

    var getRoot: URL { root }
    var getManifest: [String: Any]? { manifest }

    /// Server penuh (host/port/password) - HANYA untuk dalam app, tidak pernah ke JS.
    var serverInfo: [String: Any]? { manifest?["server"] as? [String: Any] }

    func cancel() { runLock.lock(); cancelled = true; runLock.unlock() }

    private var isCancelled: Bool { runLock.lock(); defer { runLock.unlock() }; return cancelled }

    private func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    // MARK: - Alat kecil

    private static func fileSize(_ u: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: u.path) else { return -1 }
        return (attrs[.size] as? NSNumber)?.int64Value ?? -1
    }

    private static func hex(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }

    private static func int(_ v: Any?, _ def: Int = 0) -> Int {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let n = Int(s) { return n }
        return def
    }

    private static func int64(_ v: Any?) -> Int64 {
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String, let n = Int64(s) { return n }
        return 0
    }

    private static func freeSpace(_ u: URL) -> Int64 {
        let vals = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let v = vals?.volumeAvailableCapacityForImportantUsage { return Int64(v) }
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: u.path)
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    private static func describe(_ e: Error) -> String {
        if let m = e as? McError, case .http(let c) = m { return "HTTP \(c)" }
        return e.localizedDescription
    }

    // MARK: - Manifest

    /// Muat turun teks (manifest / cache). Segerak - pemanggil sentiasa di thread latar.
    private func fetchText(_ u: URL) throws -> String {
        var req = URLRequest(url: u, timeoutInterval: McConfig.readTimeout)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("MALAYCITY-iOS/" + McConfig.versionName, forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var out: Result<String, Error> = .failure(McError.network("tiada jawapan"))
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err = err { out = .failure(err); return }
            guard let http = resp as? HTTPURLResponse else {
                out = .failure(McError.network("bukan HTTP")); return
            }
            guard http.statusCode == 200, let data = data else {
                out = .failure(McError.http(http.statusCode)); return
            }
            out = .success(String(decoding: data, as: UTF8.self))
        }.resume()
        _ = sem.wait(timeout: .now() + McConfig.readTimeout + McConfig.connectTimeout)
        switch out {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }

    private static func encodePath(_ p: String) -> String {
        p.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    /// Laluan selamat: tiada keluar folder, tiada nama fail tempahan kita.
    private static func safePath(_ p: String) -> Bool {
        if p.isEmpty || p.hasPrefix("/") || p.contains("\\") || p.contains("\0") { return false }
        for s in p.split(separator: "/", omittingEmptySubsequences: false) {
            if s == ".." || s == "." || s.isEmpty { return false }
        }
        return !p.hasSuffix(McConfig.partExt) && !p.hasPrefix(".mc_")
    }

    /// Jenis GPU bagi satu laluan: guna `gpu` dlm manifest jika ada, jika tidak ikut akhiran nama.
    private func gpuOf(_ path: String, declared: String) -> String {
        let d = declared.trimmingCharacters(in: .whitespaces)
        if !d.isEmpty { return d.lowercased() }
        let l = path.lowercased()
        if l.contains(".dxt.") { return "dxt" }
        if l.contains(".etc.") { return "etc" }
        if l.contains(".pvr.") { return "pvr" }
        return ""
    }

    private func parseEntries(_ m: [String: Any], manifestURL: URL) -> [Entry] {
        let base = URL(string: (m["baseUrl"] as? String) ?? "files/", relativeTo: manifestURL) ?? manifestURL
        guard let files = m["files"] as? [[String: Any]] else { return [] }

        var out: [Entry] = []
        for f in files {
            guard let path = f["path"] as? String else { continue }
            if !McDownloader.safePath(path) {
                NSLog("[MC_DL] laluan ditolak: %@", path)
                continue
            }
            let gpu = gpuOf(path, declared: (f["gpu"] as? String) ?? "")
            if !gpu.isEmpty && !gpuType.isEmpty && gpu != gpuType { continue }
            guard let u = URL(string: McDownloader.encodePath(path), relativeTo: base) else { continue }
            out.append(Entry(path: path,
                             size: McDownloader.int64(f["size"]),
                             md5: ((f["md5"] as? String) ?? "").lowercased(),
                             gpu: gpu,
                             keep: (f["keep"] as? Bool) ?? false,
                             url: u))
        }
        return out
    }

    // MARK: - Indeks fail disahkan

    private func loadIndex() {
        let f = root.appendingPathComponent(McConfig.indexFile)
        guard let data = try? Data(contentsOf: f),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return }
        indexLock.lock(); index = o; indexLock.unlock()
    }

    private func saveIndex() {
        indexLock.lock()
        let snapshot = index
        indexLock.unlock()

        let f = root.appendingPathComponent(McConfig.indexFile)
        let tmp = root.appendingPathComponent(McConfig.indexFile + ".tmp")
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot) else { return }
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: f.path) {
                try FileManager.default.removeItem(at: f)
            }
            try FileManager.default.moveItem(at: tmp, to: f)
        } catch {
            NSLog("[MC_DL] simpan indeks gagal: %@", String(describing: error))
        }
    }

    private static func key(_ e: Entry) -> String { e.md5 + ":" + String(e.size) }

    /// Fail sah tanpa hash (indeks + saiz). keep=true: cukup wujud (fail tetapan pemain).
    private func isOk(_ e: Entry) -> Bool {
        let f = url(e.path)
        guard FileManager.default.fileExists(atPath: f.path) else { return false }
        if e.keep { return true }
        if McDownloader.fileSize(f) != e.size { return false }
        indexLock.lock(); let known = index[e.path]; indexLock.unlock()
        return McDownloader.key(e) == known
    }

    private func missing(_ list: [Entry]) -> [Entry] { list.filter { !isOk($0) } }

    private static func sum(_ l: [Entry]) -> Int64 { l.reduce(0) { $0 + $1.size } }


    // MARK: - Semakan (thread latar)

    /// Semak manifest & fail. Objek yg dipulangkan dihantar ke HTML sbg event "check".
    /// Padanan `check(int versionCode)` dlm Java.
    func check() -> [String: Any] {
        var r: [String: Any] = [:]
        var text: String
        var online = true

        do {
            text = try fetchText(McConfig.manifestURL)
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8))     // sah JSON?
            try? text.write(to: privDir.appendingPathComponent(McConfig.manifestCache),
                            atomically: true, encoding: .utf8)
        } catch {
            NSLog("[MC_DL] manifest gagal: %@", String(describing: error))
            online = false
            var isHTTP = false
            if let m = error as? McError, case .http(let code) = m {
                r["message"] = "Pelayan kemas kini: HTTP \(code)"
                isHTTP = true
            } else {
                r["message"] = "Tiada sambungan internet"
            }
            guard let cached = try? String(contentsOf: privDir.appendingPathComponent(McConfig.manifestCache),
                                          encoding: .utf8) else {
                r["status"] = isHTTP ? "error" : "offline"
                r["canPlay"] = false
                return r
            }
            text = cached
        }

        guard let parsed = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            r["status"] = "error"
            r["message"] = "Manifest rosak: bukan JSON"
            r["canPlay"] = false
            return r
        }

        manifest = parsed
        entries = parseEntries(parsed, manifestURL: McConfig.manifestURL)
        McDownloader.copyPublic(parsed, into: &r)

        let need = missing(entries)
        if !online {
            r["status"] = "offline"
            r["canPlay"] = need.isEmpty
            return r
        }

        let app = parsed["app"] as? [String: Any]
        if let app = app {
            r["apkUrl"] = (app["apkUrl"] as? String) ?? ""
            if McDownloader.int(app["minVersionCode"]) > McConfig.versionCode {
                r["status"] = "app_required"
                return r
            }
        }
        if !need.isEmpty {
            r["status"] = "need"
            r["count"] = need.count
            r["bytes"] = McDownloader.sum(need)
            indexLock.lock(); let hasIndex = !index.isEmpty; indexLock.unlock()
            r["update"] = hasIndex
            return r
        }
        if let app = app, McDownloader.int(app["latestVersionCode"]) > McConfig.versionCode {
            r["status"] = "app_update"
        } else {
            r["status"] = "ok"
        }
        return r
    }

    /// host/port TIDAK didedahkan ke HTML (sama macam copyPublic dlm Java).
    private static func copyPublic(_ m: [String: Any], into r: inout [String: Any]) {
        if let srv = m["server"] as? [String: Any] {
            r["server"] = ["name": (srv["name"] as? String) ?? "MALAYCITY"]
        }
        if let news = m["news"] { r["news"] = news }
        if let links = m["links"] { r["links"] = links }
    }


    // MARK: - Muat turun (thread latar). verifyAll=true: hash semula SEMUA fail.

    func download(verifyAll: Bool, listener: @escaping Listener) {
        runLock.lock()
        if running { runLock.unlock(); return }          // sudah berjalan
        running = true
        cancelled = false
        runLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { runLock.lock(); running = false; runLock.unlock() }
            runDownload(verifyAll: verifyAll, listener: listener)
        }
    }

    private func runDownload(verifyAll: Bool, listener: @escaping Listener) {
        var list = entries
        if list.isEmpty {
            let c = check()                              // belum semak / tiada manifest
            list = entries
            if list.isEmpty {
                emitErr(listener, "Tiada senarai fail",
                        (c["message"] as? String) ?? "Semak sambungan internet.")
                return
            }
        }

        if verifyAll {
            indexLock.lock(); index.removeAll(); indexLock.unlock()
            saveIndex()
        }

        var need: [Entry] = verifyAll ? list : missing(list)
        if verifyAll {
            need = need.filter { !($0.keep && FileManager.default.fileExists(atPath: url($0.path).path)) }
        }
        let total = McDownloader.sum(need)

        // ruang storan: baki yg belum ada di cakera (fail sedia ada saiz sama mungkin cuma disahkan)
        var toFetch: Int64 = 0
        for e in need {
            if McDownloader.fileSize(url(e.path)) == e.size { continue }
            let pSize = McDownloader.fileSize(url(e.path + McConfig.partExt))
            let have = (pSize > 0 && pSize < e.size) ? pSize : 0
            toFetch += e.size - have
        }

        let free = McDownloader.freeSpace(root)
        if toFetch + McConfig.spaceMargin > free {
            listener("nospace", ["need": toFetch + McConfig.spaceMargin, "free": free])
            return
        }

        let st = ProgressState()

        // thread kemajuan: event "progress" setiap 300 ms (sama kadar dgn Java)
        Thread.detachNewThread { [self] in
            var lastT = DispatchTime.now().uptimeNanoseconds
            var lastB: Int64 = 0
            var speed = 0.0
            while true {
                st.lock.lock()
                if !st.progressRun { st.lock.unlock(); return }
                st.lock.unlock()

                let snap = st.snapshot()
                let now = DispatchTime.now().uptimeNanoseconds
                let inst = Double(snap.done - lastB) / (Double(now - lastT) / 1e9)
                speed = speed == 0 ? inst : speed * 0.8 + inst * 0.2
                lastT = now; lastB = snap.done
                listener("progress", [
                    "done": min(snap.done, total), "total": total,
                    "speed": snap.phase == "verify" ? 0 : Int64(max(0, speed)),
                    "file": snap.file, "phase": snap.phase,
                ])
                Thread.sleep(forTimeInterval: 0.3)
            }
        }

        // worker selari terhad (McConfig.parallel)
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: McConfig.parallel)
        for e in need {
            sem.wait()
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                defer { sem.signal(); group.leave() }
                // PENTING: jangan pegang st.lock semasa memanggil kaedah ProgressState
                // (NSLock bukan rekursif -> deadlock).
                if isCancelled || st.hasFailed() { return }
                do {
                    try fetchOne(e, st)
                    indexLock.lock(); index[e.path] = McDownloader.key(e); indexLock.unlock()
                    st.lock.lock()
                    st.saveCounter += 1
                    let n = st.saveCounter
                    st.lock.unlock()
                    if n % 25 == 0 { saveIndex() }
                } catch {
                    NSLog("[MC_DL] gagal %@: %@", e.path, String(describing: error))
                    if !isCancelled {
                        st.fail(e.path + ": " + McDownloader.describe(error))
                    }
                }
            }
        }
        group.wait()

        st.lock.lock()
        st.progressRun = false
        let finalFail = st.failMsg
        st.lock.unlock()
        saveIndex()

        if let finalFail = finalFail {
            emitErr(listener, "Muat turun gagal", "Fail: \(finalFail).")
        } else if isCancelled {
            emitErr(listener, "Muat turun dihentikan", "")
        } else if !missing(entries).isEmpty {
            emitErr(listener, "Fail tidak lengkap", "Ada fail gagal disahkan.")
        } else {
            listener("done", ["total": total])
        }
    }

    private func emitErr(_ l: Listener, _ msg: String, _ detail: String) {
        l("dlerror", ["message": msg, "detail": detail])
    }


    /// MD5 satu fail (baca 64 KB sekali jalan). Pulangkan hex huruf kecil.
    private func md5OfFile(_ f: URL, _ st: ProgressState? = nil) throws -> String {
        let fh = try FileHandle(forReadingFrom: f)
        defer { try? fh.close() }
        var hasher = Insecure.MD5()
        while true {
            if isCancelled { throw McError.network("dihentikan") }
            let chunk = try fh.read(upToCount: 1 << 16) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            if let st = st { st.add(Int64(chunk.count)) }
        }
        return McDownloader.hex(Data(hasher.finalize())).lowercased()
    }

    /// Muat turun satu fail: guna semula fail sedia ada jika saiz sama, sambung .mcpart,
    /// sahkan saiz + MD5, baru tukar nama. (padanan fetchOne dlm Java)
    private func fetchOne(_ e: Entry, _ st: ProgressState) throws {
        let target = url(e.path)
        let part = url(e.path + McConfig.partExt)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)

        // 1) Fail sedia ada saiz sama -> sahkan sahaja (tiada muat turun)
        if McDownloader.fileSize(target) == e.size {
            if e.md5.isEmpty { st.add(e.size); return }
            st.set(file: e.path, phase: "verify")
            let h = try md5OfFile(target, st)
            if h == e.md5 { return }
            st.add(-e.size)
            NSLog("[MC_DL] rosak, muat turun semula: %@", e.path)
        }

        var lastError: Error?
        for attempt in 1...McConfig.retries {
            if isCancelled { break }
            var counted: Int64 = 0                 // kemajuan cubaan ini (ditolak jika gagal)
            do {
                var have = McDownloader.fileSize(part)
                if have < 0 || have > e.size {
                    try? FileManager.default.removeItem(at: part)
                    have = 0
                }
                st.set(file: e.path, phase: "download")

                if have < e.size {
                    let got = try McFileFetch.fetch(url: e.url, into: part, from: have) { n in
                        st.add(n)
                        counted += n
                    }
                    have += got
                }
                if have != e.size {
                    throw McError.network("saiz \(have) != \(e.size)")
                }
                if !e.md5.isEmpty {
                    st.set(file: e.path, phase: "verify")
                    let h = try md5OfFile(part)
                    if h != e.md5 {
                        try? FileManager.default.removeItem(at: part)
                        throw McError.network("MD5 tak sepadan")
                    }
                }
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: part, to: target)
                return
            } catch {
                lastError = error
                // kemajuan cubaan yg gagal ditarik balik (padanan done.addAndGet(-counted) Java)
                if counted != 0 { st.add(-counted) }
                if isCancelled { break }
                NSLog("[MC_DL] %@ cubaan %d: %@", e.path, attempt, String(describing: error))
                Thread.sleep(forTimeInterval: Double(attempt))
            }
        }
        throw lastError ?? McError.network("dihentikan")
    }
}


// MARK: - Muat turun satu fail ke cakera (strim, bukan RAM)

/// Strim satu URL ke fail dgn HTTP Range, segerak (blok thread pemanggil).
/// Menggantikan HttpURLConnection + FileOutputStream dlm versi Android.
enum McFileFetch {

    /// @param from offset sambung (0 = mula baru)
    /// @param onBytes dipanggil bagi setiap ketulan diterima (untuk kemajuan)
    /// @return bilangan bait BARU ditulis
    static func fetch(url: URL, into part: URL, from: Int64,
                      onBytes: @escaping (Int64) -> Void) throws -> Int64 {
        var req = URLRequest(url: url, timeoutInterval: McConfig.readTimeout)
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if from > 0 { req.setValue("bytes=\(from)-", forHTTPHeaderField: "Range") }

        let collector = Collector(part: part, startAt: from, onBytes: onBytes)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: queue)

        let sem = DispatchSemaphore(value: 0)
        collector.waiter = sem
        session.dataTask(with: req).resume()

        if sem.wait(timeout: .now() + McConfig.readTimeout * 6) == .timedOut {
            session.invalidateAndCancel()
            throw McError.network("tamat masa")
        }
        session.finishTasksAndInvalidate()
        if let err = collector.error { throw err }
        return collector.written
    }

    /// Delegate URLSession yg menulis terus ke fail; tiada buffer besar dlm memori.
    private final class Collector: NSObject, URLSessionDataDelegate {
        private let part: URL
        private let onBytes: (Int64) -> Void

        var waiter: DispatchSemaphore?
        private(set) var error: Error?
        private(set) var written: Int64 = 0

        private var handle: FileHandle?
        private var appendFrom: Int64
        private var finished = false

        init(part: URL, startAt: Int64, onBytes: @escaping (Int64) -> Void) {
            self.part = part
            self.onBytes = onBytes
            self.appendFrom = startAt
        }

        private func finish(_ err: Error?) {
            if finished { return }
            finished = true
            if error == nil, let err = err { error = err }
            try? handle?.close()
            handle = nil
            waiter?.signal()
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse else {
                error = McError.network("bukan HTTP")
                completionHandler(.cancel)
                return
            }
            let code = http.statusCode
            if code == 206 {
                // sambung berjaya - kekalkan offset
            } else if code == 200 {
                appendFrom = 0          // pelayan abaikan Range -> tulis semula dari awal
            } else {
                error = McError.http(code)
                completionHandler(.cancel)
                return
            }
            do {
                if appendFrom == 0 || !FileManager.default.fileExists(atPath: part.path) {
                    FileManager.default.createFile(atPath: part.path, contents: nil)
                }
                let h = try FileHandle(forWritingTo: part)
                try h.seek(toOffset: UInt64(appendFrom))
                handle = h
            } catch {
                self.error = error
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !finished, error == nil, let h = handle else { return }
            do {
                try h.write(contentsOf: data)
            } catch {
                self.error = error
                dataTask.cancel()
                return
            }
            written += Int64(data.count)
            onBytes(Int64(data.count))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError err: Error?) {
            finish(err)
        }
    }
}

// MARK: - Ralat

enum McError: LocalizedError {
    case http(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .http(let c): return "HTTP \(c)"
        case .network(let m): return m
        }
    }
}

