import SwiftUI

/// Renders one feature as an icon button. The control type follows the feature protocol.
struct FeatureCell: View {
    let feature: any Feature
    let context: DeviceContext
    @Environment(AppModel.self) private var model
    @State private var showPopover = false
    @State private var confirmDestructive = false
    /// Per feature, so a tester can silence "Clear data" and still be asked before "Uninstall".
    @AppStorage private var skipConfirmation: Bool

    init(feature: any Feature, context: DeviceContext) {
        self.feature = feature
        self.context = context
        _skipConfirmation = AppStorage(wrappedValue: false, "confirm.skip.\(feature.id)")
    }

    private var store: FeatureStore { model.features }

    var body: some View {
        VStack(spacing: 4) {
            control
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(isOn ? Theme.accent : .secondary)
        }
        .frame(width: Theme.cellWidth)
        .help(feature.help)
        .disabled(store.isBusy(feature))
        .opacity(store.isBusy(feature) ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: store.isBusy(feature))
    }

    @ViewBuilder
    private var control: some View {
        switch feature {
        case let toggle as any ToggleFeature:
            iconButton { store.toggle(toggle, context) }
        case let action as any ActionFeature where action.isDestructive:
            iconButton {
                if skipConfirmation { store.perform(action, context) } else { confirmDestructive = true }
            }
            .confirmationDialog("\(action.title) of the app on screen?", isPresented: $confirmDestructive) {
                Button(action.title, role: .destructive) { store.perform(action, context) }
            } message: {
                Text("Acts on the foreground app of \(context.device.displayName). This cannot be undone.")
            }
            .dialogSuppressionToggle(isSuppressed: $skipConfirmation)
        case let action as any ActionFeature:
            iconButton { store.perform(action, context) }
        case let stepper as any StepperFeature:
            iconButton { showPopover.toggle() }
                .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                    StepperPopover(feature: stepper, context: context)
                }
        case let choice as any ChoiceFeature:
            Menu {
                ForEach(choice.options) { option in
                    Button {
                        store.choose(choice, option.id, context)
                    } label: {
                        if selectedOption == option.id { Label(option.menuTitle, systemImage: "checkmark") } else { Text(option.menuTitle) }
                    }
                }
            } label: {
                icon
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        case let text as any TextActionFeature:
            iconButton { showPopover.toggle() }
                .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                    TextActionPopover(feature: text, context: context, isPresented: $showPopover)
                }
        default:
            icon
        }
    }

    private func iconButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { icon }
            .buttonStyle(.plain)
    }

    private var icon: some View {
        Image(systemName: feature.symbol)
            .font(.system(size: 17, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(iconColor)
            .frame(width: Theme.buttonSize, height: Theme.buttonSize)
            .contentShape(Circle())
            .background { if isOn { Circle().fill(Theme.accent.gradient) } }
            .glassEffect(isOn ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: .circle)
            .animation(.easeOut(duration: 0.2), value: isOn)
            .accessibilityLabel(feature.title)
            .accessibilityValue(isOn ? "on" : caption == feature.title ? "" : caption)
    }

    private var iconColor: Color {
        if isOn { return .white }
        if let action = feature as? any ActionFeature, action.isDestructive { return Theme.destructive }
        return .primary
    }

    private var isOn: Bool {
        if case .toggle(true) = store.value(of: feature) { return true }
        return false
    }

    private var selectedOption: String? {
        if case .choice(let id) = store.value(of: feature) { return id }
        return nil
    }

    private var caption: String {
        switch store.value(of: feature) {
        case .number(let value):
            if let stepper = feature as? any StepperFeature { return stepper.label(for: value) }
        case .choice(let id?):
            if let choice = feature as? any ChoiceFeature, let option = choice.options.first(where: { $0.id == id }) {
                return option.title
            }
        default:
            break
        }
        return feature.title
    }
}

struct StepperPopover: View {
    let feature: any StepperFeature
    let context: DeviceContext
    @Environment(AppModel.self) private var model

    private var value: Double {
        if case .number(let value) = model.features.value(of: feature) { return value }
        return 1.0
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { model.features.step(feature, by: -1, context) } label: { Image(systemName: "minus") }
            Text(feature.label(for: value)).font(.title3.monospacedDigit()).frame(minWidth: 56)
            Button { model.features.step(feature, by: 1, context) } label: { Image(systemName: "plus") }
            Button("Reset") { model.features.setNumber(feature, 1.0, context) }.font(.caption)
        }
        .buttonStyle(.glass)
        .padding(12)
    }
}

struct TextActionPopover: View {
    let feature: any TextActionFeature
    let context: DeviceContext
    @Binding var isPresented: Bool
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(feature.placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($isFocused)
                .onSubmit(submit)
            Button(feature.submitTitle, action: submit).buttonStyle(.glassProminent)
        }
        .padding(12)
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !text.trimmed.isEmpty else { return }
        model.features.perform(feature, text: text, context)
        isPresented = false
    }
}
