import Foundation
import Metal
import UIKit

/// Jenis mampatan tekstur GPU yang disokong (pvr / dxt / etc) - cermin `McGpu.java`.
///
/// Perbezaan penting dari Android: Java guna EGL + `GL_EXTENSIONS`; di iOS, lapisan GLES wujud
/// tetapi Apple tak lagi menyokongnya. Kita tanya Metal (GPU sebenar peranti).
///
/// Padanan dgn Android:
///   "pvr" = PVRTC  (PowerVR/Apple GPU)  <- peranti Apple
///   "etc" = ETC1   (majoriti Android)
///   "dxt" = S3TC   (desktop; iPhone TIDAK sokong)
///
/// PENTING: cache GTA 2.10 di hosting (dari kuzia/Android) berisi tekstur ETC/DXT, bukan PVRTC.
/// Jadi launcher ini sengaja memulangkan "" (semua fail dimuat turun) sehingga cache iOS tersedia.
/// Bila cache PVRTC ada di hosting, tukar `detect()` supaya pulangkan "pvr".
enum McGPU {

    /// Nama GPU untuk log / paparan.
    static var renderer: String {
        MTLCreateSystemDefaultDevice()?.name ?? "?"
    }

    /// Seperti McGpu.detect(): "" = semua fail tekstur dimuat turun.
    static func detect() -> String {
        NSLog("[MC_GPU] renderer=%@", renderer)

        // Semakan sebenar jika cache PVRTC disediakan kelak:
        //   iPhone (A7 ke atas) menyokong PVRTC -> "pvr".
        //   Simulator PowerVR juga "pvr", tetapi simulator bukan sasaran.
        if McConfig.allGPUTextures { return "" }

        #if targetEnvironment(simulator)
        return ""
        #else
        // Semua iPhone arm64 menyokong PVRTC v2 (GPU PowerVR/Apple).
        return "pvr"
        #endif
    }

    /// Huraian ringkas untuk tetapan launcher (padanan "GPU=..." dlm log Android).
    static var describe: String {
        let t = detect()
        return t.isEmpty ? "(tak diketahui - semua)" : t
    }
}
