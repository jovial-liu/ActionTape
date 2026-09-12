import ActionTapeCore
import SwiftUI

struct StepInspector: View {
    @EnvironmentObject private var state: StudioState

    var body: some View {
        Group {
            if let step = state.selectedStep {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("STEP INSPECTOR").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "slider.horizontal.3").foregroundStyle(.tertiary)
                        }
                        TextField("Step name", text: text(step, \.name))
                            .font(.title3.weight(.semibold)).textFieldStyle(.plain)
                            .accessibilityIdentifier("step-name")
                            .disabled(state.isBusy)
                        Picker("Action", selection: Binding(get: { step.action.kind }, set: { kind in
                            state.updateStep(step.id) { $0.action = defaultAction(kind, locator: stepLocator($0) ?? Locator()) }
                        })) {
                            ForEach(StepActionKind.allCases, id: \.self) { Text(displayName(for: $0)).tag($0) }
                        }.disabled(state.isBusy)
                        Divider()
                        actionFields(step).disabled(state.isBusy)
                        if let locator = stepLocator(step) {
                            locatorFields(step, locator).disabled(state.isBusy)
                            LocatorDiagnosticsView(step: step)
                        }
                        runtimeFields(step).disabled(state.isBusy)
                        stepControls(step).disabled(state.isBusy)
                        if let trace = state.traces.first(where: { $0.stepID == step.id }) {
                            InspectorSection(title: "Last result") {
                                Label(trace.status.rawValue.capitalized, systemImage: trace.status == .succeeded ? "checkmark.circle" : "info.circle")
                                Text("\(trace.duration.formatted(.number.precision(.fractionLength(2)))) s · \(trace.attempts) attempt(s)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let message = trace.message { Text(message).font(.caption).textSelection(.enabled) }
                            }
                        }
                    }
                    .padding(20)
                }
                .textFieldStyle(.roundedBorder)
            } else {
                ContentUnavailableView("Select a step", systemImage: "scope", description: Text("Add a step or select one to edit its action, locator, and timing."))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
    }

    @ViewBuilder private func actionFields(_ step: Step) -> some View {
        switch step.action {
        case .activateApp(let app):
            InspectorSection(title: "Target application") {
                field("Bundle ID", appText(step, app, \.bundleIdentifier))
                field("Name", appText(step, app, \.name))
                field("App path", appText(step, app, \.path))
                hint("Use a bundle ID for a portable target. The app must be installed or already running.")
            }
        case .setValue(_, let value):
            InspectorSection(title: "Text or variable") {
                TextField("Text, or {{variable}}", text: Binding(get: { value }, set: { value in
                    state.updateStep(step.id) { current in
                        guard let locator = stepLocator(current) else { return }
                        current.action = .setValue(locator: locator, value: value)
                    }
                }), axis: .vertical).lineLimit(3...8)
                    .accessibilityIdentifier("step-text-value")
                Button("Manage variables…") { state.variableEditorVisible = true }.buttonStyle(.link)
                hint("Literal text is saved in plaintext YAML. For private input, use a secret variable supplied only at replay. No keystrokes are recorded.")
            }
        case .hotKey(let hotKey):
            InspectorSection(title: "Keyboard shortcut") {
                field("Key", Binding(get: { hotKey.key }, set: { key in
                    state.updateStep(step.id) { $0.action = .hotKey(HotKey(key: key, modifiers: hotKey.modifiers)) }
                }))
                ForEach(KeyModifier.allCases, id: \.self) { modifier in
                    Toggle(modifier.rawValue.capitalized, isOn: Binding(get: { hotKey.modifiers.contains(modifier) }, set: { enabled in
                        var modifiers = hotKey.modifiers.filter { $0 != modifier }
                        if enabled { modifiers.append(modifier) }
                        state.updateStep(step.id) { $0.action = .hotKey(HotKey(key: hotKey.key, modifiers: modifiers)) }
                    }))
                }
                hint("Examples: n, return, escape, tab, left, f1. Shortcuts are added manually and sent only during replay.")
            }
        case .pause(let duration):
            InspectorSection(title: "Pause") {
                numberField("Seconds", Binding(get: { duration }, set: { duration in
                    state.updateStep(step.id) { $0.action = .pause(duration: duration) }
                }))
            }
        default:
            EmptyView()
        }
    }

    private func locatorFields(_ step: Step, _ locator: Locator) -> some View {
        InspectorSection(title: "Semantic locator") {
            field("Identifier", locatorText(step, locator, \.identifier))
            field("Role", locatorText(step, locator, \.role))
            field("Title", locatorText(step, locator, \.title))
            field("Description", locatorText(step, locator, \.elementDescription))
            hint("Use stable identifiers and roles from the target app. A role alone may match many controls. Ambiguous targets stop the replay.")
            DisclosureGroup("Ancestor selectors (\(locator.ancestry.count))") {
                VStack(spacing: 12) {
                    ForEach(Array(locator.ancestry.enumerated()), id: \.offset) { index, ancestor in
                        VStack(spacing: 7) {
                            HStack {
                                Text("Parent \(index + 1)").font(.caption.weight(.medium))
                                Spacer()
                                Button(role: .destructive) {
                                    changeLocator(step) { $0.ancestry.remove(at: index) }
                                } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                                    .help("Remove ancestor \(index + 1)")
                            }
                            field("Role", ancestorText(step, ancestor, index, \.role))
                            field("Title", ancestorText(step, ancestor, index, \.title))
                            field("Identifier", ancestorText(step, ancestor, index, \.identifier))
                        }
                    }
                    Button("Add ancestor") { changeLocator(step) { $0.ancestry.append(LocatorAncestor(role: "AXWindow")) } }
                }.padding(.top, 8)
            }
            if locator.fallback != nil {
                hint("This imported locator includes coordinates. Studio never enables coordinate fallback.")
                Button("Remove coordinates") { changeLocator(step) { $0.fallback = nil } }
            }
            Button("Copy locator JSON") { state.copyLocator(locator) }.buttonStyle(.link)
        }
    }

    private func runtimeFields(_ step: Step) -> some View {
        InspectorSection(title: "Runtime") {
            Toggle("Custom timeout", isOn: Binding(get: { step.timeout != nil }, set: { enabled in
                state.updateStep(step.id) { $0.timeout = enabled ? 10 : nil }
            }))
            if let timeout = step.timeout {
                numberField("Timeout (s)", Binding(get: { timeout }, set: { value in state.updateStep(step.id) { $0.timeout = value } }))
            } else { hint("Default timeout: 10 seconds per step.") }
            Stepper("Attempts: \(step.retry.maxAttempts)", value: Binding(get: { step.retry.maxAttempts }, set: { value in
                state.updateStep(step.id) { $0.retry.maxAttempts = value }
            }), in: 1...10)
            numberField("Retry delay (s)", Binding(get: { step.retry.delay }, set: { value in state.updateStep(step.id) { $0.retry.delay = value } }))
            if step.retry.maxAttempts > 1 { hint("A retry may repeat an action. Use a single attempt for sending, purchasing, or other non-repeatable operations.") }
        }
    }

    private func stepControls(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { state.runSingleStep(step) } label: { Label("Run this step", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
            hint("Uses the nearest preceding Activate app step. Earlier actions are not replayed.")
            HStack {
                Button { state.moveStep(step.id, offset: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(state.selectedWorkflow?.steps.first?.id == step.id).help("Move step up")
                Button { state.moveStep(step.id, offset: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(state.selectedWorkflow?.steps.last?.id == step.id).help("Move step down")
                Button("Duplicate") { state.duplicateStep(step.id) }
                Spacer()
                Button(role: .destructive) { state.deleteStep(step.id) } label: { Image(systemName: "trash") }.help("Delete step")
            }
        }
    }

    private func text(_ step: Step, _ key: WritableKeyPath<Step, String?>) -> Binding<String> {
        Binding(get: { step[keyPath: key] ?? "" }, set: { value in state.updateStep(step.id) { $0[keyPath: key] = value.isEmpty ? nil : value } })
    }
    private func appText(_ step: Step, _ app: AppTarget, _ key: WritableKeyPath<AppTarget, String?>) -> Binding<String> {
        Binding(get: { app[keyPath: key] ?? "" }, set: { value in
            state.updateStep(step.id) { current in
                guard case .activateApp(var target) = current.action else { return }
                target[keyPath: key] = value.isEmpty ? nil : value
                current.action = .activateApp(target)
            }
        })
    }
    private func locatorText(_ step: Step, _ locator: Locator, _ key: WritableKeyPath<Locator, String?>) -> Binding<String> {
        Binding(get: { locator[keyPath: key] ?? "" }, set: { value in changeLocator(step) { $0[keyPath: key] = value.isEmpty ? nil : value } })
    }
    private func ancestorText(_ step: Step, _ ancestor: LocatorAncestor, _ index: Int, _ key: WritableKeyPath<LocatorAncestor, String?>) -> Binding<String> {
        Binding(get: { ancestor[keyPath: key] ?? "" }, set: { value in
            changeLocator(step) { locator in
                guard locator.ancestry.indices.contains(index) else { return }
                locator.ancestry[index][keyPath: key] = value.isEmpty ? nil : value
            }
        })
    }
    private func changeLocator(_ step: Step, _ update: (inout Locator) -> Void) {
        state.updateStep(step.id) { current in
            guard var locator = stepLocator(current) else { return }
            update(&locator)
            switch current.action {
            case .press: current.action = .press(locator)
            case .waitFor: current.action = .waitFor(locator)
            case .assertExists: current.action = .assertExists(locator)
            case .setValue(_, let value): current.action = .setValue(locator: locator, value: value)
            default: break
            }
        }
    }
    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: binding).font(.callout.monospaced()).accessibilityLabel(label)
        }
    }
    private func numberField(_ label: String, _ binding: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            TextField(label, value: binding, format: .number).frame(width: 88).accessibilityLabel(label)
        }
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.7)
            VStack(alignment: .leading, spacing: 10) { content }
        }
    }
}
