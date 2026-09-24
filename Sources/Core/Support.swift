import Foundation

/// Error with a message written for the user; shown as is in toasts and inspector banners.
struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Single-quoted for the device shell, so spaces, `&`, `;` and quotes stay literal.
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Parsers for `wm size` / `wm density`. The override wins over the physical value when set.
enum WindowManagerOutput {
    static func density(_ output: String) -> (physical: Int?, override: Int?) {
        (output.firstMatch(of: /Physical density: (\d+)/).flatMap { Int($0.1) },
         output.firstMatch(of: /Override density: (\d+)/).flatMap { Int($0.1) })
    }

    static func effectiveDensity(_ output: String) -> Int? {
        let density = density(output)
        return density.override ?? density.physical
    }

    static func effectiveSize(_ output: String) -> CGSize? {
        let match = output.firstMatch(of: /Override size: (\d+)x(\d+)/) ?? output.firstMatch(of: /Physical size: (\d+)x(\d+)/)
        guard let match, let width = Double(match.1), let height = Double(match.2) else { return nil }
        return CGSize(width: width, height: height)
    }
}
