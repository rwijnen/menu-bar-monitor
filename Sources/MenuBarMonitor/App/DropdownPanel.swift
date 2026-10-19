import AppKit
import SwiftUI

/// A borderless floating panel that drops down from the status item, like a
/// menu, with the system glass material on macOS 26 and later.
final class DropdownPanel: NSPanel {
    private static let cornerRadius: CGFloat = 12
    private let content: NSView

    init<Content: View>(rootView: Content) {
        content = NSHostingView(rootView: rootView)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient,
                              .ignoresCycle]
        contentView = makeBackground(around: content)
    }

    override var canBecomeKey: Bool { true }

    /// Places the panel just below `anchor` (a rect in screen coordinates),
    /// centred on it and kept on screen.
    func show(below anchor: NSRect) {
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8),
                    visible.maxX - size.width - 8)
        let y = anchor.minY - size.height - 6
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        makeKeyAndOrderFront(nil)
        invalidateShadow()
    }

    private func makeBackground(around content: NSView) -> NSView {
        // Swift 6.2 ships with the macOS 26 SDK, the first to have NSGlassEffectView.
        // Older toolchains still build the app, with the popover material below.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            return glass
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: Self.cornerRadius)
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }
}

private extension NSImage {
    /// A stretchable rounded-rect mask; visual effect views ignore layer corner radii.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
