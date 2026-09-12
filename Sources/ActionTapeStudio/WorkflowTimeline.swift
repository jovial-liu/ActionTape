import ActionTapeCore
import SwiftUI

struct WorkflowTimeline: View {
    @EnvironmentObject private var state: StudioState

    var body: some View {
        Group {
            if let document = state.selectedDocument {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        WorkflowHeader(workflow: document.workflow)
                            .padding(.horizontal, 24)
                            .padding(.top, 23)
                            .padding(.bottom, 19)

                        Divider().padding(.horizontal, 24)

                        HStack {
                            AddStepMenu()
                            Button { state.variableEditorVisible = true } label: {
                                Label("Variables", systemImage: "curlybraces")
                            }
                            Spacer()
                            Label(document.isSaved ? "Saved on this Mac" : "Unsaved changes", systemImage: document.isSaved ? "checkmark.circle" : "exclamationmark.circle")
                                .font(.caption).foregroundStyle(document.isSaved ? .secondary : StudioTheme.warning)
                        }
                        .padding(.horizontal, 24).padding(.top, 14)
                        .disabled(state.isBusy)

                        if !state.validationIssues.isEmpty {
                            DisclosureGroup("\(state.validationIssues.count) item(s) to review before replay") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(state.validationIssues) { issue in
                                        Text("\(issue.path): \(issue.message)").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }.padding(.top, 6)
                            }
                            .font(.caption.weight(.medium)).foregroundStyle(StudioTheme.warning)
                            .padding(12).background(StudioTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 24).padding(.top, 12)
                        }

                        if document.workflow.steps.isEmpty {
                            EmptyTimeline()
                                .padding(28)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(document.workflow.steps.enumerated()), id: \.element.id) { index, step in
                                    StepTimelineRow(
                                        step: step,
                                        index: index,
                                        isLast: index == document.workflow.steps.count - 1,
                                        isSelected: state.selectedStepID == step.id,
                                        trace: state.traces.first { $0.stepID == step.id },
                                        isRunning: isRunning(step)
                                    ) {
                                        state.selectedStepID = step.id
                                    }
                                    .contextMenu {
                                        Button("Move up") { state.moveStep(step.id, offset: -1) }.disabled(index == 0 || state.isBusy)
                                        Button("Move down") { state.moveStep(step.id, offset: 1) }.disabled(index == document.workflow.steps.count - 1 || state.isBusy)
                                        Button("Duplicate") { state.duplicateStep(step.id) }.disabled(state.isBusy)
                                        Button("Delete", role: .destructive) { state.deleteStep(step.id) }.disabled(state.isBusy)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.38))
            } else {
                ContentUnavailableView("No tape selected", systemImage: "recordingtape", description: Text("Create a tape to begin recording a workflow."))
            }
        }
    }

    private func isRunning(_ step: Step) -> Bool {
        if case .running(let stepID) = state.activity { return stepID == step.id }
        return false
    }
}

private struct WorkflowHeader: View {
    @EnvironmentObject private var state: StudioState
    let workflow: Workflow

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    TextField("Tape name", text: Binding(get: { workflow.name }, set: { name in
                        state.updateWorkflow { $0.name = name }
                    }))
                        .font(.title2.weight(.semibold)).textFieldStyle(.plain)
                        .disabled(state.isBusy).accessibilityIdentifier("tape-name")
                    Text("v\(workflow.formatVersion)")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.10), in: Capsule())
                }
                TextField("Add a description…", text: Binding(get: { workflow.description ?? "" }, set: { description in
                    state.updateWorkflow { $0.description = description.isEmpty ? nil : description }
                }), axis: .vertical)
                    .font(.callout).foregroundStyle(.secondary).textFieldStyle(.plain)
                    .disabled(state.isBusy).lineLimit(2...5)
                HStack(spacing: 14) {
                    Label("\(workflow.steps.count) steps", systemImage: "list.number")
                    Label("\(semanticCount) semantic", systemImage: "scope")
                    if fallbackCount > 0 {
                        Label("\(fallbackCount) fragile", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(StudioTheme.warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Save", action: state.saveSelectedWorkflow)
                Button("Export YAML…", action: state.exportSelectedWorkflow)
                Button("Duplicate", action: state.duplicateSelectedWorkflow)
                Divider()
                Button("Delete", role: .destructive, action: state.deleteSelectedWorkflow)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(state.isBusy)
        }
    }

    private var locators: [Locator] {
        workflow.steps.compactMap { step in
            switch step.action {
            case .press(let locator), .waitFor(let locator), .assertExists(let locator): locator
            case .setValue(let locator, _): locator
            default: nil
            }
        }
    }
    private var semanticCount: Int { locators.filter(\.hasSemanticCriteria).count }
    private var fallbackCount: Int { locators.filter { $0.fallback != nil }.count }
}

private struct StepTimelineRow: View {
    let step: Step
    let index: Int
    let isLast: Bool
    let isSelected: Bool
    let trace: StepTrace?
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                VStack(spacing: 0) {
                    StepGlyph(kind: step.action.kind, trace: trace, isRunning: isRunning)
                    if !isLast {
                        Rectangle()
                            .fill(.secondary.opacity(0.22))
                            .frame(width: 1, height: 37)
                    }
                }
                .frame(width: 30)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(step.name ?? displayName(for: step.action.kind))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        LocatorQualityBadge(step: step)
                        Spacer()
                        Text(String(format: "%02d", index + 1))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    Text(stepSummary(step))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let trace {
                        HStack(spacing: 6) {
                            Text(trace.status.rawValue.capitalized)
                            Text("•")
                            Text("\(trace.duration.formatted(.number.precision(.fractionLength(2)))) s")
                            if trace.attempts > 1 { Text("• \(trace.attempts) attempts") }
                        }
                        .font(.caption2)
                        .foregroundStyle(trace.status == .failed ? StudioTheme.failure : trace.status == .succeeded ? StudioTheme.success : .secondary)
                    }
                }
                .padding(.vertical, 9)
            }
            .padding(.horizontal, 10)
            .background(isSelected ? StudioTheme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(index + 1), \(step.name ?? displayName(for: step.action.kind))")
    }
}

