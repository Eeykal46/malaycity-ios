import Foundation

/// Pembaca/penulis fail INI ringkas - ganti `org.ini4j.Wini` (tiada dlm iOS).
///
/// Sebab ditulis sendiri, bukan library:
///  - fail settings.ini dibaca oleh libsamp (settings.cpp) dengan format tertentu;
///  - komen & susunan seksyen sedia ada MESTI kekal (fail datang dari manifest game);
///  - keperluan cuma: get(section,key), put(section,key,value), remove(section,key).
///
/// Perilaku sama dgn Wini dlm McSettings.java:
///  - kunci & seksyen KES-SENSITIF (sama macam ini4j lalai);
///  - `setEscape(false)` -> nilai ditulis apa adanya (nama watak/kata laluan);
///  - kunci dipisah `=`, ruang di sekeliling dipangkas.
struct McIni {
    private(set) var lines: [String] = []
    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// Baca fail; tiada fail = senarai kosong (pemanggil yang cipta bila perlu).
    mutating func load() throws {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    /// Tulis semula ke cakera (atomik: tulis tmp -> pindah). Buat folder jika tiada.
    func store() throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n")
        let tmp = dir.appendingPathComponent(url.lastPathComponent + ".tmp")
        try text.write(to: tmp, atomically: false, encoding: .utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    // MARK: - cari

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    private static func isSectionLine(_ s: String) -> String? {
        let t = trimmed(s)
        guard t.hasPrefix("["), t.hasSuffix("]") else { return nil }
        return String(t.dropFirst().dropLast())
    }

    /// Pisah "kunci = nilai"; nil jika baris bukan pasangan kunci/nilai.
    private static func keyValue(_ s: String) -> (String, String)? {
        guard let eq = s.firstIndex(of: "=") else { return nil }
        let k = trimmed(String(s[s.startIndex..<eq]))
        let v = trimmed(String(s[s.index(after: eq)...]))
        return k.isEmpty ? nil : (k, v)
    }

    /// Indeks baris (dlm `lines`) bagi kunci dlm seksyen. -1 = tiada.
    private func indexOf(section: String, key: String) -> Int {
        var cur = ""
        for (i, raw) in lines.enumerated() {
            if let sec = McIni.isSectionLine(raw) { cur = sec; continue }
            guard cur == section, let (k, _) = McIni.keyValue(raw) else { continue }
            if k == key { return i }
        }
        return -1
    }

    /// Indeks baris pengepala seksyen. -1 = tiada (perlu dicipta).
    private func indexOfSection(_ section: String) -> Int {
        for (i, raw) in lines.enumerated() where McIni.isSectionLine(raw) == section { return i }
        return -1
    }

    // MARK: - baca / tulis

    func get(_ section: String, _ key: String) -> String? {
        let i = indexOf(section: section, key: key)
        guard i >= 0, let (_, v) = McIni.keyValue(lines[i]) else { return nil }
        return v
    }

    mutating func put(_ section: String, _ key: String, _ value: String) -> Bool {
        let line = "\(key) = \(value)"
        let i = indexOf(section: section, key: key)
        if i >= 0 { lines[i] = line; return true }

        let secIdx = indexOfSection(section)
        if secIdx < 0 {                                  // seksyen tak ada -> tambah di hujung
            if let last = lines.last, !last.isEmpty { lines.append("") }
            lines.append("[\(section)]")
            lines.append(line)
            return true
        }
        // letak selepas baris terakhir seksyen itu (sebelum seksyen lain / hujung fail)
        var insertAt = secIdx + 1
        var j = secIdx + 1
        while j < lines.count {
            if McIni.isSectionLine(lines[j]) != nil { break }
            if McIni.keyValue(lines[j]) != nil { insertAt = j + 1 }
            j += 1
        }
        lines.insert(line, at: insertAt)
        return true
    }

    mutating func remove(_ section: String, _ key: String) {
        let i = indexOf(section: section, key: key)
        if i >= 0 { lines.remove(at: i) }
    }
}
