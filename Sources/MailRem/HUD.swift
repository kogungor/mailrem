import AppKit

/// A short message that appears briefly near the bottom of the screen.
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.sizeToFit()

        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 13
        let size = NSSize(width: label.frame.width + horizontalPadding * 2,
                          height: label.frame.height + verticalPadding * 2)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        label.setFrameOrigin(NSPoint(x: horizontalPadding, y: verticalPadding))
        background.addSubview(label)
        panel.contentView = background

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                         y: frame.minY + frame.height * 0.18))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if self?.panel === panel { self?.panel = nil }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}
