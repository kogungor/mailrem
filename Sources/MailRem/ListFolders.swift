import Foundation

/// Reads how lists are arranged in the Reminders sidebar: their order and the
/// folder each one is in.
///
/// EventKit knows nothing about folders. The only place that has them is
/// ReminderKit, the private framework behind the Reminders app, so it is
/// loaded and called by name at run time. Nothing here is guaranteed by
/// Apple: every step checks that the next one exists, and when anything is
/// missing `sidebar()` returns nil and callers show a plain list instead.
final class ListFolders {
    struct Entry {
        /// Matches `EKCalendar.calendarIdentifier`, in upper case.
        let listIdentifier: String
        let folderIdentifier: String?
        let folderName: String?
    }

    private let queue = DispatchQueue(label: "com.kogungor.mailrem.folders", qos: .userInitiated)
    private let lock = NSLock()
    private var cached: [Entry]?
    private var isReading = false

    /// The lists in sidebar order, or nil if the arrangement cannot be read.
    ///
    /// Reads off the main thread and waits only briefly, so a slow or stuck
    /// read can never hold up a menu; the previous result is used meanwhile.
    func sidebar(waitingUpTo timeout: TimeInterval = 0.3) -> [Entry]? {
        lock.lock()
        let shouldRead = !isReading
        if shouldRead { isReading = true }
        lock.unlock()

        if shouldRead {
            let done = DispatchSemaphore(value: 0)
            queue.async {
                let entries = autoreleasepool { Self.read() }
                self.lock.lock()
                self.cached = entries
                self.isReading = false
                self.lock.unlock()
                done.signal()
            }
            _ = done.wait(timeout: .now() + timeout)
        }

        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    // MARK: - ReminderKit

    private static let store: NSObject? = {
        let path = "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit"
        guard dlopen(path, RTLD_NOW) != nil,
              let type = NSClassFromString("REMStore") as? NSObject.Type else { return nil }
        return type.init()
    }()

    /// Walks accounts, then their lists and folders, then the lists in each
    /// folder. Anything that cannot be read is left out.
    private static func read() -> [Entry]? {
        guard let store, let accounts = fetch("fetchAccountsWithError:", from: store) else { return nil }

        var entries: [Entry] = []
        for account in accounts {
            for item in fetch("fetchListsWithError:", from: account) ?? [] {
                guard let storage = object("storage", of: item),
                      let identifier = identifier(of: storage) else { continue }

                guard flag("isGroup", of: storage) else {
                    entries.append(Entry(listIdentifier: identifier, folderIdentifier: nil, folderName: nil))
                    continue
                }
                guard let name = object("name", of: storage) as? NSString,
                      let context = object("sublistContext", of: item) else { continue }
                for child in fetch("fetchListsWithError:", from: context) ?? [] {
                    guard let childStorage = object("storage", of: child),
                          let childIdentifier = Self.identifier(of: childStorage) else { continue }
                    entries.append(Entry(listIdentifier: childIdentifier,
                                         folderIdentifier: identifier,
                                         folderName: name as String))
                }
            }
        }
        return entries.isEmpty ? nil : entries
    }

    private static func identifier(of storage: NSObject) -> String? {
        guard let objectID = object("objectID", of: storage),
              let uuid = object("uuid", of: objectID) as? NSUUID else { return nil }
        return uuid.uuidString.uppercased()
    }

    /// Calls a method of the form `-(NSArray *)name:(NSError **)error`.
    private static func fetch(_ name: String, from target: NSObject) -> [NSObject]? {
        let selector = NSSelectorFromString(name)
        guard target.responds(to: selector), let implementation = target.method(for: selector) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(target, selector, nil)?.takeUnretainedValue() as? [NSObject]
    }

    /// Calls a getter that returns an object.
    private static func object(_ name: String, of target: NSObject) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard target.responds(to: selector) else { return nil }
        return target.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    /// Calls a getter that returns a BOOL.
    private static func flag(_ name: String, of target: NSObject) -> Bool {
        let selector = NSSelectorFromString(name)
        guard target.responds(to: selector), let implementation = target.method(for: selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector) -> ObjCBool
        return unsafeBitCast(implementation, to: Function.self)(target, selector).boolValue
    }
}
