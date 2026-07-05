import SwiftUI
import Observation
import os

/// A single place to surface the outcome of an action instead of failing
/// silently. Shows a transient banner in the hub panel (rendered by `HubPanel`),
/// mirrors it as a Dynamic Island flash when that module is on, and always logs.
@MainActor
@Observable
final class Notifier {
    static let shared = Notifier()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var isError: Bool
    }

    private(set) var toast: Toast?
    private var clearTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.hubos.Prism", category: "Notifier")

    private init() {}

    /// Reports a successful action (green banner, auto-dismisses quickly).
    func success(_ message: String) { post(message, isError: false, detail: nil) }

    /// Reports a failed action (red banner, lingers a bit longer). `detail` is
    /// logged but not shown, to keep the banner short.
    func error(_ message: String, detail: String? = nil) { post(message, isError: true, detail: detail) }

    private func post(_ message: String, isError: Bool, detail: String?) {
        let full = detail.map { "\(message) — \($0)" } ?? message
        if isError { log.error("\(full, privacy: .public)") } else { log.info("\(full, privacy: .public)") }

        toast = Toast(message: message, isError: isError)
        NotchController.shared.showFlash(
            symbol: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            text: message,
            tint: isError ? Theme.red : Theme.green)

        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 6 : 3.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismiss() { clearTask?.cancel(); toast = nil }
}
