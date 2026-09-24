import SwiftUI

/// Design tokens for the panel. Views use these instead of literal sizes, so spacing stays consistent.
enum Theme {
    static let panelSize = CGSize(width: 236, height: 700)
    static let panelCorner: CGFloat = 26
    static let panelPadding: CGFloat = 12
    /// Gap between the header, the device summary and the content.
    static let sectionSpacing: CGFloat = 8
    /// Height of the text or icon inside header controls; equal heights give equal buttons.
    static let headerControlHeight: CGFloat = 18
    /// Text width of empty-state messages: narrower than the panel, for short readable lines.
    static let messageWidth: CGFloat = 188
    static let buttonSize: CGFloat = 46
    static let cellWidth: CGFloat = 64
    static let columns = 3
    static let accent = Color.accentColor
    static let destructive = Color.red
}
