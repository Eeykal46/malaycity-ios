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
        var machoLoadOK = false
        var machoError = ""
        var controlOK = false
        var controlError = ""
        var bundleHasSo = false
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

        // ---- 1. ELF ----
        // Cipta fail ELF minimum dlm tmp dan cuba muatkan.
        // Kita juga semak sama ada libGTASA.so sebenar ada dlm bundle/dokumen.
        let elfPath = NSTemporaryDirectory() + "probe.elf"
        let elfBytes: [UInt8] = [
            0x7F, 0x45, 0x4C, 0x46,            // \x7fELF
            0x02,                               // ELFCLASS64
            0x01,                               // ELFDATA2LSB
            0x01, 0x00,
        ] + [UInt8](repeating: 0, count: 56)
        r.elfMagic = "7F 45 4C 46 (ELF64)"
        try? Data(elfBytes).write(to: URL(fileURLWithPath: elfPath))

        if let h = dlopen(elfPath, RTLD_LAZY) {
            r.elfLoadOK = true
            dlclose(h)
        } else {
            r.elfError = String(cString: dlerror())
        }

        // Adakah libGTASA.so sebenar wujud di mana-mana yg boleh dibaca?
        let soPath = (McConfig.dataRoot.path as NSString).appendingPathComponent("libGTASA.so")
        r.bundleHasSo = FileManager.default.fileExists(atPath: soPath)
        if r.bundleHasSo {
            if let h = dlopen(soPath, RTLD_LAZY) {
                dlclose(h)
            } else {
                r.elfError += " | sebenar: " + String(cString: dlerror())
            }
        }

        // ---- 2. Mach-O dylib tanpa tandatangan ----
        // NOTA: versi pertama ujian ini SALAH - ia salin binari UTAMA (.app/McLauncher)
        // yang jenisnya MH_EXECUTE, lalu namakan .dylib. iOS tolak dgn mesej
        // "cannot dlopen a main executable" - itu BUKAN ujian tandatangan.
        // Sekarang: cipta Mach-O MH_DYLIB minimum yang sah, tanpa tandatangan.
        let dylibPath = NSTemporaryDirectory() + "probe2.dylib"
        try? FileManager.default.removeItem(atPath: dylibPath)
        if let dylib = MCLoadProbe.binaDylibMinimum() {
            try? dylib.write(to: URL(fileURLWithPath: dylibPath))
            if let h = dlopen(dylibPath, RTLD_LAZY) {
                r.machoLoadOK = true
                dlclose(h)
            } else {
                r.machoError = String(cString: dlerror())
            }
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

    private static func laporan(_ r: Result) -> String {
        var s = "=== UJIAN MUAT ENJIN DI IOS ===\n"
        s += "kawalan (libSystem) : \(r.controlOK ? "BERJAYA" : "GAGAL")\n"
        if !r.controlOK { s += "   \(r.controlError)\n" }
        s += "\n"
        s += "ELF  (\(r.elfMagic)) : \(r.elfLoadOK ? "DIMUAT" : "DITOLAK")\n"
        if !r.elfLoadOK { s += "   \(r.elfError)\n" }
        s += "libGTASA.so di Documents : \(r.bundleHasSo ? "ADA" : "tiada")\n"
        s += "\n"
        s += "Mach-O tanpa tandatangan : \(r.machoLoadOK ? "DIMUAT" : "DITOLAK")\n"
        if !r.machoLoadOK { s += "   \(r.machoError)\n" }
        s += "\n"
        if r.controlOK && !r.elfLoadOK {
            s += "KESIMPULAN: dlopen BERFUNGSI, tetapi ELF DITOLAK.\n"
            s += "Enjin MESTI ditukar ke Mach-O sebelum boleh dimuatkan.\n"
        }
        if !r.machoLoadOK {
            s += "Mach-O tanpa tandatangan juga ditolak -> perlu codesign.\n"
        }
        return s
    }
}
