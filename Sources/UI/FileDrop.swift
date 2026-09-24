import Foundation
import UniformTypeIdentifiers

/// Resolves the first dropped file URL with an accepted extension and hands it over on the main actor.
enum FileDrop {
    static let imageExtensions = ["png", "jpg", "jpeg"]

    static func load(_ providers: [NSItemProvider], extensions: [String], perform: @escaping @MainActor (URL) -> Void) -> Bool {
        let type = UTType.fileURL.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else { return false }
        provider.loadItem(forTypeIdentifier: type) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil),
                  extensions.contains(url.pathExtension.lowercased()) else { return }
            Task { @MainActor in perform(url) }
        }
        return true
    }
}