private struct StepGlyph: View {
    let kind: StepActionKind
    let trace: StepTrace?
    let isRunning: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 28, height: 28)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(foreground)
        }
        .overlay {
            if isRunning {
                Circle().stroke(StudioTheme.warm, lineWidth: 2).padding(-3)
            }
        }
    }

    private var symbol: String {
        if trace?.status == .succeeded { return "checkmark" }
        if trace?.status == .failed { return "xmark" }
        return switch kind {
        case .activateApp: "app.dashed"
        case .press: "cursorarrow.click"
        case .setValue: "character.cursor.ibeam"
        case .hotKey: "command"
        case .waitFor: "hourglass"
        case .assertExists: "checkmark.shield"
        case .pause: "pause"
        }
    }

    private var background: Color {
        if trace?.status == .succeeded { return StudioTheme.success }
        if trace?.status == .failed { return StudioTheme.failure }
        return isRunning ? StudioTheme.warm.opacity(0.22) : StudioTheme.violet.opacity(0.13)
    }

    private var foreground: Color {
        trace == nil ? (isRunning ? StudioTheme.warning : StudioTheme.violet) : .white
    }
}

private struct LocatorQualityBadge: View {
    let step: Step

    var body: some View {
        if let locator {
            Text(locator.hasSemanticCriteria ? "SEMANTIC" : "NEEDS TARGET")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(!locator.hasSemanticCriteria ? StudioTheme.warning : StudioTheme.success)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background((!locator.hasSemanticCriteria ? StudioTheme.warning : StudioTheme.success).opacity(0.10), in: Capsule())
        }
    }

    private var locator: Locator? {
        switch step.action {
        case .press(let locator), .waitFor(let locator), .assertExists(let locator): locator
        case .setValue(let locator, _): locator
        default: nil
        }
    }
}

private struct EmptyTimeline: View {
    @EnvironmentObject private var state: StudioState

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle().fill(StudioTheme.accent.opacity(0.10)).frame(width: 72, height: 72)
                Image(systemName: "record.circle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(StudioTheme.accent)
            }
            Text("This tape is ready to record")
                .font(.headline)
            Text("Choose which apps to record, or build a tape by hand. Recording captures supported semantic clicks; add text and keyboard shortcuts manually.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Start Recording", action: state.toggleRecording)
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
            AddStepMenu().disabled(state.isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }
}

func displayName(for kind: StepActionKind) -> String {
    switch kind {
    case .activateApp: "Activate app"
    case .press: "Press control"
    case .setValue: "Set value"
    case .hotKey: "Keyboard shortcut"
    case .waitFor: "Wait for control"
    case .assertExists: "Assert control exists"
    case .pause: "Pause"
    }
}

private func stepSummary(_ step: Step) -> String {
    switch step.action {
    case .activateApp(let app):
        return app.name ?? app.bundleIdentifier ?? app.path ?? "Unknown app"
    case .press(let locator):
        return locatorSummary(locator)
    case .setValue(let locator, let value):
        let safeValue = value.contains("{{") ? value : "••••••"
        return "\(locatorSummary(locator)) ← \(safeValue)"
    case .hotKey(let hotKey):
        return (hotKey.modifiers.map(\.rawValue) + [hotKey.key]).joined(separator: " + ")
    case .waitFor(let locator), .assertExists(let locator):
        return locatorSummary(locator)
    case .pause(let duration):
        return "\(duration.formatted()) seconds"
    }
}

private func locatorSummary(_ locator: Locator) -> String {
    [locator.role, locator.title, locator.identifier]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
}
