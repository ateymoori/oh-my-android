import Foundation

struct LocationPresetFeature: ChoiceFeature {
    let id = "location.preset"
    let title = "City"
    let symbol = "mappin.and.ellipse"
    let category = FeatureCategory.simulate
    let requiresEmulator = true

    private struct Place { let id: String; let title: String; let lat: Double; let lon: Double }

    private let places: [Place] = [
        .init(id: "stockholm", title: "Stockholm", lat: 59.3293, lon: 18.0686),
        .init(id: "gothenburg", title: "Göteborg", lat: 57.7089, lon: 11.9746),
        .init(id: "malmo", title: "Malmö", lat: 55.6050, lon: 13.0038),
        .init(id: "berlin", title: "Berlin", lat: 52.5200, lon: 13.4050),
        .init(id: "london", title: "London", lat: 51.5072, lon: -0.1276),
        .init(id: "newyork", title: "New York", lat: 40.7128, lon: -74.0060),
        .init(id: "sanfrancisco", title: "San Francisco", lat: 37.7749, lon: -122.4194),
        .init(id: "tokyo", title: "Tokyo", lat: 35.6895, lon: 139.6917),
        .init(id: "tehran", title: "Tehran", lat: 35.6892, lon: 51.3890),
        .init(id: "dubai", title: "Dubai", lat: 25.2048, lon: 55.2708),
        .init(id: "sydney", title: "Sydney", lat: -33.8688, lon: 151.2093),
    ]

    var options: [FeatureOption] { places.map { .init(id: $0.id, title: $0.title) } }

    func selection(_ context: DeviceContext) async throws -> String? { nil }

    func select(_ optionID: String, _ context: DeviceContext) async throws {
        guard let place = places.first(where: { $0.id == optionID }) else { return }
        try await context.console("geo", "fix", String(place.lon), String(place.lat))
    }
}

struct CustomLocationFeature: TextActionFeature {
    let id = "location.custom"
    let title = "Lat, lon"
    let symbol = "location.fill"
    let category = FeatureCategory.simulate
    let requiresEmulator = true
    let placeholder = "59.3293, 18.0686"
    let submitTitle = "Set"

    func perform(_ text: String, _ context: DeviceContext) async throws -> String? {
        let numbers = text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double(String($0).trimmed) }
        guard numbers.count == 2 else { throw AppError("Use: latitude, longitude") }
        try await context.console("geo", "fix", String(numbers[1]), String(numbers[0]))
        return nil
    }
}
