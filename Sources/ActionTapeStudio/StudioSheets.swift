import ActionTapeCore
import AppKit
import SwiftUI

struct AddStepMenu: View {
    @EnvironmentObject private var state: StudioState
    var body: some View {
        Menu {
            ForEach(StepActionKind.allCases, id: \.self) { kind in
                Button(displayName(for: kind)) { state.addStep(kind) }
            }
        } label: { Label("Add step", systemImage: "plus") }
            .fixedSize().accessibilityIdentifier("add-step")
    }
}

struct RecordingSetupSheet: View {
    @EnvironmentObject private var state: StudioState
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Choose apps to record", systemImage: "record.circle")
                .font(.title2.weight(.semibold)).foregroundStyle(StudioTheme.accent)
            Text("Only the apps you select are observed. Switching among them records a cross-app tape. Unselected apps and ActionTape itself are ignored.")
                .foregroundStyle(.secondary)
            List(state.recordingApps, id: \.processIdentifier) { app in
                Toggle(isOn: Binding(get: { state.recordingAppPIDs.contains(app.processIdentifier) }, set: { selected in
                    if selected { state.recordingAppPIDs.insert(app.processIdentifier) }
                    else { state.recordingAppPIDs.remove(app.processIdentifier) }
                })) {
                    HStack(spacing: 10) {
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.localizedName ?? "App")
                            Text(app.bundleIdentifier ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.toggleStyle(.checkbox).padding(.vertical, 3)
            }
            .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 9))
            Label("Clicks only. No keystrokes, field contents, passwords, or screen images are recorded. Text and shortcuts can be added manually afterward.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Control labels and application/window names become part of your local YAML tape. Review them before sharing. Unsupported controls are skipped. Stop using the floating Stop button, even while another app is active.")
                .font(.caption).foregroundStyle(.secondary)
            if state.permission != .granted {
                HStack {
                    Text("Accessibility access is required.").font(.callout).foregroundStyle(StudioTheme.warning)
                    Spacer()
                    Button("Grant access…", action: state.requestAccessibilityAccess)
                }
            }
            HStack {
                Button("Refresh apps", action: state.refreshRecordingApps)
                Spacer()
                Button("Cancel") { state.recordingSetupVisible = false }.keyboardShortcut(.cancelAction)
                Button("Start recording", action: state.startRecording)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(state.recordingAppPIDs.isEmpty || state.permission != .granted)
            }
        }
        .padding(24).frame(width: 540)
        .onAppear { state.refreshPermission() }
    }
}

