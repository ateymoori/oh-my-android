import Foundation

/// Where captures land. Desktop keeps them visible; the folder is created on first write.
enum CaptureLocation {
    static let directory = URL.desktopDirectory.appending(path: "Android Captures")

    /// Fixed, locale-independent stamp, same style as macOS screenshots: "Screenshot 2026-09-24 at 10.15.43.png".
    private static let stampFormat = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
        timeZone: .current, calendar: Calendar(identifier: .gregorian)
    )

    /// New file URL in the Captures folder; never overwrites an earlier capture from the same second.
    static func file(_ prefix: String, _ ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = "\(prefix) \(Date().formatted(stampFormat))"
        var url = directory.appending(path: "\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appending(path: "\(base) \(counter).\(ext)")
            counter += 1
        }
        return url
    }
}

struct ScreenshotFeature: ActionFeature {
    let id = "capture.screenshot"
    let title = "Screenshot"
    let symbol = "camera.fill"
    let category = FeatureCategory.capture
    let help = "Saves a PNG to Desktop/Android Captures and copies it to the clipboard."

    func perform(_ context: DeviceContext) async throws -> String? {
        let data = try await context.adb.execOut(context.device, "screencap -p")
        let url = try CaptureLocation.file("Screenshot", "png")
        try data.write(to: url)
        await context.host.copyImage(data)
        return "Saved and copied: \(url.lastPathComponent)"
    }
}

/// Screen recording through the emulator console (VP9 WebM, audio included).
/// The console splits arguments on spaces, so it records to a temporary path and the file moves to the
/// Captures folder on stop. State lives here because the console has no status query.
struct ScreenRecordFeature: ToggleFeature {
    let id = "capture.record"
    let title = "Record"
    let symbol = "record.circle"
    let category = FeatureCategory.capture
    let requiresEmulator = true
    let help = "Records screen + audio to WebM (max 3 min) in Desktop/Android Captures. Quality: see the Quality icon."

    private let recorder: RecorderState

    init(recorder: RecorderState = RecorderState()) { self.recorder = recorder }

    func isOn(_ context: DeviceContext) async throws -> Bool {
        await recorder.temporaryFile(for: context.device.serial) != nil
    }

    func setOn(_ on: Bool, _ context: DeviceContext) async throws {
        if on {
            let quality = RecordingQuality.current
            let resolution = try await Self.displayResolution(context)
            let temporary = FileManager.default.temporaryDirectory.appending(path: "oyama-\(context.device.serial)-\(UUID().uuidString).webm")
            try await context.adb.console(context.device, ["screenrecord", "start"] + quality.arguments(for: resolution) + [temporary.path])
            await recorder.start(context.device.serial, file: temporary)
        } else {
            try await context.console("screenrecord", "stop")
            guard let temporary = await recorder.stop(context.device.serial) else { return }
            try await Self.moveWhenFinished(temporary, to: try CaptureLocation.file("Recording", "webm"))
        }
    }

    /// Current display size, honouring a `wm size` override.
    private static func displayResolution(_ context: DeviceContext) async throws -> CGSize? {
        WindowManagerOutput.effectiveSize(try await context.shell("wm size"))
    }

    /// The emulator finalises the container shortly after `stop`; wait for the file to settle before moving it.
    private static func moveWhenFinished(_ source: URL, to destination: URL) async throws {
        var lastSize = -1
        for _ in 0..<40 {
            let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
            if size > 0, size == lastSize { break }
            lastSize = size
            try await Task.sleep(for: .milliseconds(250))
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

/// Two presets are enough: small files for sharing, or everything the emulator can give.
enum RecordingQuality: String, CaseIterable, Sendable {
    case balanced, best

    static let defaultsKey = "recording.quality"

    static var current: RecordingQuality {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(RecordingQuality.init) ?? .balanced }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .best: "Best"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "720p, 24 fps, 3 Mbps — small files, good quality"
        case .best: "Native resolution, 60 fps, 16 Mbps"
        }
    }

    /// Console flags. Balanced scales the short side to 720 px and keeps the aspect ratio (even dimensions).
    func arguments(for resolution: CGSize?) -> [String] {
        switch self {
        case .best:
            return ["--fps", "60", "--bit-rate", "16M", "--time-limit", "180"]
        case .balanced:
            var arguments = ["--fps", "24", "--bit-rate", "3M", "--time-limit", "180"]
            if let resolution, min(resolution.width, resolution.height) > 720 {
                let scale = 720 / min(resolution.width, resolution.height)
                let even = { (value: Double) in Int((value * scale / 2).rounded()) * 2 }
                arguments += ["--size", "\(even(resolution.width))x\(even(resolution.height))"]
            }
            return arguments
        }
    }
}

struct RecordingQualityFeature: ChoiceFeature {
    let id = "capture.quality"
    let title = "Quality"
    let symbol = "slider.horizontal.3"
    let category = FeatureCategory.capture
    let requiresEmulator = true
    let help = "Recording quality. Balanced: 720p, 24 fps, 3 Mbps. Best: native, 60 fps, 16 Mbps."
    let options = RecordingQuality.allCases.map { FeatureOption(id: $0.rawValue, title: $0.title, detail: $0.detail) }

    func selection(_ context: DeviceContext) async throws -> String? { RecordingQuality.current.rawValue }

    func select(_ optionID: String, _ context: DeviceContext) async throws {
        guard let quality = RecordingQuality(rawValue: optionID) else { return }
        RecordingQuality.current = quality
    }
}

actor RecorderState {
    private var files: [String: URL] = [:]
    func temporaryFile(for serial: String) -> URL? { files[serial] }
    func start(_ serial: String, file: URL) { files[serial] = file }
    func stop(_ serial: String) -> URL? { files.removeValue(forKey: serial) }
}

struct RevealCapturesFeature: ActionFeature {
    let id = "capture.reveal"
    let title = "Captures"
    let symbol = "folder.fill"
    let category = FeatureCategory.capture

    func perform(_ context: DeviceContext) async throws -> String? {
        try FileManager.default.createDirectory(at: CaptureLocation.directory, withIntermediateDirectories: true)
        await context.host.reveal(CaptureLocation.directory)
        return nil
    }
}
