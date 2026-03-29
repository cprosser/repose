import AppKit
import SwiftUI

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
class OverlayManager {
    private var overlayWindows: [NSPanel] = []
    private var keyMonitor: Any?

    func showBreakOverlay(timerManager: TimerManager) {
        dismissOverlay()

        for screen in NSScreen.screens {
            let isPrimary = screen == NSScreen.main
            let view = BreakOverlayView(timerManager: timerManager, isPrimary: isPrimary)

            let panel = KeyablePanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.contentView = NSHostingView(rootView: view)

            if isPrimary {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
            overlayWindows.append(panel)
        }

        // Install escape key handler to skip break
        let allowSkip = UserDefaults.standard.bool(forKey: "allowSkipBreak")
        if allowSkip {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape
                    timerManager.skipBreak()
                    return nil
                }
                return event
            }
        }
    }

    func dismissOverlay() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}
