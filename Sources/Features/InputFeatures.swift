import Foundation

/// One Android key press (`input keyevent`).
struct KeyEventFeature: ActionFeature {
    let id: String
    let title: String
    let symbol: String
    let keyCode: Int
    let category = FeatureCategory.navigation

    func perform(_ context: DeviceContext) async throws -> String? {
        try await context.shell("input keyevent \(keyCode)")
        return nil
    }
}

extension KeyEventFeature {
    static let back = KeyEventFeature(id: "input.back", title: "Back", symbol: "arrow.uturn.backward", keyCode: 4)
    static let home = KeyEventFeature(id: "input.home", title: "Home", symbol: "house.fill", keyCode: 3)
    static let recents = KeyEventFeature(id: "input.recents", title: "Recents", symbol: "square.on.square", keyCode: 187)
    /// Escape closes the soft keyboard.
    static let hideKeyboard = KeyEventFeature(id: "input.hideKeyboard", title: "Hide keys", symbol: "keyboard.chevron.compact.down", keyCode: 111)
}

struct TypeTextFeature: TextActionFeature {
    let id = "input.typeText"
    let title = "Type text"
    let symbol = "character.cursor.ibeam"
    let category = FeatureCategory.navigation
    let placeholder = "Text for the focused field"
    let submitTitle = "Type"

    func perform(_ text: String, _ context: DeviceContext) async throws -> String? {
        try await context.shell(try Self.command(text))
        return nil
    }

    /// `input text` takes ASCII on one line only, and reads %s as a space.
    static func command(_ text: String) throws -> String {
        guard text.allSatisfy({ $0.isASCII && !$0.isNewline }) else { throw AppError("adb can type ASCII only, on one line.") }
        return "input text \(text.replacingOccurrences(of: " ", with: "%s").shellQuoted)"
    }
}

extension SettingToggleFeature {
    static let softKeyboard = SettingToggleFeature(
        id: "input.softKeyboard", title: "Soft keys", symbol: "keyboard.fill", category: .navigation,
        namespace: "secure", key: "show_ime_with_hard_keyboard"
    )
}
