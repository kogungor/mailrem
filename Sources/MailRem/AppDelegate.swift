import AppKit
import Carbon.HIToolbox
import EventKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let reminders = RemindersService()
    private let mail = MailBridge()
    private let updater = Updater()

    private var statusItem: NSStatusItem!
    private var hotKey: HotKey!
    private var clickTap: ClickTap?
    private var accessibilityTimer: Timer?
    private var didRequestMailPermission = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        setUpStatusItem()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.showListMenuAtPointer()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontmostApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        showWelcomeIfNeeded()

        reminders.requestAccess { [weak self] granted in
            let listCount = self?.reminders.lists().count ?? 0
            log.notice("Reminders access granted: \(granted, privacy: .public), lists: \(listCount, privacy: .public)")
        }
        startClickTap(promptIfNeeded: true)
        frontmostApplicationChanged()
        requestMailPermissionIfPossible()

        updater.onChange = { [weak self] in self?.refreshStatusIcon() }
        updater.onInstallFailure = { [weak self] error in self?.updateFailed(error) }
        updater.startAutomaticChecks()
    }

    private func showWelcomeIfNeeded() {
        guard !Settings.didShowWelcome else { return }
        Settings.didShowWelcome = true

        let alert = NSAlert()
        alert.messageText = "Welcome to MailRem"
        alert.informativeText = """
        MailRem lives in your menu bar and sends the selected Mail message to a Reminders list.

        In Mail, hold Option and right-click a message, or press Control-Option-R, then pick a list.

        macOS will now ask for three permissions: Accessibility (for the Option + right-click menu), \
        Reminders, and permission to control Mail.
        """
        alert.addButton(withTitle: "Continue")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Permissions

    /// The Option + right-click menu needs the Accessibility permission. If it
    /// has not been granted yet, keep checking and start as soon as it is.
    private func startClickTap(promptIfNeeded: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), installClickTap() { return }

        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted(), self.installClickTap() {
                timer.invalidate()
                self.accessibilityTimer = nil
            }
        }
    }

    @discardableResult
    private func installClickTap() -> Bool {
        guard clickTap == nil else { return true }
        clickTap = ClickTap(
            shouldHandle: { [weak self] in
                guard let self = self else { return false }
                return Settings.optionRightClickEnabled && self.mail.isFrontmost
            },
            handler: { [weak self] point in
                self?.handleOptionRightClick(at: point)
            })
        log.notice("Click tap installed: \(self.clickTap != nil, privacy: .public)")
        return clickTap != nil
    }

    /// macOS only asks for permission to control Mail when Mail is first
    /// contacted, so do that as early as possible instead of on first use.
    private func requestMailPermissionIfPossible() {
        guard !didRequestMailPermission, mail.isRunning else { return }
        didRequestMailPermission = true
        mail.requestPermission { granted in
            log.notice("Mail automation permission granted: \(granted, privacy: .public)")
        }
    }

    @objc private func frontmostApplicationChanged() {
        if mail.isFrontmost {
            if Settings.shortcutEnabled { hotKey.register() } else { hotKey.unregister() }
            requestMailPermissionIfPossible()
        } else {
            hotKey.unregister()
        }
    }

    // MARK: - Sending

    private func handleOptionRightClick(at point: CGPoint) {
        // Select the message under the pointer first, then open the menu.
        ClickTap.leftClick(at: point)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showListMenuAtPointer()
        }
    }

    private func showListMenuAtPointer() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addListItems(to: menu, header: "Send to Reminders")

        // The menu only takes keyboard input and closes on an outside click
        // while this app is active, so activate it and hand control back after.
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        mail.activate()
    }

    private func addListItems(to menu: NSMenu, header: String) {
        let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        guard reminders.hasAccess else {
            let item = NSMenuItem(title: "Allow Access to Reminders…",
                                  action: #selector(openRemindersSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return
        }

        let lists = reminders.lists()
        guard !lists.isEmpty else {
            let item = NSMenuItem(title: "No Reminders Lists", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        for list in lists {
            let item = NSMenuItem(title: list.title, action: #selector(sendToList(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = list.calendarIdentifier
            item.image = Self.dot(color: list.color)
            menu.addItem(item)
        }
    }

    private static func dot(color: NSColor?) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            (color ?? .secondaryLabelColor).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }

    @objc private func sendToList(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        let listName = sender.title

        do {
            let messages = try mail.selectedMessages()
            guard !messages.isEmpty else {
                HUD.shared.show("No message selected in Mail")
                return
            }
            let count = try reminders.add(messages, toListWithIdentifier: identifier)
            log.notice("Added \(count, privacy: .public) reminder(s)")
            HUD.shared.show(count == 1 ? "Added to \(listName)" : "\(count) messages added to \(listName)")
        } catch MailError.notRunning {
            HUD.shared.show("Mail is not running")
        } catch MailError.notAuthorized {
            HUD.shared.show("MailRem is not allowed to control Mail")
            openAutomationSettings()
        } catch {
            log.error("Could not add reminder: \(String(describing: error), privacy: .public)")
            HUD.shared.show("Could not add the reminder")
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "envelope.badge", accessibilityDescription: "MailRem")
        image?.isTemplate = true
        statusItem.button?.image = image
        refreshStatusIcon()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The menu bar icon turns orange while an update is waiting.
    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        if let update = updater.available {
            button.contentTintColor = .systemOrange
            button.toolTip = "MailRem \(update.version) is available"
        } else {
            button.contentTintColor = nil
            button.toolTip = "MailRem"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()

        if let update = updater.available {
            let item = makeItem(updater.isInstalling ? "Updating…" : "Update to MailRem \(update.version)",
                                #selector(installUpdate))
            item.isEnabled = !updater.isInstalling
            item.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(item)
            menu.addItem(.separator())
        }

        addListItems(to: menu, header: "Send Selected Message To")
        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            menu.addItem(makeItem("Allow Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        let rightClick = makeItem("Option + Right-Click Menu in Mail", #selector(toggleOptionRightClick))
        rightClick.state = Settings.optionRightClickEnabled ? .on : .off
        menu.addItem(rightClick)

        let shortcut = makeItem("Control-Option-R in Mail", #selector(toggleShortcut))
        shortcut.state = Settings.shortcutEnabled ? .on : .off
        menu.addItem(shortcut)

        let login = makeItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        if updater.available == nil {
            menu.addItem(makeItem("Check for Updates…", #selector(checkForUpdates)))
        }
        let automaticChecks = makeItem("Check for Updates Automatically", #selector(toggleAutomaticUpdateChecks))
        automaticChecks.state = Settings.automaticUpdateChecks ? .on : .off
        menu.addItem(automaticChecks)

        menu.addItem(.separator())
        menu.addItem(makeItem("About MailRem", #selector(showAbout)))
        menu.addItem(makeItem("Quit MailRem", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Menu actions

    @objc private func toggleOptionRightClick() {
        Settings.optionRightClickEnabled.toggle()
        if Settings.optionRightClickEnabled { startClickTap(promptIfNeeded: true) }
    }

    @objc private func toggleShortcut() {
        Settings.shortcutEnabled.toggle()
        frontmostApplicationChanged()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Launch at login failed: \(String(describing: error), privacy: .public)")
            HUD.shared.show("Could not change Launch at Login")
        }
    }

    @objc private func installUpdate() {
        updater.install()
    }

    @objc private func checkForUpdates() {
        updater.check { result in
            switch result {
            case .success(let update?):
                HUD.shared.show("MailRem \(update.version) is available")
            case .success(nil):
                HUD.shared.show("MailRem is up to date")
            case .failure:
                HUD.shared.show("Could not check for updates")
            }
        }
    }

    @objc private func toggleAutomaticUpdateChecks() {
        Settings.automaticUpdateChecks.toggle()
        updater.startAutomaticChecks()
    }

    private func updateFailed(_ error: Error) {
        if case UpdateError.notWritable = error {
            // The app cannot replace itself here (for example it was opened
            // straight from the disk image), so send the user to the download.
            HUD.shared.show("Opening the download page…")
            NSWorkspace.shared.open(Updater.latestReleasePage)
        } else {
            HUD.shared.show("Could not install the update")
        }
    }

    @objc private func openAccessibilitySettings() {
        openSettings("Privacy_Accessibility")
    }

    @objc private func openRemindersSettings() {
        openSettings("Privacy_Reminders")
    }

    private func openAutomationSettings() {
        openSettings("Privacy_Automation")
    }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 8

        let primary: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        var secondary = primary
        secondary[.font] = NSFont.systemFont(ofSize: 11)
        secondary[.foregroundColor] = NSColor.secondaryLabelColor
        var link = secondary
        link[.link] = URL(string: "https://github.com/kogungor/mailrem")

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "Send the message you have selected in Mail to a Reminders list.\n",
            attributes: primary))
        credits.append(NSAttributedString(
            string: "In Mail, Option + right-click a message or press Control-Option-R, then pick a list.\n",
            attributes: secondary))
        credits.append(NSAttributedString(string: "github.com/kogungor/mailrem", attributes: link))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .version: "", // hide the build number; the marketing version is enough
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
