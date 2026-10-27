import UIKit

/// Titik masuk app iOS MALAYCITY.
/// Padanan AndroidManifest Android: LauncherActivity = skrin pertama (HTML launcher),
/// SAMP (enjin) dibuka kemudian - di iOS enjin belum wujud (Fasa 3-5 dlm NOTA_PROJEK.txt).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = LauncherViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Padanan onDestroy() Android: hentikan muat turun (disambung bila dibuka semula).
        (window?.rootViewController as? LauncherViewController)?.pauseDownloads()
    }
}
