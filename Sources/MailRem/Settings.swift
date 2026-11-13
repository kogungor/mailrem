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
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let autoInstallUpdates = "autoInstallUpdates"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.optionRightClick: true,
            Key.shortcut: true,
            Key.automaticUpdateChecks: true,
            Key.autoInstallUpdates: false,
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

    /// Look for a newer release on GitHub at launch and every few hours.
    static var automaticUpdateChecks: Bool {
        get { defaults.bool(forKey: Key.automaticUpdateChecks) }
        set { defaults.set(newValue, forKey: Key.automaticUpdateChecks) }
    }

    /// Install an update as soon as an automatic check finds one. Off by
    /// default and not shown in the menu; set it with `defaults write`.
    static var autoInstallUpdates: Bool {
        defaults.bool(forKey: Key.autoInstallUpdates)
    }
}
