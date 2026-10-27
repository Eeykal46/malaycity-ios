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

    /// Jenis tekstur yang perlu untuk GPU ini.
    /// iPhone/iPad arm64 = GPU PowerVR/Apple -> PVRTC ("pvr").
    /// Manifest hosting memang ada tekstur pvr (21 fail, 286 MB), jadi ini selamat.
    /// "" = muat turun semua jenis (jika PVRTC tak disokong / ujian).
    static func detect() -> String {
        NSLog("[MC_GPU] renderer=%@", renderer)

        if McConfig.allGPUTextures { return "" }

        #if targetEnvironment(simulator)
        return "pvr"          // simulator Apple juga PVRTC
        #else
        return "pvr"
        #endif
    }

    /// Huraian ringkas untuk tetapan launcher (padanan "GPU=..." dlm log Android).
    static var describe: String {
        let t = detect()
        return t.isEmpty ? "(tak diketahui - semua)" : t
    }
}
