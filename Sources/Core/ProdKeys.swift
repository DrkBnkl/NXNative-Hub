import Foundation

// MARK: - prod.keys sanity check
//
// Only checks that the file looks like a Switch key file – key values are never logged or shown.

enum ProdKeysFile {
    enum Validity: Equatable {
        case valid
        case missing
        case unreadable
        /// Readable, but the keys nxnative needs to decrypt games are not in it.
        case incomplete
    }

    /// Key names every NSP decryption needs.
    private static let requiredKeyPrefixes = ["header_key", "key_area_key_application_"]

    static func validate(path: String) -> Validity {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return .missing }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return .unreadable }
        let names = content.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1)
            return parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespaces).lowercased() : nil
        }
        let complete = requiredKeyPrefixes.allSatisfy { prefix in names.contains { $0.hasPrefix(prefix) } }
        return complete ? .valid : .incomplete
    }
}
