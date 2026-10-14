import Foundation

/// Persists custom Space names keyed by `Space.key`.
public final class NameStore {
    public static let maxNameLength = 40

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MySpaces/names.json")
    }

    private struct FileFormat: Codable {
        var version = 1
        var names: [String: String]
    }

    public private(set) var names: [String: String] = [:]
    public private(set) var recoveredFromCorruption = false
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    public func name(for key: String) -> String? { names[key] }

    /// Normalises and saves; an empty result removes the custom name.
    public func setName(_ raw: String, for key: String) throws {
        let name = Self.normalize(raw)
        if name.isEmpty { names.removeValue(forKey: key) } else { names[key] = name }
        try save()
    }

    public func removeNames(for keys: Set<String>) throws {
        guard !keys.isEmpty else { return }
        for key in keys { names.removeValue(forKey: key) }
        try save()
    }

    public static func normalize(_ raw: String) -> String {
        let collapsed = raw.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(maxNameLength))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            names = try JSONDecoder().decode(FileFormat.self, from: data).names
        } catch {
            let backup = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            names = [:]
            recoveredFromCorruption = true
        }
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(FileFormat(names: names)).write(to: fileURL, options: .atomic)
    }
}
