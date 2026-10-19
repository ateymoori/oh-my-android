import AppKit

extension NSPasteboard {
    /// Replaces the contents with plain text.
    func copy(_ text: String) {
        clearContents()
        setString(text, forType: .string)
    }
}
