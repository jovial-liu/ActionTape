import ActionTapeCore
import Foundation

enum DemoContent {
    static let welcome = Workflow(
        name: "Example · Prepare a greeting",
        description: "A safe example for the included ActionTape Practice app. Launch Practice first, then replay. It changes only the practice app’s in-memory form; nothing is sent or saved outside this Mac. Other apps need their own recorded locators.",
        variables: ["recipient": WorkflowVariable(defaultValue: "Alex", description: "A name for the practice greeting")],
        steps: [
            Step(id: "open-practice", name: "Open the practice app", action: .activateApp(AppTarget(bundleIdentifier: "com.jovial-liu.ActionTape.Practice", name: "ActionTape Practice"))),
            Step(id: "wait-for-form", name: "Wait for the recipient field", action: .waitFor(Locator(identifier: "recipient-field", role: "AXTextField")), timeout: 8),
            Step(id: "fill-recipient", name: "Fill in the recipient", action: .setValue(locator: Locator(identifier: "recipient-field", role: "AXTextField"), value: "{{recipient}}")),
            Step(id: "prepare-greeting", name: "Prepare the greeting", action: .press(Locator(identifier: "prepare-button", role: "AXButton"))),
            Step(id: "check-result", name: "Verify the result", action: .assertExists(Locator(identifier: "prepared-status", role: "AXStaticText")))
        ]
    )

    static let blank = Workflow(name: "Untitled Tape", description: "", steps: [])
}
