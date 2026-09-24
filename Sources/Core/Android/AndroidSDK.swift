import Foundation

/// Locates the Android SDK on this Mac. Nothing is bundled; Google's license forbids redistribution.
struct AndroidSDK: Sendable {
    let root: URL

    var adb: URL { root.appending(path: "platform-tools/adb") }

    /// Folder chosen in Settings. Checked first, because apps started from Finder or the Dock do not see
    /// `ANDROID_HOME` from the shell profile.
    static let customRootKey = "sdk.customRoot"

    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> AndroidSDK? {
        var paths: [String] = []
        if let custom = defaults.string(forKey: customRootKey) { paths.append(custom) }
        paths += ["ANDROID_HOME", "ANDROID_SDK_ROOT"].compactMap { environment[$0] }
        paths += [
            fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Android/sdk").path,  // Android Studio
            "/opt/homebrew/share/android-commandlinetools",  // brew install --cask android-commandlinetools
            "/usr/local/share/android-commandlinetools",
            "/opt/homebrew/share/android-sdk",
            "/usr/local/share/android-sdk",
        ]
        return paths
            .filter { !$0.isEmpty }
            .map { AndroidSDK(root: URL(filePath: $0)) }
            .first { isValid($0, fileManager: fileManager) }
    }

    static func isValid(_ sdk: AndroidSDK, fileManager: FileManager = .default) -> Bool {
        fileManager.isExecutableFile(atPath: sdk.adb.path)
    }
}
