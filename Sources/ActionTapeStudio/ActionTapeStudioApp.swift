import SwiftUI

@main
struct ActionTapeStudioApp: App {
    @StateObject private var state = StudioState()

    var body: some Scene {
        Window("ActionTape", id: "studio") {
            StudioView()
                .environmentObject(state)
                .frame(minWidth: 1_080, minHeight: 680)
                .task { await state.bootstrap() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1_260, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tape") { state.createWorkflow() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(state.isBusy)
                Button("Import Tape…") { state.importWorkflow() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(state.isBusy)
                Button("Save Tape") { state.saveSelectedWorkflow() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(state.selectedDocument == nil || state.isBusy)
                Button("Export Tape…") { state.exportSelectedWorkflow() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(state.selectedDocument == nil || state.isBusy)
            }

            CommandMenu("Run") {
                Button(state.isRecording ? "Stop Recording" : "Record") {
                    state.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.isBusy && !state.isRecording)

                Button("Replay Tape") { state.runSelectedWorkflow() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(state.selectedDocument == nil || state.isBusy)
                Button("Stop") { state.stopCurrentActivity() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!state.isBusy)
            }
        }
    }
}
