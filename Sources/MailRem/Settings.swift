import Foundation
import os

let log = Logger(subsystem: "com.kogungor.mailrem", category: "app")

/// User preferences, stored in UserDefaults.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let optionRightClick = "optionRightClickEnabled"
        static let shortcut = "shortcutEnabled"
        static let welcomed = "didShowWelcome"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.optionRightClick: true,
            Key.shortcut: true,
        ])
    }

    /// Option + right-click on a message in Mail opens the list menu.
    static var optionRightClickEnabled: Bool {
        get { defaults.bool(forKey: Key.optionRightClick) }
        set { defaults.set(newValue, forKey: Key.optionRightClick) }
    }

    /// Control-Option-R in Mail opens the list menu.
    static var shortcutEnabled: Bool {
        get { defaults.bool(forKey: Key.shortcut) }
        set { defaults.set(newValue, forKey: Key.shortcut) }
    }

    static var didShowWelcome: Bool {
        get { defaults.bool(forKey: Key.welcomed) }
        set { defaults.set(newValue, forKey: Key.welcomed) }
    }
}
