import Foundation

/// UJIAN PENENTU: boleh tak iOS memuatkan libGTASA.so (ELF Android)?
///
/// Ini soalan yang menentukan sama ada seluruh pendekatan "guna enjin Android
/// di iOS" boleh berfungsi. Bukan andaian - diukur pada peranti.
///
/// Tiga ujian:
///   1. ELF  -> dlopen  (jangkaan: GAGAL, dyld hanya terima Mach-O)
///   2. Mach-O tanpa tandatangan -> dlopen  (jangkaan: GAGAL, perlu codesign)
///   3. dylib sistem -> dlopen (kawalan: patut BERJAYA, buktikan dlopen berfungsi)
///
/// Jika (1) dan (2) gagal tetapi (3) berjaya, maka:
///   - masalahnya BUKAN dlopen kita
///   - enjin MESTI ditukar ke Mach-O DAN ditandatangan
final class MCLoadProbe {

    struct Result {
        var elfMagic = ""
        var elfLoadOK = false
        var elfError = ""
        /// Struktur dylib yang kita bina SAH (disemak sendiri, bukan dlopen).
        var machoStrukturSah = false
        var machoError = ""
        var controlOK = false
        var controlError = ""
        var bundleHasSo = false
        var soMagic = ""
        var soIsELF = false
        var report = ""
    }

    static func run() -> Result {
        var r = Result()

        // ---- 3. KAWALAN: dylib sistem (mesti berjaya) ----
        if let h = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY) {
            r.controlOK = true
            dlclose(h)
        } else {
            r.controlError = String(cString: dlerror())
        }

        // ---- 1. ELF: SEMAK MAGIC SAHAJA, JANGAN dlopen ----
        // CRASH: dlopen() pada fail ELF boleh menyebabkan dyld crash pada iOS.
        // Kita sudah tahu jawapannya dari dokumentasi: dyld hanya terima Mach-O.
        // Jadi cukup semak magic - tiada risiko.
        let elfPath = NSTemporaryDirectory() + "probe.elf"
        let elfBytes: [UInt8] = [
            0x7F, 0x45, 0x4C, 0x46,            // \x7fELF
            0x02,                               // ELFCLASS64
            0x01,                               // ELFDATA2LSB
            0x01, 0x00,
        ] + [UInt8](repeating: 0, count: 56)
        r.elfMagic = "7F 45 4C 46 (ELF64)"
        try? Data(elfBytes).write(to: URL(fileURLWithPath: elfPath))
        // (tiada dlopen di sini - sebabnya di atas)

        // Adakah libGTASA.so sebenar wujud, dan adakah ia ELF?
        let soPath = (McConfig.dataRoot.path as NSString).appendingPathComponent("libGTASA.so")
        r.bundleHasSo = FileManager.default.fileExists(atPath: soPath)
        if r.bundleHasSo {
            // PENTING: JANGAN dlopen sebelum semak magic.
            // dyld boleh CRASH (bukan pulangkan nil) apabila diberi fail
            // bukan-Mach-O yang besar. Kita semak 4 bait pertama dahulu.
            if let hd = FileManager.default.contents(atPath: soPath), hd.count >= 4 {
                let m = Array(hd.prefix(4))
                let isELF = (m[0] == 0x7F && m[1] == 0x45 && m[2] == 0x4C && m[3] == 0x46)
                let isMachO = (m[0] == 0xCF && m[1] == 0xFA && m[2] == 0xED && m[3] == 0xFE)
                    || (m[0] == 0xCE && m[1] == 0xFA && m[2] == 0xED && m[3] == 0xFE)
                r.soMagic = String(format: "%02X %02X %02X %02X", m[0], m[1], m[2], m[3])
                if isELF {
                    // Terbukti ELF. dlopen TIDAK akan berjaya - jangan cuba.
                    r.elfError = "libGTASA.so ialah ELF (\(r.soMagic)) - dyld iOS hanya terima Mach-O"
                    r.soIsELF = true
                } else if isMachO {
                    if let h = dlopen(soPath, RTLD_LAZY) {
                        r.elfLoadOK = true
                        dlclose(h)
                    } else {
                        r.elfError = "Mach-O tetapi dlopen gagal: " + String(cString: dlerror())
                    }
                } else {
                    r.elfError = "magic tidak dikenali: \(r.soMagic)"
                }
            } else {
                r.elfError = "tidak dapat baca 4 bait pertama libGTASA.so"
            }
        }

