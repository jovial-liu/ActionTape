import ActionTapeCore
import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WorkflowDocument: Identifiable, Equatable {
    let id: UUID
    var workflow: Workflow
    var fileURL: URL?
    var modifiedAt: Date
    var isSaved: Bool

    init(id: UUID = UUID(), workflow: Workflow, fileURL: URL? = nil, modifiedAt: Date = .now) {
        self.id = id
        self.workflow = workflow
        self.fileURL = fileURL
        self.modifiedAt = modifiedAt
        isSaved = fileURL != nil
    }
}

@MainActor
final class StudioState: ObservableObject {
    enum Activity: Equatable {
        case idle
        case recording
        case running(stepID: String?)
        case stopping
    }

    @Published var documents: [WorkflowDocument] = []
    @Published var selectedDocumentID: UUID?
    @Published var selectedStepID: String?
    @Published var activity: Activity = .idle
    @Published var traces: [StepTrace] = []
    @Published var permission = AccessibilityPermission.current
    @Published var bannerMessage: String?
    @Published var recordingSetupVisible = false
    @Published var variableEditorVisible = false
    @Published var runInputsVisible = false
    @Published var recordingApps: [NSRunningApplication] = []
    @Published var recordingAppPIDs: Set<pid_t> = []
    @Published var runtimeValues: [String: String] = [:]
    @Published private(set) var inspectionRunning = false
    @Published private(set) var inspectionStopRequested = false
    @Published private(set) var inspectionResult: LocatorInspectionResult?

    private var hasBootstrapped = false
    private let store = WorkflowFileStore()
    private var recorder: SemanticRecorder?
    private var recordingDocumentID: UUID?
    private var recordingSessionID: UUID?
    private var runTask: Task<Void, Never>?
    private var runSessionID: UUID?
    private var pendingRun: Workflow?
    private var pendingInspection: LocatorInspectionRequest?
    private var inspectionTask: Task<Void, Never>?
    private let runHUD = ActivityHUDController()

    var selectedDocument: WorkflowDocument? { documents.first { $0.id == selectedDocumentID } }
    var selectedWorkflow: Workflow? { selectedDocument?.workflow }
    var selectedStep: Step? { selectedWorkflow?.steps.first { $0.id == selectedStepID } }
    var isRecording: Bool { activity == .recording }
    var isRunning: Bool {
        if case .running = activity { return true }
        return activity == .stopping
    }
    var isBusy: Bool { activity != .idle || inspectionRunning }
    var isPreparingInspection: Bool { pendingInspection != nil }
    var pendingInputVariables: [String: WorkflowVariable] { pendingInspection?.variables ?? pendingRun?.variables ?? [:] }
    var pendingInputError: String? {
        var resolved: ResolvedVariables?
        do {
            let values = try VariableResolver.resolve(declarations: pendingInputVariables, overrides: runtimeValues)
            resolved = values
            if let inspection = pendingInspection {
                _ = try VariableResolver.interpolate(inspection.app, using: values.values)
                _ = try VariableResolver.interpolate(inspection.locator, using: values.values)
            } else if let workflow = pendingRun {
                for step in workflow.steps { _ = try VariableResolver.interpolate(step.action, using: values.values) }
            }
            return nil
        } catch { return resolved?.redacting(error.localizedDescription) ?? error.localizedDescription }
    }
    var validationIssues: [ValidationIssue] {
        selectedWorkflow.map { WorkflowSchemaValidator().validate($0) } ?? []
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        refreshPermission()
        do {
            let loaded = try store.loadAll()
            documents = loaded.documents
            if !loaded.failures.isEmpty {
                bannerMessage = "Some local tapes could not be opened; their files were preserved: " + loaded.failures.joined(separator: "; ")
            }
        } catch { bannerMessage = "Could not open the local tape library: \(error.localizedDescription)" }
        if documents.isEmpty {
            documents = [WorkflowDocument(workflow: DemoContent.welcome)]
            saveDocument(documents[0].id)
        }
        selectDocument(documents.first?.id)
    }

    func selectDocument(_ id: UUID?) {
        guard !isBusy, selectedDocumentID != id else { return }
        selectedDocumentID = id
        selectedStepID = selectedDocument?.workflow.steps.first?.id
        traces = []
        inspectionResult = nil
        runtimeValues = [:]
    }

