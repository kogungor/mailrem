import EventKit
import Foundation

/// Reads Reminders lists and creates reminders through EventKit.
final class RemindersService {
    private let store = EKEventStore()
    private let folders = ListFolders()

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

    /// The same lists arranged as in the Reminders sidebar: in its order, with
    /// the lists of a folder together under the folder's name. Falls back to
    /// one section sorted by name when the arrangement cannot be read.
    func sections() -> [ListSection] {
        let all = lists()
        guard !all.isEmpty else { return [] }
        guard let sidebar = folders.sidebar() else {
            return [ListSection(folderIdentifier: nil, folderName: nil, lists: all)]
        }

        var remaining = Dictionary(all.map { ($0.calendarIdentifier.uppercased(), $0) },
                                   uniquingKeysWith: { first, _ in first })
        var sections: [ListSection] = []
        for entry in sidebar {
            guard let list = remaining.removeValue(forKey: entry.listIdentifier) else { continue }
            if let last = sections.last, last.folderIdentifier == entry.folderIdentifier {
                sections[sections.count - 1].lists.append(list)
            } else {
                sections.append(ListSection(folderIdentifier: entry.folderIdentifier,
                                            folderName: entry.folderName, lists: [list]))
            }
        }

        // Lists the sidebar did not mention still have to be reachable.
        let leftovers = all.filter { remaining[$0.calendarIdentifier.uppercased()] != nil }
        if !leftovers.isEmpty {
            sections.append(ListSection(folderIdentifier: nil, folderName: nil, lists: leftovers))
        }
        return sections
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

/// A run of lists in the menu: the lists of one folder, or lists outside any folder.
struct ListSection {
    let folderIdentifier: String?
    /// Nil for lists that are not in a folder.
    let folderName: String?
    var lists: [EKCalendar]
}

enum RemindersError: Error {
    case listNotFound
}
