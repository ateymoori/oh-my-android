import Foundation

/// Runs every `BatchReadable` read in one `adb shell` call and maps the outputs back by feature id.
struct BatchReader: Sendable {
    private static let separator = "@@OHMYANDROID@@"

    func read(_ features: [any BatchReadable], _ context: DeviceContext) async -> [String: FeatureValue] {
        await read(features.map { ($0.id, $0.read) }, context)
    }

    /// Same, for reads that are not features (for example the MCP server's device state).
    func read(_ reads: [(id: String, read: DeviceRead)], _ context: DeviceContext) async -> [String: FeatureValue] {
        guard !reads.isEmpty else { return [:] }
        let script = reads.map(\.read.command).joined(separator: "; echo \(Self.separator); ")
        guard let output = try? await context.shell(script) else {
            return await readIndividually(reads, context)
        }
        let sections = output.components(separatedBy: Self.separator)
        guard sections.count == reads.count else {
            return await readIndividually(reads, context)
        }
        var values: [String: FeatureValue] = [:]
        for ((id, read), section) in zip(reads, sections) {
            if let value = read.parse(section) { values[id] = value }
        }
        return values
    }

    /// Fallback when one command breaks the batch (unexpected shell, exotic OEM).
    private func readIndividually(_ reads: [(id: String, read: DeviceRead)], _ context: DeviceContext) async -> [String: FeatureValue] {
        await withTaskGroup(of: (String, FeatureValue?).self) { group in
            for (id, read) in reads {
                group.addTask { (id, (try? await context.shell(read.command)).flatMap(read.parse)) }
            }
            var values: [String: FeatureValue] = [:]
            for await (id, value) in group { if let value { values[id] = value } }
            return values
        }
    }
}