        // ---- 2. Mach-O: SEMAK SAHAJA, JANGAN dlopen ----
        // CRASH: versi sebelum ini dlopen() dylib sintetik lalu dlclose().
        // Dylib tanpa kod + tanpa tandatangan boleh menyebabkan dyld crash
        // (bukan pulangkan nil) - app tidak boleh dibuka langsung.
        //
        // Jadi: kita bina dylib dan SAHKAN strukturnya sendiri (semak bait),
        // tidak menyerahkannya kepada dyld. Ujian "boleh codesign" dibuat
        // berasingan di GitHub Actions pada macOS, bukan pada peranti pemain.
        if let dylib = MCLoadProbe.binaDylibMinimum() {
            let sah = MCLoadProbe.semakStrukturDylib(dylib)
            r.machoStrukturSah = sah.ok
            r.machoError = sah.nota
            // TIDAK dlopen. Tiada risiko crash.
        } else {
            r.machoError = "gagal bina dylib minimum"
        }

        r.report = laporan(r)
        return r
    }

    /// Bina Mach-O MH_DYLIB minimum yang sah (arm64, tiada kod, tiada tandatangan).
    /// Tujuan: uji sama ada iOS menerima dylib TANPA tandatangan.
    ///
    /// Struktur: mach_header_64 + LC_SEGMENT_64(__TEXT) + LC_ID_DYLIB + symtab kosong.
    private static func binaDylibMinimum() -> Data? {
        var d = Data()

        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        // ---- kira saiz command dahulu ----
        // LC_SEGMENT_64(__TEXT): 72 bait + 1 seksyen(80) = 152
        let segSize: UInt32 = 72 + 80
        // LC_ID_DYLIB: 24 + nama (25 bait, dipad 8)
        let idName = "mcprobe"
        let idNamePadded = ((idName.utf8.count + 1) + 7) / 8 * 8
        let idSize: UInt32 = 24 + UInt32(idNamePadded)

        let textOff: UInt64 = 0x1000
        let textSize: UInt64 = 0x1000       // 1 halaman, kosong

        let sizeofcmds = segSize + idSize

        // ---- mach_header_64 ----
        u32(0xFEEDFACF)              // magic
        u32(0x0100000C)              // cputype arm64
        u32(0)                       // cpusubtype
        u32(6)                       // filetype = MH_DYLIB   <-- PENTING
        u32(2)                       // ncmds
        u32(sizeofcmds)
        u32(0)                       // flags
        u32(0)                       // reserved

        // ---- LC_SEGMENT_64 __TEXT ----
        u32(0x19)                    // cmd
        u32(segSize)
        var segName = Array("__TEXT".utf8)
        segName.append(contentsOf: [UInt8](repeating: 0, count: 16 - segName.count))
        d.append(contentsOf: segName)   // segname[16]

        u64(textOff)                 // vmaddr
        u64(textSize)                // vmsize
        u64(textOff)                 // fileoff
        u64(0)                       // filesize (0 = tiada isi)
        u32(5)                       // maxprot  r-x
        u32(5)                       // initprot r-x
        u32(1)                       // nsects
        u32(0)                       // flags

        // section_64 (80 bait)
        var sect = Array("__text".utf8)
        sect.append(contentsOf: [UInt8](repeating: 0, count: 16 - sect.count))
        d.append(contentsOf: sect)
        d.append(contentsOf: Array("__TEXT".utf8))
        d.append(contentsOf: [UInt8](repeating: 0, count: 16 - "__TEXT".utf8.count))
        u64(textOff)                 // addr
        u64(textSize)                // size
        u32(UInt32(textOff))         // offset
        u32(4)                       // align
        u32(0)                       // reloff
        u32(0)                       // nreloc
        u32(0x80000400)              // flags (S_ATTR_PURE_INSTRUCTIONS|S_ATTR_SOME_INSTRUCTIONS)
        u32(0); u32(0); u32(0)       // reserved1..3

        // ---- LC_ID_DYLIB ----
        u32(0xD)                     // cmd
        u32(idSize)
        u32(0)                       // name offset (relatif ke permulaan command)
        u32(0)                       // timestamp
        u32(0x10000)                 // current version 1.0.0
        u32(0x10000)                 // compatibility version
        var nm = Array(idName.utf8); nm.append(0)
        while nm.count < idNamePadded { nm.append(0) }
        d.append(contentsOf: nm)

        // pad ke textOff
        while d.count < Int(textOff) { d.append(0) }

        return d
    }

    /// Semak struktur Mach-O yang kita bina sendiri. TIADA dlopen.
    /// Pulangkan (ok, nota).
    private static func semakStrukturDylib(_ d: Data) -> (ok: Bool, nota: String) {
        guard d.count >= 32 else { return (false, "fail terlalu kecil") }

        func r32(_ o: Int) -> UInt32 {
            guard o + 4 <= d.count else { return 0 }
            return d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
        }

        let magic = r32(0)
        if magic != 0xFEEDFACF { return (false, "magic salah: 0x\(String(magic, radix: 16))") }
        let cputype = r32(4)
        if cputype != 0x0100000C { return (false, "cputype bukan arm64") }
        let filetype = r32(12)
        if filetype != 6 { return (false, "filetype bukan MH_DYLIB (\(filetype))") }
        let ncmds = r32(16)
        let sizeofcmds = r32(20)

        var off = 32
        var jumpaSeg = false
        for _ in 0..<ncmds {
            if off + 8 > d.count { return (false, "command terkeluar fail") }
            let cmd = r32(off)
            let sz = r32(off + 4)
            if cmd == 0x19 { jumpaSeg = true }
            off += Int(sz)
            if sz == 0 { return (false, "saiz command 0") }
        }
        if !jumpaSeg { return (false, "tiada LC_SEGMENT_64") }
        if off - 32 != Int(sizeofcmds) {
            return (false, "sizeofcmds tak padan (\(off - 32) vs \(sizeofcmds))")
        }
        return (true, "MH_DYLIB arm64, \(ncmds) command, \(d.count) bait")
    }

    private static func laporan(_ r: Result) -> String {
        var s = "=== UJIAN MUAT ENJIN DI IOS ===\n"
        s += "kawalan (libSystem) : \(r.controlOK ? "BERJAYA" : "GAGAL")\n"
        if !r.controlOK { s += "   \(r.controlError)\n" }
        s += "\n"
        s += "libGTASA.so di Documents : \(r.bundleHasSo ? "ADA" : "tiada")\n"
        if !r.soMagic.isEmpty {
            s += "magic 4 bait : \(r.soMagic)"
            s += r.soIsELF ? "  <-- ELF (Android)\n" : "\n"
        }
        if !r.elfError.isEmpty { s += "   \(r.elfError)\n" }
        s += "\n"
        s += "Struktur Mach-O (binaan sendiri) : "
        s += r.machoStrukturSah ? "SAH\n" : "TIDAK SAH\n"
        if !r.machoError.isEmpty { s += "   \(r.machoError)\n" }
        s += "\n"
        if r.soIsELF {
            s += "KESIMPULAN: enjin ialah ELF. dyld iOS HANYA terima Mach-O.\n"
            s += "Enjin MESTI ditukar ke Mach-O (dan ditandatangan) dahulu.\n"
            s += "Tiada jumlah kerja pada client boleh mengubah fakta ini.\n"
        } else if r.elfLoadOK {
            s += "KESIMPULAN: enjin Mach-O BERJAYA dimuatkan!\n"
        }
        return s
    }
}