struct VariablesEditorSheet: View {
    @EnvironmentObject private var state: StudioState
    @State private var newName = ""
    private var variables: [String: WorkflowVariable] { state.selectedWorkflow?.variables ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tape variables", systemImage: "curlybraces").font(.title2.weight(.semibold))
            Text("Use {{name}} in text, locators, or app targets. Defaults are saved locally in plaintext. Secret inputs are requested at replay and are never saved by this editor.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 14) {
                    if variables.isEmpty { Text("No variables yet. Add one below.").foregroundStyle(.secondary).padding(30) }
                    ForEach(variables.keys.sorted(), id: \.self) { name in
                        if let variable = variables[name] {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("{{\(name)}}").font(.headline.monospaced())
                                    Spacer()
                                    Button(role: .destructive) { state.updateWorkflow { $0.variables.removeValue(forKey: name) } } label: { Image(systemName: "trash") }
                                        .help("Remove variable \(name)")
                                }
                                TextField("Description", text: Binding(get: { variable.description ?? "" }, set: { value in
                                    change(name) { $0.description = value.isEmpty ? nil : value }
                                }))
                                HStack {
                                    Toggle("Required", isOn: Binding(get: { variable.required }, set: { value in change(name) { $0.required = value } }))
                                    Toggle("Secret (run-time only)", isOn: Binding(get: { variable.secret }, set: { value in
                                        change(name) { $0.secret = value; if value { $0.defaultValue = nil } }
                                    }))
                                }
                                if variable.secret {
                                    Text("No default is stored. Enter the secret when replaying.").font(.caption).foregroundStyle(.secondary)
                                    if variable.defaultValue != nil {
                                        Button("Remove imported plaintext secret default") { change(name) { $0.defaultValue = nil } }
                                    }
                                } else {
                                    TextField("Default value (optional)", text: Binding(get: { variable.defaultValue ?? "" }, set: { value in
                                        change(name) { $0.defaultValue = value.isEmpty ? nil : value }
                                    }))
                                }
                            }
                            .padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }.frame(minHeight: 180, maxHeight: 360)
            HStack {
                TextField("New variable name", text: $newName)
                Button("Add variable") {
                    state.updateWorkflow { $0.variables[newName] = WorkflowVariable() }
                    newName = ""
                }.disabled(!validNewName)
            }
            if !newName.isEmpty && !validNewName {
                Text("Use a unique name beginning with a letter or underscore, followed by letters, digits, _, . or -.")
                    .font(.caption).foregroundStyle(StudioTheme.warning)
            }
            HStack { Spacer(); Button("Done") { state.variableEditorVisible = false }.keyboardShortcut(.defaultAction) }
        }
        .textFieldStyle(.roundedBorder).padding(24).frame(width: 580)
    }

    private var validNewName: Bool {
        newName.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil && variables[newName] == nil
    }
    private func change(_ name: String, _ update: (inout WorkflowVariable) -> Void) {
        state.updateWorkflow { workflow in
            guard var variable = workflow.variables[name] else { return }
            update(&variable)
            workflow.variables[name] = variable
        }
    }
}

struct RunInputsSheet: View {
    @EnvironmentObject private var state: StudioState
    private var variables: [String: WorkflowVariable] { state.pendingInputVariables }
    private var inputError: String? { state.pendingInputError }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(state.isPreparingInspection ? "Inspection inputs" : "Replay inputs", systemImage: state.isPreparingInspection ? "scope" : "play.circle")
                .font(.title2.weight(.semibold))
            Text(state.isPreparingInspection
                 ? "These values resolve only the target app and locator for this inspection. The target app will open or come forward; no controls are pressed and no text is entered."
                 : "Review the tape before continuing. These values apply to this replay only. Secret inputs are cleared from the form when replay starts or is cancelled.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(variables.keys.sorted(), id: \.self) { name in
                        if let variable = variables[name] {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(name + (variable.required ? " · required" : "")).font(.callout.weight(.semibold))
                                if let description = variable.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                                if variable.defaultValue != nil {
                                    Toggle("Use saved default", isOn: Binding(
                                        get: { state.runtimeValues[name] == nil },
                                        set: { useDefault in
                                            state.runtimeValues[name] = useDefault ? nil : ""
                                        }
                                    )).font(.caption)
                                }
                                if variable.secret {
                                    SecureField("Enter secret for this replay", text: valueBinding(name))
                                        .disabled(variable.defaultValue != nil && state.runtimeValues[name] == nil)
                                } else {
                                    TextField(variable.defaultValue.map { "Default: \($0)" } ?? "Value", text: valueBinding(name))
                                        .disabled(variable.defaultValue != nil && state.runtimeValues[name] == nil)
                                }
                            }
                        }
                    }
                }
            }.frame(maxHeight: 300)
            if let inputError { Text(inputError).font(.caption).foregroundStyle(StudioTheme.warning) }
            HStack {
                Spacer()
                Button("Cancel", action: state.cancelPendingRun).keyboardShortcut(.cancelAction)
                Button(state.isPreparingInspection ? "Inspect matches" : "Start replay", action: state.startPendingRun).buttonStyle(.borderedProminent)
                    .disabled(inputError != nil).keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder).padding(24).frame(width: 510)
    }

    private func valueBinding(_ name: String) -> Binding<String> {
        Binding(get: { state.runtimeValues[name] ?? "" }, set: { value in
            state.runtimeValues[name] = value
        })
    }
}
