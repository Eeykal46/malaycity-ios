import Foundation

/// Tetapan tetap launcher - cermin `mobile/app/src/main/java/com/malaycity/mobile/launcher/mc/McConfig.java`.
/// SEMUA lain (server, berita, link, senarai fail, versi app) datang dari manifest.json di website,
/// jadi boleh diubah tanpa build app baru.
enum McConfig {
    /// Fail manifest di website. Fail game dimuat turun dari "baseUrl" dlm manifest.
    static let manifestURL = URL(string: "https://malaycity.com/mobile/manifest.json")!

    /// true = muat turun SEMUA fail tekstur (.dxt./.etc./.pvr.) tanpa ikut GPU.
    /// iPhone = GPU PowerVR/Apple sahaja -> launcher Android dapat "pvr" atau "etc".
    /// KEKAL true sehingga cache iOS (tekstur PVRTC) disediakan di hosting.
    static let allGPUTextures = true

    /// Bilangan fail dimuat turun serentak.
    static let parallel = 3

    /// Cubaan semula setiap fail sebelum menyerah.
    static let retries = 4

    /// Ruang lebihan wajib selepas muat turun (bait).
    static let spaceMargin: Int64 = 64 * 1024 * 1024

    static let connectTimeout: TimeInterval = 15
    static let readTimeout: TimeInterval = 60

    /// Fail dlm folder data.
    static let indexFile = ".mc_index.json"            // fail yg sudah disahkan
    static let manifestCache = ".mc_manifest.json"      // salinan manifest terakhir (main luar talian)
    static let partExt = ".mcpart"                      // muat turun separuh (disambung)

    /// Folder fail game (padanan getExternalFilesDir(null) Android).
    /// iOS: Documents/ - boleh dilihat dlm app Files kerana UIFileSharingEnabled.
    static var dataRoot: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if !FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
        return u
    }

    /// Folder peribadi (cache manifest: ada IP/port/kata laluan server) - padanan getFilesDir.
    /// iOS: Library/Application Support - tidak dipapar dlm Files.
    static var privateRoot: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if !FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
        return u
    }

    static var versionName: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    static var versionCode: Int {
        Int((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0") ?? 0
    }

    /// Sama mesej dgn "abi" Android (HTML papar dlm teks versi).
    static var archLabel: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        // iOS 26 = arm64 sahaja (tiada 32-bit sejak iOS 11)
        return "64-bit"
        #endif
    }
}
