//
//  Logging.swift
//  Ice
//

import OSLog

extension Logger {
    /// The app-wide logger.
    static let `default` = Logger(category: "Ice")

    /// A logger for one area of the app, under the app's subsystem.
    init(category: String) {
        self.init(subsystem: Constants.bundleIdentifier, category: category)
    }
}