    func createWorkflow() {
        guard !isBusy else { return }
        let document = WorkflowDocument(workflow: DemoContent.blank)
        documents.insert(document, at: 0)
        selectDocument(document.id)
        saveDocument(document.id)
    }

    func duplicateSelectedWorkflow() {
        guard !isBusy, var workflow = selectedWorkflow else { return }
        workflow.name += " Copy"
        let copy = WorkflowDocument(workflow: workflow)
        documents.insert(copy, at: 0)
        selectDocument(copy.id)
        saveDocument(copy.id)
    }

    func deleteSelectedWorkflow() {
        guard !isBusy, let id = selectedDocumentID,
              let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Move ‘\(documents[index].workflow.name)’ to Trash?"
        alert.informativeText = "The saved tape can be recovered from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if let url = documents[index].fileURL { try store.remove(url) }
            documents.remove(at: index)
            selectDocument(documents.first?.id)
            bannerMessage = "Tape moved to Trash."
        } catch { bannerMessage = "Could not move the tape to Trash; it remains in the library: \(error.localizedDescription)" }
    }

    func updateWorkflow(_ update: (inout Workflow) -> Void) {
        guard !isBusy, let id = selectedDocumentID,
              let index = documents.firstIndex(where: { $0.id == id }) else { return }
        update(&documents[index].workflow)
        documents[index].modifiedAt = .now
        documents[index].isSaved = false
        traces = []
        inspectionResult = nil
        saveDocument(id)
    }

    func updateStep(_ id: String, _ update: (inout Step) -> Void) {
        updateWorkflow { workflow in
            guard let index = workflow.steps.firstIndex(where: { $0.id == id }) else { return }
            update(&workflow.steps[index])
        }
    }

    func addStep(_ kind: StepActionKind) {
        let step = Step(id: UUID().uuidString.lowercased(), name: displayName(for: kind), action: defaultAction(kind))
        updateWorkflow { workflow in
            let insertion = workflow.steps.firstIndex { $0.id == selectedStepID }.map { $0 + 1 } ?? workflow.steps.count
            workflow.steps.insert(step, at: insertion)
        }
        if !isBusy { selectedStepID = step.id }
    }

    func deleteStep(_ id: String) {
        guard !isBusy else { return }
        let index = selectedWorkflow?.steps.firstIndex { $0.id == id } ?? 0
        updateWorkflow { $0.steps.removeAll { $0.id == id } }
        if selectedStepID == id {
            let steps = selectedWorkflow?.steps ?? []
            selectedStepID = steps.isEmpty ? nil : steps[min(index, steps.count - 1)].id
        }
    }

    func moveStep(_ id: String, offset: Int) {
        updateWorkflow { workflow in
            guard let index = workflow.steps.firstIndex(where: { $0.id == id }),
                  workflow.steps.indices.contains(index + offset) else { return }
            workflow.steps.swapAt(index, index + offset)
        }
    }

    func duplicateStep(_ id: String) {
        guard !isBusy, var step = selectedWorkflow?.steps.first(where: { $0.id == id }) else { return }
        step.id = UUID().uuidString.lowercased()
        updateWorkflow { workflow in
            let index = workflow.steps.firstIndex { $0.id == id } ?? workflow.steps.count - 1
            workflow.steps.insert(step, at: index + 1)
        }
        selectedStepID = step.id
    }

    func toggleRecording() {
        if isRecording { stopCurrentActivity(); return }
        guard !isBusy else { return }
        if selectedDocument == nil { createWorkflow() }
        refreshRecordingApps()
        recordingSetupVisible = true
    }

    func refreshRecordingApps() {
        recordingApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        recordingAppPIDs.formIntersection(Set(recordingApps.map(\.processIdentifier)))
    }

    func startRecording() {
        guard !isBusy, let documentID = selectedDocumentID else { return }
        refreshPermission()
        guard permission == .granted else { requestAccessibilityAccess(); return }
        let apps = recordingApps.filter { recordingAppPIDs.contains($0.processIdentifier) && !$0.isTerminated }
        guard !apps.isEmpty else { bannerMessage = "Choose at least one running app to record."; return }
        let sessionID = UUID()
        recordingSessionID = sessionID
        recordingDocumentID = documentID
        activity = .recording
        let recorder = SemanticRecorder(
            apps: apps,
            onStep: { [weak self] step in self?.appendRecordedStep(step, sessionID: sessionID) },
            onMessage: { [weak self] message in
                guard self?.recordingSessionID == sessionID else { return }
                self?.bannerMessage = message
            },
            onStop: { [weak self] in self?.stopCurrentActivity() }
        )
        self.recorder = recorder
        guard recorder.start() else {
            self.recorder = nil
            recordingSessionID = nil
            recordingDocumentID = nil
            activity = .idle
            return
        }
        recordingSetupVisible = false
        bannerMessage = "Recording only \(apps.compactMap(\.localizedName).joined(separator: ", ")). Text, keystrokes, and password fields are not recorded. Use the floating Stop button when finished."
    }

    func runSelectedWorkflow() {
        guard let workflow = selectedWorkflow else { return }
        prepareRun(workflow)
    }

    func runSingleStep(_ step: Step) {
        guard let selectedWorkflow,
              let index = selectedWorkflow.steps.firstIndex(where: { $0.id == step.id }) else { return }
        var steps: [Step] = []
        if step.action.kind != .activateApp && step.action.kind != .pause {
            guard let activation = selectedWorkflow.steps.prefix(index).last(where: { $0.action.kind == .activateApp }) else {
                bannerMessage = "Add an Activate app step before this step so replay has an explicit target."
                return
            }
            steps.append(activation)
        }
        steps.append(step)
        prepareRun(Workflow(name: selectedWorkflow.name, variables: selectedWorkflow.variables, steps: steps))
    }

    func inspectMatches(for step: Step) {
        guard !isBusy, let documentID = selectedDocumentID, let workflow = selectedWorkflow,
              let index = workflow.steps.firstIndex(where: { $0.id == step.id }),
              let locator = stepLocator(step) else { return }
        guard let activation = workflow.steps.prefix(index).last(where: { $0.action.kind == .activateApp }),
              case .activateApp(let app) = activation.action else {
            bannerMessage = "Add an Activate app step before this control. Inspection needs an explicit target."
            return
        }
        guard locator.hasSemanticCriteria else {
            bannerMessage = "Add a semantic identifier, role, title, or description before inspecting matches."
            return
        }
        let strings = [app.bundleIdentifier, app.name, app.path, locator.identifier, locator.role,
                       locator.title, locator.elementDescription] + locator.ancestry.flatMap { [$0.identifier, $0.role, $0.title] }
        let referenced = Set(strings.compactMap { $0 }.flatMap(VariableResolver.placeholderNames))
        let variables = workflow.variables.filter { referenced.contains($0.key) }
        let inspectionWorkflow = Workflow(name: "Inspect locator", variables: variables, steps: [
            Step(id: "inspect-app", action: .activateApp(app)),
            Step(id: "inspect-control", action: .assertExists(locator))
        ])
        do { try WorkflowSchemaValidator().validateOrThrow(inspectionWorkflow) }
        catch { bannerMessage = "Fix this locator before inspecting: \(error.localizedDescription)"; return }
        refreshPermission()
        guard permission == .granted else { requestAccessibilityAccess(); return }
        pendingRun = nil
        pendingInspection = LocatorInspectionRequest(documentID: documentID, stepID: step.id, app: app,
                                                     locator: locator, variables: variables)
        runtimeValues = [:]
        if variables.isEmpty { startPendingRun() }
        else { runInputsVisible = true }
    }

    private func startPendingInspection() {
        guard !isBusy, let request = pendingInspection else { return }
        let resolved: ResolvedVariables
        let app: AppTarget
        let locator: Locator
        do {
            resolved = try VariableResolver.resolve(declarations: request.variables, overrides: runtimeValues)
            app = try VariableResolver.interpolate(request.app, using: resolved.values)
            locator = try VariableResolver.interpolate(request.locator, using: resolved.values)
        } catch { bannerMessage = error.localizedDescription; return }
        pendingInspection = nil
        runInputsVisible = false
        runtimeValues = [:]
        inspectionResult = nil
        inspectionRunning = true
        inspectionStopRequested = false
        runHUD.show(title: "Inspecting controls", subtitle: "Reading semantic matches") { [weak self] in self?.stopCurrentActivity() }
        inspectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let ranked = try await LocatorInspection.matches(app: app, locator: locator)
                try Task.checkCancellation()
                self.inspectionResult = LocatorInspectionResult(request: request, app: app, locator: locator,
                                                               ranked: ranked, resolved: resolved)
            } catch {
                let message = Task.isCancelled ? "Inspection cancelled." : resolved.redacting(error.localizedDescription)
                self.inspectionResult = LocatorInspectionResult(request: request, message: message)
            }
            self.inspectionRunning = false
            self.inspectionStopRequested = false
            self.inspectionTask = nil
            self.runHUD.hide()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func prepareRun(_ workflow: Workflow) {
        guard !isBusy else { return }
        do { try WorkflowSchemaValidator().validateOrThrow(workflow) }
        catch { bannerMessage = "Fix this tape before replay: \(error.localizedDescription)"; return }
        var hasTarget = false
        for step in workflow.steps {
            if step.action.kind == .activateApp { hasTarget = true }
            else if step.action.kind != .pause && !hasTarget {
                bannerMessage = "Add an Activate app step before ‘\(step.name ?? step.id)’. Replay never targets an unspecified app."
                return
            }
        }
        if workflow.steps.contains(where: { $0.action.kind != .pause }) {
            refreshPermission()
            guard permission == .granted else { requestAccessibilityAccess(); return }
        }
        pendingRun = workflow
        pendingInspection = nil
        runtimeValues = [:]
        if workflow.variables.isEmpty { startPendingRun() }
        else { runInputsVisible = true }
    }

    func startPendingRun() {
        if pendingInspection != nil { startPendingInspection(); return }
        guard !isBusy, let workflow = pendingRun else { return }
        do { _ = try VariableResolver.resolve(declarations: workflow.variables, overrides: runtimeValues) }
        catch { bannerMessage = error.localizedDescription; return }
        pendingRun = nil
        runInputsVisible = false
        let values = runtimeValues
        runtimeValues = [:]
        let sessionID = UUID()
        runSessionID = sessionID
        traces = []
        activity = .running(stepID: workflow.steps.first?.id)
        bannerMessage = "Replaying the tape. Keep target apps in front; use the floating Stop button to cancel."
        runHUD.show(title: "Replaying Tape", subtitle: workflow.name) { [weak self] in self?.stopCurrentActivity() }
        runTask = Task { [weak self] in
            guard let self else { return }
            let runner = WorkflowRunner(driver: MacOSAccessibilityDriver())
            let result = await runner.run(workflow, variables: values) { trace in
                Task { @MainActor [weak self] in
                    guard let self, self.runSessionID == sessionID, self.activity != .stopping else { return }
                    if let index = self.traces.firstIndex(where: { $0.stepID == trace.stepID }) { self.traces[index] = trace }
                    else { self.traces.append(trace) }
                    let next = workflow.steps.firstIndex { $0.id == trace.stepID }.flatMap { index in
                        workflow.steps.indices.contains(index + 1) ? workflow.steps[index + 1].id : nil
                    }
                    self.activity = .running(stepID: next)
                }
            }
            guard self.runSessionID == sessionID else { return }
            self.runSessionID = nil
            self.traces = result.steps
            self.activity = .idle
            self.runTask = nil
            self.runHUD.hide()
            switch result.status {
            case .succeeded: self.bannerMessage = "Replay completed in \(String(format: "%.2f", result.duration)) seconds."
            case .failed: self.bannerMessage = "Replay stopped: \(result.message ?? "a step failed")"
            case .cancelled: self.bannerMessage = "Replay cancelled. Completed actions cannot be undone automatically."
            }
        }
    }

    func cancelPendingRun() {
        pendingRun = nil
        pendingInspection = nil
        runtimeValues = [:]
        runInputsVisible = false
    }

    func stopCurrentActivity() {
        if inspectionRunning {
            inspectionStopRequested = true
            inspectionTask?.cancel()
        } else if isRecording {
            let documentID = recordingDocumentID
            recordingSessionID = nil
            recordingDocumentID = nil
            recorder?.stop()
            recorder = nil
            activity = .idle
            if let documentID { saveDocument(documentID) }
            if documentID.flatMap({ id in documents.first { $0.id == id } })?.isSaved == true {
                bannerMessage = "Recording stopped and saved locally. Review the locators before replaying."
            }
        } else if isRunning {
            activity = .stopping
            runTask?.cancel()
            bannerMessage = "Stop requested. Waiting for the current accessibility call to return; completed actions remain applied."
        }
    }

    func refreshPermission() { permission = AccessibilityPermission.current }
    func requestAccessibilityAccess() {
        AccessibilityPermission.request()
        refreshPermission()
        if permission != .granted {
            bannerMessage = "Enable ActionTape in System Settings → Privacy & Security → Accessibility, then return here. Recording has not started."
            openPrivacySettings()
        }
    }
    func openPrivacySettings() { AccessibilityPermission.openSystemSettings() }
    func dismissBanner() { bannerMessage = nil }

    func copyLocator(_ locator: Locator) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(locator)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
            bannerMessage = "Locator copied as JSON."
        } catch { bannerMessage = "Could not copy locator: \(error.localizedDescription)" }
    }

    func importWorkflow() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yml") ?? .plainText, UTType(filenameExtension: "yaml") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Drafts exported by Studio may intentionally contain incomplete steps. Keep
            // importing lossless; the timeline surfaces schema issues and replay rejects them.
            let workflow = try WorkflowYAML.load(from: url, validate: false)
            let localURL = try store.save(workflow)
            let document = WorkflowDocument(workflow: workflow, fileURL: localURL)
            documents.insert(document, at: 0)
            selectDocument(document.id)
            bannerMessage = "Imported \(url.lastPathComponent)."
        } catch { bannerMessage = "Could not import this tape: \(error.localizedDescription)" }
    }

    func exportSelectedWorkflow() {
        guard !isBusy, let workflow = selectedWorkflow else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(workflow.name).actiontape.yml"
        panel.allowedContentTypes = [UTType(filenameExtension: "yml") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try WorkflowYAML.save(workflow, to: url, validate: false)
            bannerMessage = "Exported \(url.lastPathComponent). Drafts are validated before replay."
        } catch { bannerMessage = "Could not export this tape: \(error.localizedDescription)" }
    }

    func saveSelectedWorkflow() {
        guard let id = selectedDocumentID else { return }
        saveDocument(id)
        if selectedDocument?.isSaved == true { bannerMessage = "Tape saved locally. Drafts are validated before replay." }
    }

    private func appendRecordedStep(_ step: Step, sessionID: UUID) {
        guard isRecording, recordingSessionID == sessionID, let documentID = recordingDocumentID,
              let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[index].workflow.steps.append(step)
        documents[index].modifiedAt = .now
        documents[index].isSaved = false
        selectedStepID = step.id
        saveDocument(documentID)
    }

    private func saveDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        do {
            documents[index].fileURL = try store.save(documents[index].workflow, replacing: documents[index].fileURL)
            documents[index].isSaved = true
        } catch {
            documents[index].isSaved = false
            bannerMessage = "Changes are only in memory; local save failed: \(error.localizedDescription)"
        }
    }
}

func defaultAction(_ kind: StepActionKind, locator: Locator = Locator()) -> StepAction {
    switch kind {
    case .activateApp: .activateApp(AppTarget(bundleIdentifier: "com.apple.finder", name: "Finder"))
    case .press: .press(locator)
    case .setValue: .setValue(locator: locator, value: "")
    case .hotKey: .hotKey(HotKey(key: "n", modifiers: [.command]))
    case .waitFor: .waitFor(locator)
    case .assertExists: .assertExists(locator)
    case .pause: .pause(duration: 1)
    }
}

func stepLocator(_ step: Step) -> Locator? {
    switch step.action {
    case .press(let locator), .waitFor(let locator), .assertExists(let locator), .setValue(let locator, _): locator
    default: nil
    }
}

enum AccessibilityPermission: Equatable {
    case granted, denied
    static var current: Self { AXIsProcessTrusted() ? .granted : .denied }
    static func request() {
        _ = MacOSAccessibilityDriver.isTrusted(prompt: true)
    }
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
