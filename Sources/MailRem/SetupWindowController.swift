import AppKit

enum PermissionState: Equatable {
    case granted
    /// macOS has not asked the user yet.
    case notDetermined
    case denied
    /// Cannot be checked right now (Mail is not running).
    case unavailable
}

enum Permission: CaseIterable {
    case accessibility
    case reminders
    case mail

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .reminders: return "Reminders"
        case .mail: return "Mail"
        }
    }

    func detail(for state: PermissionState) -> String {
        switch self {
        case .accessibility:
            return "Lets MailRem notice Option + right-click in Mail and open its menu."
        case .reminders:
            return "Lets MailRem read your lists and add reminders to them."
        case .mail:
            if state == .unavailable {
                return "Open Mail so that MailRem can ask for permission to read the selected message."
            }
            return "Lets MailRem read the subject, sender and link of the selected message."
        }
    }

    func buttonTitle(for state: PermissionState) -> String? {
        switch state {
        case .granted: return nil
        case .notDetermined: return "Allow…"
        case .denied: return "Open Settings…"
        case .unavailable: return "Open Mail"
        }
    }
}

/// The setup window: one row per permission with its current state and a
/// button that asks for it or opens the right place in System Settings.
final class SetupWindowController: NSObject, NSWindowDelegate {
    /// The current state of a permission. Called on the main thread, except for
    /// `.mail`, which is asked on a background queue because it can block.
    private let stateProvider: (Permission) -> PermissionState
    /// Called on the main thread when the button of a row is clicked.
    private let actionHandler: (Permission, PermissionState) -> Void

    private var window: NSWindow?
    private var rows: [Permission: Row] = [:]
    private var subtitle: NSTextField?
    private var states: [Permission: PermissionState] = [:]
    private var timer: Timer?
    private var isCheckingMail = false

    private static let contentWidth: CGFloat = 520
    private static let padding: CGFloat = 24

    init(stateProvider: @escaping (Permission) -> PermissionState,
         actionHandler: @escaping (Permission, PermissionState) -> Void) {
        self.stateProvider = stateProvider
        self.actionHandler = actionHandler
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        let window = loadWindow()
        if states[.mail] == nil {
            // Fill in every row before the window first appears.
            states[.mail] = stateProvider(.mail)
        }
        refresh()
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    /// Reads the current state of every permission and updates the rows.
    func refresh() {
        var fresh = states
        fresh[.accessibility] = stateProvider(.accessibility)
        fresh[.reminders] = stateProvider(.reminders)
        apply(fresh)

        guard !isCheckingMail else { return }
        isCheckingMail = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let mailState = self.stateProvider(.mail)
            DispatchQueue.main.async {
                self.isCheckingMail = false
                var updated = self.states
                updated[.mail] = mailState
                self.apply(updated)
            }
        }
    }

    /// Shows the given states. A permission without a state keeps its last one.
    func apply(_ newStates: [Permission: PermissionState]) {
        guard newStates != states || rows.values.contains(where: { $0.shownState == nil }) else { return }
        states = newStates
        for (permission, row) in rows {
            row.show(states[permission] ?? .unavailable, for: permission)
        }
        let allGranted = Permission.allCases.allSatisfy { states[$0] == .granted }
        subtitle?.stringValue = allGranted
            ? "Everything is set up. MailRem is ready to use."
            : "MailRem needs three permissions to work. Allow each one below."
        resizeToFit()
    }

    // MARK: - Window

    @discardableResult
    func loadWindow() -> NSWindow {
        if let window = window { return window }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 400))
        let stack = NSStackView(views: [makeHeader(), makeRows(), makeFooter()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.padding),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.padding),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "MailRem Setup"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content
        self.window = window
        resizeToFit()
        return window
    }

    private func resizeToFit() {
        guard let window = window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.contentWidth, height: content.fittingSize.height)
        guard abs(window.contentLayoutRect.height - size.height) > 0.5 else { return }
        // Keep the title bar where it is while the height changes.
        let top = window.frame.maxY
        window.setContentSize(size)
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: "Welcome to MailRem")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString: "")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = Self.contentWidth - Self.padding * 2 - 64 - 14
        self.subtitle = subtitle

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4

        let header = NSStackView(views: [icon, text])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        return header
    }

    private func makeRows() -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0

        for (index, permission) in Permission.allCases.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                list.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
            let row = Row(width: Self.contentWidth - Self.padding * 2, target: self,
                          action: #selector(rowButtonClicked(_:)), tag: index)
            rows[permission] = row
            list.addArrangedSubview(row.view)
            row.view.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }

        let box = RoundedBox()
        list.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            list.topAnchor.constraint(equalTo: box.topAnchor),
            list.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    private func makeFooter() -> NSView {
        let hint = NSTextField(wrappingLabelWithString:
            "In Mail, hold Option and right-click a message, or press Control-Option-R, then pick a list.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = Self.contentWidth - Self.padding * 2 - 76 - 16

        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.keyEquivalent = "\r"
        done.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let footer = NSView()
        for subview in [hint, done] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            hint.topAnchor.constraint(equalTo: footer.topAnchor),
            hint.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
            done.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return footer
    }

    @objc private func rowButtonClicked(_ sender: NSButton) {
        let permission = Permission.allCases[sender.tag]
        actionHandler(permission, states[permission] ?? .unavailable)
        refresh()
    }

    @objc private func close() {
        window?.close()
    }
}

/// The rounded panel behind the rows.
private final class RoundedBox: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
    }
}

/// One permission in the setup window.
private final class Row {
    let view = NSView()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let button: NSButton
    private let width: CGFloat
    private(set) var shownState: PermissionState?

    private static let inset: CGFloat = 14
    private static let iconSize: CGFloat = 22
    private static let gap: CGFloat = 12

    /// - Parameter width: the width the row is laid out at, used to wrap the text.
    init(width: CGFloat, target: AnyObject, action: Selector, tag: Int) {
        self.width = width
        button = NSButton(title: "", target: target, action: action)
        button.tag = tag
        button.bezelStyle = .rounded

        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor

        for subview in [icon, title, detail, button] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.inset),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Self.iconSize),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Self.gap),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            detail.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.inset),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func show(_ state: PermissionState, for permission: Permission) {
        shownState = state
        title.stringValue = permission.title
        detail.stringValue = permission.detail(for: state)

        let symbol: String
        let color: NSColor
        let label: String
        switch state {
        case .granted:
            (symbol, color, label) = ("checkmark.circle.fill", .systemGreen, "Allowed")
        case .notDetermined, .denied:
            (symbol, color, label) = ("exclamationmark.circle.fill", .systemOrange, "Not allowed yet")
        case .unavailable:
            (symbol, color, label) = ("questionmark.circle.fill", .tertiaryLabelColor, "Not checked yet")
        }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        icon.contentTintColor = color

        var textWidth = width - Self.inset * 2 - Self.iconSize - Self.gap
        if let buttonTitle = permission.buttonTitle(for: state) {
            button.title = buttonTitle
            button.isHidden = false
            textWidth -= button.fittingSize.width + Self.gap
        } else {
            button.isHidden = true
        }
        // Wrap the description at the space that is left beside the button.
        detail.preferredMaxLayoutWidth = textWidth
    }
}
