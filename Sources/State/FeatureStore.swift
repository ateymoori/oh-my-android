import Foundation
import Observation
import SwiftUI

struct Toast: Equatable {
    enum Kind { case info, error }
    let kind: Kind
    let message: String
}

/// Holds feature values for the selected device and performs feature actions.
@MainActor
@Observable
final class FeatureStore {
    private(set) var values: [String: FeatureValue] = [:]
    private(set) var busy: Set<String> = []
    private(set) var toast: Toast?

    private var toastTask: Task<Void, Never>?
    private var lastFullRefresh: Date = .distantPast
    private var activeRefreshes = 0
    /// Device the values belong to. Reads that finish after a device switch are dropped.
    private var valuesSerial: String?
    private let batchReader = BatchReader()
    /// The device can change on its own (Android settings, Studio). adb offers no change events for
    /// settings, so the panel re-reads when the pointer returns to it: one batched shell call, no timer.
    private static let panelStaleAfter: TimeInterval = 5

    func value(of feature: any Feature) -> FeatureValue? { values[feature.id] }
    func isBusy(_ feature: any Feature) -> Bool { busy.contains(feature.id) }

    /// Re-reads everything if the last full read is older than `panelStaleAfter`. Cheap to call often.
    func refreshIfStale(_ context: DeviceContext) async {
        guard Date().timeIntervalSince(lastFullRefresh) > Self.panelStaleAfter, activeRefreshes == 0 else { return }
        await refreshAll(context)
    }

    /// Full read. Cancelling the calling task (device switch) discards its result.
    func refreshAll(_ context: DeviceContext) async {
        let serial = context.device.serial
        if valuesSerial != serial {
            values = [:]  // never show, or toggle from, another device's state
            busy = []
            valuesSerial = serial
        }
        activeRefreshes += 1
        let fresh = await readAll(context)
        activeRefreshes -= 1
        guard !Task.isCancelled, valuesSerial == serial else { return }
        if fresh != values { values = fresh }
        lastFullRefresh = Date()
    }

    /// One shell round-trip for every batchable feature; console-backed features read concurrently beside it.
    private func readAll(_ context: DeviceContext) async -> [String: FeatureValue] {
        let features = FeatureCatalog.all.filter { $0.supports(context.device) }
        let batchable = features.compactMap { $0 as? any BatchReadable }
        let others = features.filter { !($0 is any BatchReadable) }

        async let batched = batchReader.read(batchable, context)
        async let individual: [String: FeatureValue] = withTaskGroup(of: (String, FeatureValue?).self) { group in
            for feature in others {
                group.addTask { (feature.id, await Self.read(feature, context)) }
            }
            var values: [String: FeatureValue] = [:]
            for await (id, value) in group { if let value { values[id] = value } }
            return values
        }
        return await batched.merging(individual) { _, new in new }
    }

    func refresh(_ feature: any Feature, _ context: DeviceContext) async {
        guard let value = await Self.read(feature, context), valuesSerial == context.device.serial else { return }
        if values[feature.id] != value { values[feature.id] = value }
    }

    func toggle(_ feature: any ToggleFeature, _ context: DeviceContext) {
        guard !isBusy(feature) else { return }
        let current = if case .toggle(let on) = values[feature.id] { on } else { false }
        values[feature.id] = .toggle(!current)
        run(feature, context) {
            try await feature.setOn(!current, context)
            return nil
        }
    }

    func step(_ feature: any StepperFeature, by delta: Int, _ context: DeviceContext) {
        let current = if case .number(let value) = values[feature.id] { value } else { 1.0 }
        let index = feature.steps.firstIndex { $0 >= current - 0.0001 } ?? 0
        let target = min(max(index + delta, 0), feature.steps.count - 1)
        setNumber(feature, feature.steps[target], context)
    }

    func setNumber(_ feature: any StepperFeature, _ value: Double, _ context: DeviceContext) {
        guard !isBusy(feature) else { return }
        values[feature.id] = .number(value)
        run(feature, context) {
            try await feature.setValue(value, context)
            return nil
        }
    }

    func choose(_ feature: any ChoiceFeature, _ optionID: String, _ context: DeviceContext) {
        guard !isBusy(feature) else { return }
        values[feature.id] = .choice(optionID)
        run(feature, context) {
            try await feature.select(optionID, context)
            return nil
        }
    }

    func perform(_ feature: any ActionFeature, _ context: DeviceContext) {
        run(feature, context, refreshAfter: false) { try await feature.perform(context) }
    }

    func perform(_ feature: any TextActionFeature, text: String, _ context: DeviceContext) {
        run(feature, context, refreshAfter: false) { try await feature.perform(text, context) }
    }

    /// Dropped APK: same path as the Install icon, so the icon shows busy and the result becomes a toast.
    func install(_ url: URL, _ context: DeviceContext) {
        run(InstallAPKFeature(), context, refreshAfter: false) { try await APKInstaller.install(url, context) }
    }

    func show(_ toast: Toast) {
        self.toast = toast
        AccessibilityNotification.Announcement(toast.message).post()
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(toast.kind == .error ? 5 : 2.5))
            if !Task.isCancelled { self.toast = nil }
        }
    }

    // MARK: - Private

    private func run(
        _ feature: any Feature,
        _ context: DeviceContext,
        refreshAfter: Bool = true,
        _ work: @escaping @Sendable () async throws -> String?
    ) {
        // A second tap while the first command runs would race it on the device.
        guard busy.insert(feature.id).inserted else { return }
        Task {
            defer { busy.remove(feature.id) }
            do {
                if let message = try await work() { show(.init(kind: .info, message: message)) }
            } catch {
                show(.init(kind: .error, message: error.localizedDescription))
            }
            if refreshAfter { await refresh(feature, context) }
        }
    }

    private static func read(_ feature: any Feature, _ context: DeviceContext) async -> FeatureValue? {
        switch feature {
        case let batchable as any BatchReadable:
            return try? await batchable.readValue(context)
        case let toggle as any ToggleFeature:
            return (try? await toggle.isOn(context)).map { .toggle($0) }
        case let stepper as any StepperFeature:
            return (try? await stepper.value(context)).map { .number($0) }
        case let choice as any ChoiceFeature:
            guard let selection = try? await choice.selection(context) else { return nil }
            return .choice(selection)
        default:
            return nil
        }
    }
}
