import SwiftUI

/// A side-effect-free target for recording, replaying, and debugging tapes.
@main
struct ActionTapePracticeApp: App {
    var body: some Scene {
        WindowGroup("ActionTape Practice") {
            PracticeView()
                .frame(minWidth: 620, minHeight: 450)
        }
        .defaultSize(width: 680, height: 510)
    }
}

private struct PracticeView: View {
    @State private var recipient = ""
    @State private var express = false
    @State private var preparedRecipient: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("The windows moved.\nThe workflow still worked.")
                        .font(.title2.weight(.semibold))
                    Text("A safe playground for ActionTape")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("PRACTICE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Prepare a sample shipping label")
                    .font(.headline)
                TextField("Recipient", text: $recipient)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Recipient")
                    .accessibilityIdentifier("recipient-field")
                Toggle("Express delivery", isOn: $express)
                    .accessibilityIdentifier("express-toggle")
                HStack {
                    Button("Prepare Label") {
                        preparedRecipient = recipient.isEmpty ? "a new friend" : recipient
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityIdentifier("prepare-button")
                    Button("Reset") {
                        recipient = ""
                        express = false
                        preparedRecipient = nil
                    }
                    .accessibilityIdentifier("reset-button")
                    .keyboardShortcut("r", modifiers: [.command])
                }
            }

            HStack(spacing: 12) {
                Image(systemName: preparedRecipient == nil ? "circle.dashed" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(preparedRecipient == nil ? Color.secondary : Color.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preparedRecipient == nil ? "Ready" : "Prepared")
                        .font(.headline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityLabel(preparedRecipient == nil ? "Ready" : "Prepared")
                        .accessibilityIdentifier(preparedRecipient == nil ? "ready-status" : "prepared-status")
                    Text(preparedRecipient.map { "Sample label for \($0) · \(express ? "Express" : "Standard")" }
                         ?? "Run a tape, then move this window and run it again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Text("Nothing is sent, saved, or purchased. This form only changes its own in-memory state.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
    }
}
