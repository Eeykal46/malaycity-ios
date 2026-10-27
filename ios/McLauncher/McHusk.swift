import Foundation
import UIKit

/// Jambatan Swift ke translation layer Husk (GPL-2.0).
///
/// Husk menyelesaikan masalah yang kita jumpa 28 Okt: libGTASA.so ialah ELF,
/// dyld iOS menolaknya. Husk memetakan ELF sendiri ke memori iOS dan memenuhi
/// import Android melalui shim — binari TIDAK diubah.
///
/// PENTING: kita guna RUJUKAN LANGSUNG (bukan dlsym). dlsym menyebabkan
/// linker buang kod Husk sebagai dead code -> "API dilink : TIDAK".
/// mc_husk_bridge.c mengambil alamat setiap fungsi untuk paksa ia kekal.
final class McHusk {

    /// API penting ada? Dipanggil daripada mc_husk_bridge.c (rujukan langsung).
    private static let apiOK = mc_husk_semak_api() == 1

    static let shared = McHusk()

    private init() {
        NSLog("[MC] Husk: apiOK=%d tersedia=%d", McHusk.apiOK ? 1 : 0, tersedia ? 1 : 0)
    }

    /// Adakah kod Husk benar-benar dilink dan boleh dipanggil?
    var tersedia: Bool { McHusk.apiOK }

    // MARK: - Panggilan (langsung, tiada dlsym)

    private func denganPath(_ path: String, _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> Void) {
        path.withCString { c in
            var p: UnsafePointer<CChar>? = c
            withUnsafePointer(to: &p) { body($0) }
        }
    }

    /// Laporan apa yang APK perlukan (JSON Husk).
    func laporanScan(apk: String) -> String {
        var out = "{}"
        denganPath(apk) { ptr in
            guard let r = husk_tl_scan(ptr, 1) else { return }
            out = String(cString: r)
            husk_tl_free(r)
        }
        return out
    }

    /// Ujian peranti: x18, page 16 KiB, MAP_JIT.
    func ujianPeranti(bolehLaksana: Bool) -> String {
        guard let r = husk_tl_run_checks(bolehLaksana) else { return "[]" }
        let s = String(cString: r)
        husk_tl_free(r)
        return s
    }

    /// Jalankan APK. Pulangkan true jika berjaya bermula.
    func mula(apk: String, saat: Int32 = 0) -> Bool {
        var ok = false
        denganPath(apk) { ptr in
            ok = husk_tl_attempt_start(ptr, 1, saat) == 0
        }
        return ok
    }

    var selesai: Bool {
        var kod: Int32 = 0
        return husk_tl_attempt_done(&kod)
    }
    var frame: Int { Int(husk_tl_attempt_frames()) }

    func log() -> String {
        guard let r = husk_tl_attempt_log() else { return "" }
        let s = String(cString: r)
        husk_tl_free(r)
        return s
    }

    func henti() { husk_tl_attempt_stop() }
    func setSemula() { husk_tl_attempt_reset() }

    /// APK yang dibundle dalam app (bukan dimuat turun).
    var apkBundel: String? {
        Bundle.main.path(forResource: "MALAYCITY", ofType: "apk", inDirectory: "bundel")
    }
}
