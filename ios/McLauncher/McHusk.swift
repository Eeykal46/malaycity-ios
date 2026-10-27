import Foundation
import UIKit

/// Jambatan Swift ke translation layer Husk (GPL-2.0).
///
/// Husk menyelesaikan masalah yang kita jumpa 28 Okt: libGTASA.so ialah ELF,
/// dyld iOS menolaknya ("slice is not valid mach-o file"). Husk memetakan ELF
/// sendiri ke memori iOS pada page 16 KiB dan memenuhi 274 import Android
/// melalui shim — binari TIDAK diubah.
///
/// API Husk (husk-tl.h) dipanggil terus; tiada pembalut C tambahan:
///   husk_tl_scan        - laporan APK
///   husk_tl_run_checks  - ujian peranti (x18, page, MAP_JIT)
///   husk_tl_attempt_start - JALANKAN app
///   husk_tl_frame_acquire - ambil piksel untuk dipapar
final class McHusk {

    // MARK: - API C daripada husk-tl.h

    private typealias ScanFn = @convention(c) (UnsafePointer<UnsafePointer<CChar>?>?, Int32) -> UnsafeMutablePointer<CChar>?
    private typealias ChecksFn = @convention(c) (Bool) -> UnsafeMutablePointer<CChar>?
    private typealias AttemptStartFn = @convention(c) (UnsafePointer<UnsafePointer<CChar>?>?, Int32, Int32) -> Int32
    private typealias AttemptDoneFn = @convention(c) (UnsafeMutablePointer<Int32>?) -> Bool
    private typealias AttemptFramesFn = @convention(c) () -> Int32
    private typealias AttemptLogFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
    private typealias AttemptStopFn = @convention(c) () -> Void
    private typealias AttemptResetFn = @convention(c) () -> Void
    private typealias FreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private let scan: ScanFn?
    private let runChecks: ChecksFn?
    private let attemptStart: AttemptStartFn?
    private let attemptDone: AttemptDoneFn?
    private let attemptFrames: AttemptFramesFn?
    private let attemptLog: AttemptLogFn?
    private let attemptStop: AttemptStopFn?
    private let attemptReset: AttemptResetFn?
    private let tlFree: FreeFn?

    static let shared = McHusk()

    private init() {
        let h = dlopen(nil, RTLD_NOW)
        func sym<T>(_ n: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, n) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        scan = sym("husk_tl_scan", ScanFn.self)
        runChecks = sym("husk_tl_run_checks", ChecksFn.self)
        attemptStart = sym("husk_tl_attempt_start", AttemptStartFn.self)
        attemptDone = sym("husk_tl_attempt_done", AttemptDoneFn.self)
        attemptFrames = sym("husk_tl_attempt_frames", AttemptFramesFn.self)
        attemptLog = sym("husk_tl_attempt_log", AttemptLogFn.self)
        attemptStop = sym("husk_tl_attempt_stop", AttemptStopFn.self)
        attemptReset = sym("husk_tl_attempt_reset", AttemptResetFn.self)
        tlFree = sym("husk_tl_free", FreeFn.self)
        NSLog("[MC] Husk API: scan=%@ checks=%@ start=%@",
              scan != nil ? "ada" : "TIADA",
              runChecks != nil ? "ada" : "TIADA",
              attemptStart != nil ? "ada" : "TIADA")
    }

    /// Adakah kod Husk benar-benar dilink ke dalam app?
    var tersedia: Bool { scan != nil && attemptStart != nil }

    // MARK: - Panggilan

    private func denganPath(_ path: String, _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> Void) {
        path.withCString { c in
            var p: UnsafePointer<CChar>? = c
            withUnsafePointer(to: &p) { body($0) }
        }
    }

    /// Laporan apa yang APK perlukan (JSON Husk).
    func laporanScan(apk: String) -> String {
        guard let f = scan else { return "{\"error\":\"husk_tl_scan tiada\"}" }
        var out = "{}"
        denganPath(apk) { ptr in
            guard let r = f(ptr, 1) else { return }
            out = String(cString: r)
            tlFree?(r)
        }
        return out
    }

    /// Ujian peranti: x18, page 16 KiB, MAP_JIT.
    func ujianPeranti(bolehLaksana: Bool) -> String {
        guard let f = runChecks else { return "[]" }
        guard let r = f(bolehLaksana) else { return "[]" }
        let s = String(cString: r)
        tlFree?(r)
        return s
    }

    /// Jalankan app. Pulangkan true jika berjaya bermula.
    func mula(apk: String, saat: Int32 = 0) -> Bool {
        guard let f = attemptStart else { return false }
        var ok = false
        denganPath(apk) { ptr in
            ok = f(ptr, 1, saat) == 0
        }
        return ok
    }

    var selesai: Bool {
        guard let f = attemptDone else { return true }
        return f(nil)
    }

    var frame: Int { Int(attemptFrames?() ?? 0) }

    func log() -> String {
        guard let f = attemptLog, let r = f() else { return "" }
        let s = String(cString: r)
        tlFree?(r)
        return s
    }

    func henti() { attemptStop?() }
    func setSemula() { attemptReset?() }
}
