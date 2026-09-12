import ActionTapeCore
import SwiftUI

struct TapeSidebar: View {
    @EnvironmentObject private var state: StudioState
    @State private var searchText = ""

    private var filteredDocuments: [WorkflowDocument] {
        guard !searchText.isEmpty else { return state.documents }
        return state.documents.filter {
            $0.workflow.name.localizedCaseInsensitiveContains(searchText)
            || ($0.workflow.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tapes", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search tapes")
            }
            .font(.callout)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            HStack {
                Text("TAPES")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                Button(action: state.createWorkflow) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New tape")
                .disabled(state.isBusy)
            }
            .padding(.horizontal, 13)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            List(selection: Binding(
                get: { state.selectedDocumentID },
                set: { state.selectDocument($0) }
            )) {
                ForEach(filteredDocuments) { document in
                    TapeSidebarRow(document: document)
                        .tag(document.id)
                        .contextMenu {
                            Button("Duplicate") { state.selectDocument(document.id); state.duplicateSelectedWorkflow() }
                            Divider()
                            Button("Delete", role: .destructive) { state.selectDocument(document.id); state.deleteSelectedWorkflow() }
                        }
                }
            }
            .listStyle(.sidebar)
            .disabled(state.isBusy)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Button("Import tape…", action: state.importWorkflow).disabled(state.isBusy)
                    Label("Local only", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    Text("Tapes and traces stay on this Mac. No account, cloud, or telemetry.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TapeSidebarRow: View {
    let document: WorkflowDocument

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(StudioTheme.accentGradient)
                Image(systemName: "recordingtape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.workflow.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(document.workflow.steps.count) steps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
