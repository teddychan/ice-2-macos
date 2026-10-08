//
//  LocalizedErrorWrapper.swift
//  Ice
//

import DragonKit
import Foundation

/// `L(_:)` for a `LocalizedError` property, which the protocol requires to be nonisolated
/// while `L(_:)` is main-actor-isolated.
///
/// Every alert that shows these errors reads them on the main thread (`NSAlert(error:)` and
/// `LocalizedErrorWrapper` in a view), so that path follows the language chosen in Settings.
/// Read from anywhere else, the text falls back to the system language rather than trapping.
func localizedErrorText(_ key: String) -> String {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { L(key) }
    }
    return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// A type that wraps the information of any error inside a `LocalizedError`.
///
/// If the error used to initialize the box is also a `LocalizedError`, its
/// information is passed through to the box. Otherwise, a description of the
/// error is passed to the wrapper.
struct LocalizedErrorWrapper: LocalizedError {
    let errorDescription: String?
    let failureReason: String?
    let helpAnchor: String?
    let recoverySuggestion: String?

    /// Creates a wrapper with the given error.
    init(_ error: any Error) {
        if let error = error as? any LocalizedError {
            self.errorDescription = error.errorDescription
            self.failureReason = error.failureReason
            self.helpAnchor = error.helpAnchor
            self.recoverySuggestion = error.recoverySuggestion
        } else {
            self.errorDescription = error.localizedDescription
            self.failureReason = nil
            self.helpAnchor = nil
            self.recoverySuggestion = nil
        }
    }
}
