import Foundation

// MARK: - Inline KIR Filename Helpers

extension String {
    /// FNV-1a 64-bit hash used to derive a stable, filesystem-safe filename
    /// from an arbitrary mangled name.
    package var fnv1a64Hash: UInt64 {
        let offset: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        var hash = offset
        for byte in self.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

extension MetadataEncoder {
    /// Returns the inline-KIR filename for a mangled symbol name.
    /// Short, filesystem-safe names are preserved; long or non-alphanumeric
    /// mangled names are hashed to avoid exceeding filesystem path limits.
    package static func inlineKIRFileName(for mangledName: String) -> String {
        let safePattern = "^[A-Za-z0-9_-]+$"
        let isSafe = mangledName.range(of: safePattern, options: .regularExpression) != nil
        if isSafe && mangledName.count <= 64 {
            return "\(mangledName).kirbin"
        }
        return "\(mangledName.fnv1a64Hash).kirbin"
    }
}
