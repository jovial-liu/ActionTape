import AppKit
import Foundation

// Headless packaging verification, not a UI/Accessibility compatibility test.
// In particular, resolve resources through the app-local Bundle.module path
// without ever using SwiftPM's absolute developer-machine build fallback.
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw VerificationError.invalid(message) }
}

enum VerificationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

do {
    try require(CommandLine.arguments.count == 2, "Usage: swift scripts/verify-app.swift /path/to/ActionTape.app")
    let fileManager = FileManager.default
    let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
    guard let app = Bundle(url: appURL) else {
        throw VerificationError.invalid("Could not open app bundle: \(appURL.path)")
    }
    let isPractice = app.bundleIdentifier == "com.jovial-liu.ActionTape.Practice"
    try require(app.bundleIdentifier == "dev.actiontape.studio" || isPractice, "Unexpected bundle identifier")
    try require(app.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL", "Missing APPL package type")
    try require(app.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String == "14.0", "Unexpected deployment target")
    guard let executable = app.executableURL else {
        throw VerificationError.invalid("Info.plist does not resolve an executable")
    }
    try require(fileManager.isExecutableFile(atPath: executable.path), "Executable is missing or not executable")
    guard let resourcesURL = app.resourceURL else {
        throw VerificationError.invalid("Missing Resources directory")
    }
    let iconURL = resourcesURL.appendingPathComponent("ActionTape.icns")
    let iconData = try Data(contentsOf: iconURL)
    try require(iconData.starts(with: Array("icns".utf8)), "App icon is not an ICNS file")
    try require(NSImage(contentsOf: iconURL)?.isValid == true, "App icon cannot be decoded")

    if !isPractice {
        let resourceName = "ActionTape_ActionTapeStudio.bundle"
        let moduleURL = appURL.appendingPathComponent(resourceName, isDirectory: true)
        let expectedURL = resourcesURL.appendingPathComponent(resourceName, isDirectory: true).resolvingSymlinksInPath()
        try require(moduleURL.resolvingSymlinksInPath() == expectedURL, "Bundle.module link does not resolve inside Contents/Resources")
        guard let module = Bundle(url: moduleURL),
              let pngURL = module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: pngURL), image.isValid else {
            throw VerificationError.invalid("SwiftPM resource bundle cannot load its app-local icon")
        }
    }
    let licenses = isPractice ? ["ActionTape-LICENSE.txt"] : ["ActionTape-LICENSE.txt", "Yams-LICENSE.txt", "ThirdParty-NOTICE.md"]
    for name in licenses {
        let license = resourcesURL.appendingPathComponent("Licenses").appendingPathComponent(name)
        try require(fileManager.isReadableFile(atPath: license.path), "Missing license: \(name)")
    }
    print("Verified app-local resources, icons, executable, metadata, and licenses: \(appURL.path)")
} catch {
    FileHandle.standardError.write(Data("App verification failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
