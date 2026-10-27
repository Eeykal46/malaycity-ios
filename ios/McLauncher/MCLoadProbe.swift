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

        // ---- 2. Mach-O tanpa tandatangan ----
        // Ambil binari app sendiri, salin, dan cuba dlopen. Ia Mach-O SAH
        // tetapi tiada tandatangan dylib -> uji keperluan codesign.
        if let exec = Bundle.main.executableURL {
            let copyPath = NSTemporaryDirectory() + "probe.dylib"
            try? FileManager.default.removeItem(atPath: copyPath)
            try? FileManager.default.copyItem(atPath: exec.path, toPath: copyPath)
            if let h = dlopen(copyPath, RTLD_LAZY) {
                r.machoLoadOK = true
                dlclose(h)
            } else {
                r.machoError = String(cString: dlerror())
            }
        }

        r.report = laporan(r)
        return r
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
