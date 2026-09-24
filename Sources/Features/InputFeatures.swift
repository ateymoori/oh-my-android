import Foundation

struct HideKeyboardFeature: ActionFeature {
    let id = "input.hideKeyboard"
    let title = "Hide keys"
    let symbol = "keyboard.chevron.compact.down"
    let category = FeatureCategory.navigation

    func perform(_ context: DeviceContext) async throws -> String? {
        try await context.shell("input keyevent 111")
        return nil
    }
}

struct TypeTextFeature: TextActionFeature {
    let id = "input.typeText"
    let title = "Type text"
    let symbol = "character.cursor.ibeam"
    let category = FeatureCategory.navigation
    let placeholder = "Text for the focused field"
    let submitTitle = "Type"

    func perform(_ text: String, _ context: DeviceContext) async throws -> String? {
        // `input text` reads %s as a space.
        try await context.shell("input text \(text.replacingOccurrences(of: " ", with: "%s").shellQuoted)")
        return nil
    }
}

struct BackFeature: ActionFeature {
    let id = "input.back"
    let title = "Back"
    let symbol = "arrow.uturn.backward"
    let category = FeatureCategory.navigation

    func perform(_ context: DeviceContext) async throws -> String? {
        try await context.shell("input keyevent 4")
        return nil
    }
}

struct HomeFeature: ActionFeature {
    let id = "input.home"
    let title = "Home"
    let symbol = "house.fill"
    let category = FeatureCategory.navigation

    func perform(_ context: DeviceContext) async throws -> String? {
        try await context.shell("input keyevent 3")
        return nil
    }
}

struct RecentsFeature: ActionFeature {
    let id = "input.recents"
    let title = "Recents"
    let symbol = "square.on.square"
    let category = FeatureCategory.navigation

    func perform(_ context: DeviceContext) async throws -> String? {
        try await context.shell("input keyevent 187")
        return nil
    }
}
