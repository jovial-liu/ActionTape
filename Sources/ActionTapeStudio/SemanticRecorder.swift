import ActionTapeCore
import AppKit
import ApplicationServices
import SwiftUI

/// Explicit app allowlist; never observes keyboard events or reads AXValue.
/// AX handles stay on the main actor and captures are synchronous, so a stopped session
/// cannot finish an asynchronous capture later. Queued event deliveries also check a token.
@MainActor
final class SemanticRecorder {
    private let apps: [pid_t: NSRunningApplication]
    private let onStep: @MainActor (Step) -> Void
    private let onMessage: @MainActor (String) -> Void
    private let onStop: @MainActor () -> Void
    private var mouseMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var sessionID: UUID?
    private var lastPID: pid_t?
    private let hud = ActivityHUDController()

    init(apps: [NSRunningApplication], onStep: @escaping @MainActor (Step) -> Void,
         onMessage: @escaping @MainActor (String) -> Void, onStop: @escaping @MainActor () -> Void) {
        self.apps = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        self.onStep = onStep
        self.onMessage = onMessage
        self.onStop = onStop
    }

    @discardableResult
    func start() -> Bool {
        guard sessionID == nil, AXIsProcessTrusted(), !apps.isEmpty else {
            onMessage("Recording could not start. Check Accessibility access and choose a running app.")
            return false
        }
        let token = UUID()
        sessionID = token
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let point = event.cgEvent?.location else { return }
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == token else { return }
                self.captureClick(at: point)
            }
        }
        guard mouseMonitor != nil else {
            sessionID = nil
            onMessage("macOS did not allow a mouse event monitor. No recording was started.")
            return false
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == token else { return }
                self.recordActivation(pid)
            }
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { recordActivation(pid) }
        hud.show(title: "Recording Tape", subtitle: "\(apps.count) selected app\(apps.count == 1 ? "" : "s") · clicks only", onStop: onStop)
        return true
    }

    func stop() {
        sessionID = nil
        lastPID = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        hud.hide()
    }

    private func recordActivation(_ pid: pid_t) {
        guard sessionID != nil, let app = apps[pid], !app.isTerminated, lastPID != pid else { return }
        lastPID = pid
        onStep(Step(id: UUID().uuidString.lowercased(), name: "Activate \(app.localizedName ?? "app")",
                    action: .activateApp(AppTarget(bundleIdentifier: app.bundleIdentifier, name: app.localizedName))))
    }

    private func captureClick(at point: CGPoint) {
        guard sessionID != nil else { return }
        guard AXIsProcessTrusted() else {
            onMessage("Accessibility access was revoked. Recording stopped.")
            onStop()
            return
        }
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
        guard result == .success, let hit else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, let app = apps[pid], !app.isTerminated else { return }

        // Check the entire local parent chain before reading titles. Password fields are
        // commonly AXTextField with AXSecureTextField as their subrole, not their role.
        var chain = [hit]
        var cursor = hit
        for _ in 0..<8 {
            guard let parent = parent(of: cursor) else { break }
            chain.append(parent)
            cursor = parent
        }
        guard !chain.contains(where: { element in
            let role = string(element, kAXRoleAttribute)
            let subrole = string(element, kAXSubroleAttribute)
            return role == "AXSecureTextField" || subrole == "AXSecureTextField"
                || role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox"
        }) else {
            onMessage("Text fields are not recorded. Add a Set value step with a variable by hand.")
            return
        }

        // Record only actual AXPress support: AXRow or a focusable editor is not a press.
        // A text/image child of a button may use its nearest pressable ancestor.
        guard let element = chain.prefix(3).first(where: supportsPress) else {
            onMessage("Skipped a control without AXPress support. Add the appropriate supported action manually.")
            return
        }
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == pid else { return }
        let role = string(element, kAXRoleAttribute)
        let title = string(element, kAXTitleAttribute)
        let identifier = portableIdentifier(string(element, kAXIdentifierAttribute), role: role)
        let description = string(element, kAXDescriptionAttribute)
        var ancestry: [LocatorAncestor] = []
        cursor = element
        for _ in 0..<4 {
            guard let parent = parent(of: cursor) else { break }
            let ancestorRole = string(parent, kAXRoleAttribute)
            let ancestor = LocatorAncestor(
                identifier: portableIdentifier(string(parent, kAXIdentifierAttribute), role: ancestorRole),
                role: ancestorRole,
                title: string(parent, kAXTitleAttribute)
            )
            if ancestor.hasCriteria { ancestry.append(ancestor) }
            cursor = parent
        }
        let locator = Locator(identifier: identifier, role: role, title: title, description: description, ancestry: ancestry)
        guard locator.hasSemanticCriteria else { onMessage("Skipped a control with no accessible identity."); return }
        recordActivation(pid)
        let label = title ?? description ?? role ?? "control"
        onStep(Step(id: UUID().uuidString.lowercased(), name: "Press \(label)", action: .press(locator)))
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private func portableIdentifier(_ identifier: String?, role: String?) -> String? {
        guard let identifier, role != "AXWindow" else { return nil }
        // SwiftUI synthesizes window/type identities containing process-specific context
        // addresses and instance numbers. Keep window role/title for disambiguation, and
        // retain explicit control identifiers such as "prepare-button" across app restarts.
        guard !identifier.hasPrefix("SwiftUI."),
              !identifier.contains("(unknown context at $"),
              identifier.range(of: #"\$[0-9a-fA-F]{6,}"#, options: .regularExpression) == nil else {
            return nil
        }
        return identifier
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func supportsPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success else { return false }
        return (actions as? [String])?.contains(kAXPressAction as String) == true
    }
}

@MainActor
final class ActivityHUDController {
    private var panel: NSPanel?

    func show(title: String, subtitle: String, onStop: @escaping @MainActor () -> Void) {
        hide()
        let size = NSSize(width: 286, height: 58)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ActivityHUD(title: title, subtitle: subtitle, onStop: onStop))
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 18, y: frame.maxY - size.height - 14))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() { panel?.orderOut(nil); panel = nil }
}

private struct ActivityHUD: View {
    let title: String
    let subtitle: String
    let onStop: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(StudioTheme.accent).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            Button(action: onStop) { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderedProminent).tint(StudioTheme.accent)
                .accessibilityIdentifier("activity-stop")
        }
        .padding(12)
        .frame(width: 286, height: 58)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.10)) }
    }
}
