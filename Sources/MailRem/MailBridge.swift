import AppKit
import Foundation

struct MailMessage {
    let subject: String
    let sender: String
    let messageID: String

    /// A link that opens this message in Mail.
    var link: String {
        let encoded = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
        return "message://%3C\(encoded)%3E"
    }
}

enum MailError: Error {
    case notRunning
    case notAuthorized
    case scriptFailed(String)
}

/// Talks to Apple Mail through Apple events.
final class MailBridge {
    static let bundleID = "com.apple.mail"

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID
    }

    func activate() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.activate(options: [])
    }

    /// Asks macOS for permission to control Mail, showing the system prompt if it
    /// has not been answered yet. Mail must be running. Safe to call repeatedly.
    func requestPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleID)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            DispatchQueue.main.async { completion(status == noErr) }
        }
    }

    /// The messages currently selected in Mail. Must be called on the main thread.
    func selectedMessages() throws -> [MailMessage] {
        guard isRunning else { throw MailError.notRunning }

        let source = """
        set out to {}
        tell application "Mail"
            repeat with m in (get selection)
                set end of out to {subject of m, sender of m, message id of m}
            end repeat
        end tell
        return out
        """
        guard let script = NSAppleScript(source: source) else {
            throw MailError.scriptFailed("Could not compile script")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo = errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -1743 { throw MailError.notAuthorized }
            throw MailError.scriptFailed(errorInfo[NSAppleScript.errorMessage] as? String ?? "Error \(number)")
        }

        var messages: [MailMessage] = []
        let count = result.numberOfItems
        guard count > 0 else { return messages }
        for index in 1...count {
            guard let item = result.atIndex(index) else { continue }
            messages.append(MailMessage(
                subject: item.atIndex(1)?.stringValue ?? "",
                sender: item.atIndex(2)?.stringValue ?? "",
                messageID: item.atIndex(3)?.stringValue ?? ""
            ))
        }
        return messages
    }
}
