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

        // libGame.so: cari BUNDLE dahulu, kemudian Documents.
        // Lib dibundle dalam app (enjin/bundel/lib) — bukan dimuat turun.
        if let soPath = McHuskGTASA.cariLib("libGame.so")
                    ?? McHuskGTASA.cariLib("libGTASA.so") {
            let mb = (try? FileManager.default.attributesOfItem(atPath: soPath)[.size] as? NSNumber)?.intValue ?? 0
            let dari = soPath.contains(".app/") ? "bundle" : "Documents"
            lap += "libGame.so  : ADA (\(mb / 1048576) MB, \(dari))\n"
        } else {
            lap += "libGame.so  : TIADA (bundle enjin/bundel/lib + Documents/lib)\n"
            ok = false
        }

        if let a = McHuskGTASA.cariLib("libANGLE-shared.dylib") {
            lap += "ANGLE       : ADA (\(a.contains(".app/") ? "bundle" : "Documents"))\n"
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

        // APK untuk DexIndex - launcher boleh bina, atau kita guna DEX sahaja
        let apk = root.appendingPathComponent("MALAYCITY.apk").path
        lap += "MALAYCITY.apk : \(FileManager.default.fileExists(atPath: apk) ? "ADA" : "TIADA (perlu utk DexIndex)")"

        lap += "\n\n\(ok ? "SIAP" : "BELUM SIAP")"
        return (ok, lap)
    }

    /// Cari fail dalam bundle app dahulu, kemudian Documents/ dan Documents/lib/.
    /// Lib dibundle (enjin/bundel/lib) — bukan dimuat turun pemain.
    static func cariLib(_ nama: String) -> String? {
        // 1. bundle: McLauncher.app/lib/nama (folder reference)
        let bundle = Bundle.main.bundlePath
        for sub in ["lib/", "bundel/lib/", ""] {
            let p = bundle + "/" + sub + nama
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        // 2. Documents (jika launcher muat turun kemudian)
        let root = McConfig.dataRoot
        for sub in ["lib/", ""] {
            let p = root.appendingPathComponent(sub + nama).path
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    /// Sediakan APK minimum untuk tl_dexidx_open: ZIP berisi classes.dex sahaja.
    /// Husk hanya perlukan classes.dex (kelas Java oswrapper Rockstar), bukan
    /// APK penuh 36 MB. Jika launcher sudah letak MALAYCITY.apk, guna itu.
    static func sediakanApkDex() -> String? {
        let root = McConfig.dataRoot

        // 1. APK penuh jika ada (paling mudah)
        let penuh = root.appendingPathComponent("MALAYCITY.apk").path
        if FileManager.default.fileExists(atPath: penuh) { return penuh }

        // 2. classes.dex sahaja -> bungkus jadi ZIP minimum
        let dex = root.appendingPathComponent("classes.dex").path
        guard FileManager.default.fileExists(atPath: dex),
              let dexData = FileManager.default.contents(atPath: dex) else { return nil }

        let out = root.appendingPathComponent("dexonly.apk")
        if FileManager.default.fileExists(atPath: out.path) { return out.path }

        // ZIP minimum (stored, tanpa mampatan) — cukup untuk tl_zip_open
        var z = Data()
        var nama = Array("classes.dex".utf8)
        let saiz = UInt32(dexData.count)
        let crc = McHuskGTASA.crc32(dexData)

        var local = Data()
        local.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])   // sig
        withUnsafeBytes(of: UInt16(20).littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: crc.littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: saiz.littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: saiz.littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(nama.count).littleEndian) { local.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { local.append(contentsOf: $0) }
        local.append(contentsOf: nama)
        let localOffset = z.count
        z.append(local)

        let dataStart = z.count
        z.append(dexData)
        let centralOffset = z.count

        // central directory
        z.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        for v: UInt16 in [20, 20, 0, 0, 0, 0] { withUnsafeBytes(of: v.littleEndian) { z.append(contentsOf: $0) } }
        withUnsafeBytes(of: crc.littleEndian) { z.append(contentsOf: $0) }
        withUnsafeBytes(of: saiz.littleEndian) { z.append(contentsOf: $0) }
        withUnsafeBytes(of: saiz.littleEndian) { z.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(nama.count).littleEndian) { z.append(contentsOf: $0) }
        for v: UInt16 in [0, 0, 0, 0, 0] { withUnsafeBytes(of: v.littleEndian) { z.append(contentsOf: $0) } }
        withUnsafeBytes(of: UInt32(localOffset).littleEndian) { z.append(contentsOf: $0) }
        z.append(contentsOf: nama)
        let centralSize = z.count - centralOffset

        // EOCD
        z.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        for v: UInt16 in [0, 0, 1, 1] { withUnsafeBytes(of: v.littleEndian) { z.append(contentsOf: $0) } }
        withUnsafeBytes(of: UInt32(centralSize).littleEndian) { z.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(centralOffset).littleEndian) { z.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { z.append(contentsOf: $0) }
        _ = dataStart

        do {
            try z.write(to: URL(fileURLWithPath: out.path))
            NSLog("[MC] dexonly.apk dibina (%d bait)", z.count)
            return out.path
        } catch {
            NSLog("[MC] gagal bina dexonly.apk: %@", String(describing: error))
            return nil
        }
    }

    /// CRC32 untuk ZIP (stored entry).
    static func crc32(_ d: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in d {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
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
        let angle = McHuskGTASA.cariLib("libANGLE-shared.dylib") ?? ""

        // APK untuk tl_dexidx_open (kelas Java oswrapper Rockstar).
        // DexIndex hanya baca classes.dex dari ZIP — bukan APK penuh.
        let apk = McHuskGTASA.sediakanApkDex() ?? ""
        guard !apk.isEmpty else {
            lock.lock(); berjalan = false; lock.unlock()
            selesai(false, "classes.dex tiada - launcher perlu sediakan Dex")
            return
        }

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
