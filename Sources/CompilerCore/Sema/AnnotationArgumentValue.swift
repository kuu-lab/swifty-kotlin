import Foundation

enum SemaAnnotationArgument {
    static func value(_ raw: String, parameterName: String? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parameterName {
            let pieces = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2,
                  pieces[0].trimmingCharacters(in: .whitespacesAndNewlines) == parameterName
            else {
                return trimmed
            }
            return pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let equalIndex = trimmed.firstIndex(of: "=") else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: equalIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
