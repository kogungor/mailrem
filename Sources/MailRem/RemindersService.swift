import EventKit
import Foundation

/// Reads Reminders lists and creates reminders through EventKit.
final class RemindersService {
    private let store = EKEventStore()

    var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    var accessState: PermissionState {
        if hasAccess { return .granted }
        return EKEventStore.authorizationStatus(for: .reminder) == .notDetermined ? .notDetermined : .denied
    }

    /// Asks macOS for access to Reminders. Shows the system prompt the first time.
    func requestAccess(completion: @escaping (Bool) -> Void) {
        let done: (Bool, Error?) -> Void = { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders(completion: done)
        } else {
            store.requestAccess(to: .reminder, completion: done)
        }
    }

    /// Lists the user can add reminders to, sorted by name.
    func lists() -> [EKCalendar] {
        guard hasAccess else { return [] }
        return store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Creates one reminder per message in the given list, due on the given day
    /// if there is one. Returns how many were added.
    func add(_ messages: [MailMessage], toListWithIdentifier identifier: String, due: DueDate? = nil) throws -> Int {
        guard let list = store.calendar(withIdentifier: identifier) else {
            throw RemindersError.listNotFound
        }
        for message in messages {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = message.subject.isEmpty ? "(no subject)" : message.subject
            reminder.notes = "From: \(message.sender)\n\(message.link)"
            reminder.dueDateComponents = due?.components()
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return messages.count
    }
}

enum RemindersError: Error {
    case listNotFound
}
