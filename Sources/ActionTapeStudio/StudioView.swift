import AppKit
import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var state: StudioState

    var body: some View {
        VStack(spacing: 0) {
            StudioToolbar()
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if let message = state.bannerMessage {
                StatusBanner(message: message, onDismiss: state.dismissBanner)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            HSplitView {
                TapeSidebar()
                    .frame(minWidth: 210, idealWidth: 238, maxWidth: 290)
                WorkflowTimeline()
                    .frame(minWidth: 430, idealWidth: 560, maxWidth: .infinity)
                StepInspector()
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 430)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(StudioTheme.accent)
        .sheet(isPresented: $state.recordingSetupVisible) { RecordingSetupSheet().environmentObject(state) }
        .sheet(isPresented: $state.variableEditorVisible) { VariablesEditorSheet().environmentObject(state) }
        .sheet(isPresented: $state.runInputsVisible, onDismiss: state.cancelPendingRun) { RunInputsSheet().environmentObject(state) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in state.stopCurrentActivity() }
        .onDisappear { state.stopCurrentActivity() }
    }
}

private struct StudioToolbar: View {
    @EnvironmentObject private var state: StudioState

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("ActionTape")
                    .font(.headline.weight(.semibold))
                Text("Replay by meaning, not pixels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            PermissionPill(permission: state.permission) {
                state.requestAccessibilityAccess()
            }

            Divider().frame(height: 24)

            Button {
                state.toggleRecording()
            } label: {
                Label(state.isRecording ? "Stop" : "Record", systemImage: state.isRecording ? "stop.fill" : "record.circle")
                    .frame(minWidth: 74)
            }
            .buttonStyle(RecordButtonStyle(isRecording: state.isRecording))
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(state.isBusy && !state.isRecording)

            Button {
                state.isRunning ? state.stopCurrentActivity() : state.runSelectedWorkflow()
            } label: {
                Label(state.activity == .stopping ? "Stopping…" : state.isRunning ? "Stop Run" : "Replay", systemImage: state.isRunning ? "stop.fill" : "play.fill")
                    .frame(minWidth: 76)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.selectedDocument == nil || state.isRecording || state.inspectionRunning || state.activity == .stopping)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var appIcon: NSImage {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "recordingtape", accessibilityDescription: nil) ?? NSImage()
        }
        return image
    }
}

private struct PermissionPill: View {
    let permission: AccessibilityPermission
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(permission == .granted ? StudioTheme.success : StudioTheme.warning)
                    .frame(width: 7, height: 7)
                Text(permission == .granted ? "Access ready" : "Grant access")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(permission == .granted ? "Accessibility permission is enabled" : "ActionTape needs Accessibility access to inspect and replay controls")
    }
}

private struct RecordButtonStyle: ButtonStyle {
    let isRecording: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(isRecording ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? AnyShapeStyle(StudioTheme.accent) : AnyShapeStyle(.primary.opacity(0.07)))
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct StatusBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(StudioTheme.violet)
            Text(message)
                .font(.callout)
                .lineLimit(5)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(StudioTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
