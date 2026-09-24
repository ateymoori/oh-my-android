import Foundation

/// Runs every `BatchReadable` read in one `adb shell` call and maps the outputs back by feature id.
struct BatchReader: Sendable {
    private static let separator = "@@OYAMA@@"

    func read(_ features: [any BatchReadable], _ context: DeviceContext) async -> [String: FeatureValue] {
        guard !features.isEmpty else { return [:] }
        let script = features.map(\.read.command).joined(separator: "; echo \(Self.separator); ")
        guard let output = try? await context.shell(script) else {
            return await readIndividually(features, context)
        }
        let sections = output.components(separatedBy: Self.separator)
        guard sections.count == features.count else {
            return await readIndividually(features, context)
        }
        var values: [String: FeatureValue] = [:]
        for (feature, section) in zip(features, sections) {
            if let value = feature.read.parse(section) { values[feature.id] = value }
        }
        return values
    }

    /// Fallback when one command breaks the batch (unexpected shell, exotic OEM).
    private func readIndividually(_ features: [any BatchReadable], _ context: DeviceContext) async -> [String: FeatureValue] {
        await withTaskGroup(of: (String, FeatureValue?).self) { group in
            for feature in features {
                group.addTask { (feature.id, try? await feature.readValue(context)) }
            }
            var values: [String: FeatureValue] = [:]
            for await (id, value) in group { if let value { values[id] = value } }
            return values
        }
    }
}
