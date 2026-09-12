import ActionTapeCore
import Foundation

struct WorkflowFileStore {
    let directory: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directory = support
            .appendingPathComponent("ActionTape", isDirectory: true)
            .appendingPathComponent("Tapes", isDirectory: true)
    }

    struct LibraryLoad {
        var documents: [WorkflowDocument] = []
        var failures: [String] = []
    }

    func loadAll(fileManager: FileManager = .default) throws -> LibraryLoad {
        try ensureDirectory(fileManager: fileManager)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        var result = LibraryLoad()
        for url in urls.filter({ ["yml", "yaml"].contains($0.pathExtension.lowercased()) }) {
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true else { continue }
                result.documents.append(WorkflowDocument(
                    workflow: try WorkflowYAML.load(from: url, validate: false),
                    fileURL: url,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                ))
            } catch {
                result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        result.documents.sort { $0.modifiedAt > $1.modifiedAt }
        return result
    }

    @discardableResult
    func save(
        _ workflow: Workflow,
        replacing url: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try ensureDirectory(fileManager: fileManager)
        let destination = url ?? uniqueURL(for: workflow.name, fileManager: fileManager)
        // Drafts may be incomplete while the user edits. Validation happens before replay.
        try WorkflowYAML.save(workflow, to: destination, validate: false)
        return destination
    }

    func remove(_ url: URL, fileManager: FileManager = .default) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    private func ensureDirectory(fileManager: FileManager) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func uniqueURL(for name: String, fileManager: FileManager) -> URL {
        let base = slug(name).isEmpty ? "untitled-tape" : slug(name)
        var candidate = directory.appendingPathComponent("\(base).actiontape.yml")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).actiontape.yml")
            suffix += 1
        }
        return candidate
    }

    private func slug(_ value: String) -> String {
        let transformed = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        return String(transformed).split(separator: "-").joined(separator: "-")
    }
}
