import Foundation

/// Tetapan launcher <-> SAMP/settings.ini (dibaca libsamp: settings.cpp).
/// Cermin `McSettings.java` - nama kunci & nilai lalai SAMA dgn settings.cpp.
final class McSettings {
    /// kunciJS, seksyen, kunciIni, jenis, lalai
    private struct Entry {
        let js: String
        let section: String
        let key: String
        let isBool: Bool
        let def: String
    }

    private static let map: [Entry] = [
        Entry(js: "fpsLimit",        section: "gui",    key: "FPSLimit",        isBool: false, def: "60"),
        Entry(js: "fpsCounter",      section: "gui",    key: "fps",             isBool: true,  def: "false"),
        Entry(js: "cutout",          section: "gui",    key: "cutout",          isBool: true,  def: "false"),
        Entry(js: "radarRect",       section: "gui",    key: "radarrect",       isBool: true,  def: "false"),
        Entry(js: "chatLines",       section: "gui",    key: "ChatMaxMessages", isBool: false, def: "6"),
        Entry(js: "androidKeyboard", section: "gui",    key: "androidkeyboard", isBool: true,  def: "false"),
        Entry(js: "autoAim",         section: "client", key: "autoaim",         isBool: true,  def: "false"),
        Entry(js: "firstPerson",     section: "gui",    key: "firstperson",     isBool: true,  def: "true"),
        Entry(js: "hpText",          section: "gui",    key: "hparmourtext",    isBool: true,  def: "false"),
        Entry(js: "voice",           section: "gui",    key: "VoiceChatEnable", isBool: true,  def: "true"),
    ]

    private let file: URL
    private let lock = NSLock()

    init(dataRoot: URL) {
        self.file = dataRoot.appendingPathComponent("SAMP/settings.ini")
    }

    private func open() throws -> McIni {
        var ini = McIni(url: file)
        try ini.load()
        return ini
    }

    private static func parseBool(_ v: String?, _ d: Bool) -> Bool {
        guard let v = v?.trimmingCharacters(in: .whitespaces).lowercased() else { return d }
        if v == "1" || v == "true" || v == "yes" || v == "on" { return true }
        if v == "0" || v == "false" || v == "no" || v == "off" { return false }
        return d
    }

    /// Semua tetapan dlm bentuk yg difahami HTML (kunci JS -> Bool/Int).
    func readAll() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: Any] = [:]
        do {
            let ini = try open()
            for e in McSettings.map {
                let v = ini.get(e.section, e.key)
                if e.isBool {
                    out[e.js] = McSettings.parseBool(v, Bool(e.def) ?? false)
                } else {
                    let d = Int(e.def) ?? 0
                    out[e.js] = v.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? d
                }
            }
        } catch {
            for e in McSettings.map {
                out[e.js] = e.isBool ? (Bool(e.def) ?? false) : (Int(e.def) ?? 0)
            }
        }
        return out
    }

    /// @return true jika kunci dikenali & disimpan
    func set(_ jsKey: String, _ value: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let e = McSettings.map.first(where: { $0.js == jsKey }) else { return false }
        var v: String
        if e.isBool {
            v = McSettings.parseBool(value, false) ? "true" : "false"
        } else {
            guard let n = Int(value.trimmingCharacters(in: .whitespaces)) else { return false }
            v = String(n)
        }
        do {
            var ini = try open()
            _ = ini.put(e.section, e.key, v)
            try ini.store()
            return true
        } catch {
            return false
        }
    }

    func getNick() -> String {
        lock.lock(); defer { lock.unlock() }
        return (try? open().get("client", "name")) ?? ""
    }

    /// Ditulis sejurus sebelum game dimulakan. HANYA nama.
    /// Ip/port/kata laluan server TIDAK disimpan dlm settings.ini (fail ini boleh dibaca/diubah
    /// pemain) - ia datang dari manifest & dihantar ke game dlm memori (sama keputusan 21 Okt).
    func writeClient(nick: String) throws {
        lock.lock(); defer { lock.unlock() }
        var ini = try open()
        _ = ini.put("client", "name", nick)
        ini.remove("client", "host")
        ini.remove("client", "port")
        ini.remove("client", "password")
        try ini.store()
    }
}
