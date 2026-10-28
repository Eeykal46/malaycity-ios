// McHuskGTASA.swift - Jalankan enjin GTA SA melalui Husk 3.1.
//
// CARA IA BERFUNGSI (dibaca dari husk-tl-gtasa.c):
//   1. tl_ga_start(cfg) - muat libGame.so + siapkan dunia Java (oswrapper)
//   2. tl_ga_run()      - thread enjin: frame loop, render ke metal_layer
//   3. tl_ga_touch      - sentuh masuk ke enjin
//
// TIADA APK PENUH untuk pemain: launcher iOS uruskan muat turun data,
// kemudian bina MALAYCITY.apk kecil (Dex sahaja) untuk Husk.
import Foundation
import Metal
import QuartzCore

final class McHuskGTASA {

    static let shared = McHuskGTASA()

    private var lapisan: CAMetalLayer?
    private var berjalan = false
    private let lock = NSLock()

    private init() {}

    /// Semua bahagian ada? Dipaparkan di Diagnostik.
    func semakPersediaan() -> (ok: Bool, lap: String) {
        var lap = "=== PERSEDIAAN ENJIN GTA SA ===\n"
        var ok = true
        let root = McConfig.dataRoot

        let api = mc_husk_semak_api() == 1
        lap += "API Husk    : \(api ? "ADA" : "TIADA")\n"
        if !api { ok = false }

        // libGame.so (= libGTASA.so), nama berbeza sahaja
        let calon = ["lib/libGame.so", "lib/libGTASA.so", "libGame.so", "libGTASA.so"]
        var soPath: String? = nil
        for c in calon {
            let p = root.appendingPathComponent(c).path
            if FileManager.default.fileExists(atPath: p) { soPath = p; break }
        }
        if let soPath = soPath {
            let mb = (try? FileManager.default.attributesOfItem(atPath: soPath)[.size] as? NSNumber)?.intValue ?? 0
            lap += "libGame.so  : ADA (\(mb / 1048576) MB)\n"
        } else {
            lap += "libGame.so  : TIADA (perlu lib/libGame.so atau libGTASA.so)\n"
            ok = false
        }

        if Bundle.main.path(forResource: "libANGLE-shared", ofType: "dylib") != nil {
            lap += "ANGLE       : ADA\n"
        } else {
            lap += "ANGLE       : TIADA (bina dgn .github/workflows/angle.yml)\n"
            ok = false
        }

        if FileManager.default.fileExists(atPath: root.appendingPathComponent("texdb").path) {
            lap += "data GTA    : ADA (texdb/)\n"
        } else {
            lap += "data GTA    : TIADA (launcher patut muat turun texdb/)\n"
            ok = false
        }

        let metal = MTLCreateSystemDefaultDevice() != nil
        lap += "Metal       : \(metal ? "ADA" : "TIADA")\n"
        if !metal { ok = false }

        lap += "\n\(ok ? "SIAP" : "BELUM SIAP")"
        return (ok, lap)
    }

    /// Mula enjin. `selesai` dipanggil di thread utama.
    func mula(lebar: Int, tinggi: Int, selesai: @escaping (Bool, String) -> Void) {
        lock.lock()
        if berjalan {
            lock.unlock()
            selesai(false, "Enjin sudah berjalan")
            return
        }
        berjalan = true
        lock.unlock()

        let (ok, lapPersediaan) = semakPersediaan()
        guard ok else {
            lock.lock(); berjalan = false; lock.unlock()
            selesai(false, lapPersediaan)
            return
        }

        guard let dev = MTLCreateSystemDefaultDevice() else {
            lock.lock(); berjalan = false; lock.unlock()
            selesai(false, "Tiada Metal device")
            return
        }

        let root = McConfig.dataRoot
        let angle = Bundle.main.path(forResource: "libANGLE-shared", ofType: "dylib") ?? ""
        let apk = root.appendingPathComponent("MALAYCITY.apk").path

        let layer = CAMetalLayer()
        layer.device = dev
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.frame = CGRect(x: 0, y: 0, width: lebar, height: tinggi)
        layer.drawableSize = CGSize(width: lebar, height: tinggi)
        lapisan = layer

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var cfg = tl_ga_config()
            cfg.apk_path = (apk as NSString).utf8String
            cfg.data_dir = (root.path as NSString).utf8String
            cfg.package_name = ("com.malaycity.mobile" as NSString).utf8String
            cfg.width = Int32(lebar)
            cfg.height = Int32(tinggi)
            cfg.metal_layer = Unmanaged.passUnretained(layer).toOpaque()
            cfg.angle_egl = (angle as NSString).utf8String
            cfg.angle_gles = nil
            cfg.frame_dir = nil
            cfg.frame_every = 0

            NSLog("[MC] tl_ga_start ...")
            let started = tl_ga_start(&cfg)
            NSLog("[MC] tl_ga_start = %d", started ? 1 : 0)

            guard started else {
                self?.lock.lock(); self?.berjalan = false; self?.lock.unlock()
                DispatchQueue.main.async {
                    selesai(false, "tl_ga_start gagal - lihat husk_report.txt")
                }
                return
            }

            NSLog("[MC] tl_ga_run (frame loop) ...")
            _ = tl_ga_run()
            let f = tl_ga_frames()
            NSLog("[MC] tl_ga_run tamat, frame=%lu", f)

            self?.lock.lock(); self?.berjalan = false; self?.lock.unlock()
            DispatchQueue.main.async {
                selesai(true, "Enjin tamat selepas \(f) frame")
            }
        }
    }

    var frame: Int { Int(tl_ga_frames()) }

    func sentuh(fasa: Int32, id: Int32, x: Float, y: Float) {
        tl_ga_touch(fasa, id, x, y)
    }

    func jeda(_ v: Bool) { tl_ga_set_paused(v) }
}
