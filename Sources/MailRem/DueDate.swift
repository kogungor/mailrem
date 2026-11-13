import Foundation

/// A due date that can be picked while sending a message to Reminders.
enum DueDate: CaseIterable {
    case today
    case tomorrow
    case nextWeek

    /// Title of the menu item.
    var title: String {
        switch self {
        case .today: return "Due Today"
        case .tomorrow: return "Due Tomorrow"
        case .nextWeek: return "Due Next Week"
        }
    }

    /// How the date reads at the end of a confirmation, as in "Added to Work, due tomorrow".
    var phrase: String {
        switch self {
        case .today: return "due today"
        case .tomorrow: return "due tomorrow"
        case .nextWeek: return "due on Monday"
        }
    }

    /// The day the reminder is due, without a time of day. Next week means the
    /// coming Monday; on a Monday that is the Monday after.
    func components(now: Date = Date(), calendar: Calendar = .current) -> DateComponents {
        let today = calendar.startOfDay(for: now)
        let day: Date
        switch self {
        case .today:
            day = today
        case .tomorrow:
            day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .nextWeek:
            let monday = DateComponents(weekday: 2)
            day = calendar.nextDate(after: today, matching: monday, matchingPolicy: .nextTime)
                ?? calendar.date(byAdding: .day, value: 7, to: today) ?? today
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.calendar = calendar
        return components
    }
}
