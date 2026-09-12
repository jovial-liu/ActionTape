import ActionTapeCore
import SwiftUI

struct LocatorDiagnosticsView: View {
    @EnvironmentObject private var state: StudioState
    let step: Step

    private var result: LocatorInspectionResult? {
        guard let result = state.inspectionResult,
              result.stepID == step.id, result.documentID == state.selectedDocumentID else { return nil }
        return result
    }

    var body: some View {
        InspectorSection(title: "Live match diagnostics") {
            HStack {
                Button { state.inspectMatches(for: step) } label: {
                    Label("Inspect matches", systemImage: "scope")
                }
                .disabled(state.isBusy)
                .accessibilityIdentifier("inspect-matches")
                if state.inspectionRunning {
                    ProgressView().controlSize(.small)
                    Spacer(minLength: 0)
                    Button(state.inspectionStopRequested ? "Stopping…" : "Cancel", action: state.stopCurrentActivity)
                        .disabled(state.inspectionStopRequested)
                }
            }
            Text("Opens or activates the nearest preceding app target, then reads its current controls. No clicks or text entry. Earlier tape actions are not replayed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let result {
                outcome(result)
                Text("\(result.appName) · \(result.inspectedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
                if !result.candidates.isEmpty {
                    Text("\(result.matchCount) matching control\(result.matchCount == 1 ? "" : "s") · ranked by selector score")
                        .font(.caption.weight(.medium))
                    if result.matchCount > result.candidates.count {
                        Text("Showing the first \(result.candidates.count) matches.").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(Array(result.candidates.enumerated()), id: \.element.id) { index, candidate in
                        candidateCard(candidate, rank: index + 1)
                    }
                    Text("Scores combine matching signals; they are not confidence percentages. Results are a snapshot of the app at inspection time.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func outcome(_ result: LocatorInspectionResult) -> some View {
        switch result.outcome {
        case .selected:
            Label("Unique best match", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(StudioTheme.success)
        case .notFound:
            Label("No matching controls", systemImage: "magnifyingglass")
                .font(.callout.weight(.semibold)).foregroundStyle(StudioTheme.warning)
            Text("No accessible element satisfies every supplied criterion. Check identifiers, state-dependent labels, and whether the expected window is open.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .ambiguous(let count):
            Label("Ambiguous · \(count) tied best matches", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(StudioTheme.warning)
            Text("Replay would stop here. Add an identifier, title, or ancestor selector to distinguish the intended control.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label("Inspection stopped", systemImage: "info.circle")
                .font(.callout.weight(.semibold)).foregroundStyle(StudioTheme.warning)
            Text(message).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func candidateCard(_ candidate: LocatorInspectionResult.Candidate, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(rank)").foregroundStyle(.secondary)
                Text(candidate.role ?? "Unknown role").lineLimit(1)
                Spacer(minLength: 2)
                Text("\(candidate.score) pts").foregroundStyle(StudioTheme.violet)
            }.font(.caption.monospaced().weight(.semibold))
            detail("Identifier", candidate.identifier)
            detail("Role", candidate.role)
            detail("Title", candidate.title)
            detail("Description", candidate.description)
            DisclosureGroup("Score breakdown") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidate.components, id: \.signal) { component in
                        HStack {
                            Text(component.signal.rawValue.capitalized)
                            Spacer()
                            Text("+\(component.points)").monospacedDigit()
                        }
                    }
                }.padding(.top, 5)
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(11)
        .background(StudioTheme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(StudioTheme.violet.opacity(0.12)) }
    }

    private func detail(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value ?? "—").font(.caption.monospaced()).lineLimit(4).textSelection(.enabled)
        }
    }
}
