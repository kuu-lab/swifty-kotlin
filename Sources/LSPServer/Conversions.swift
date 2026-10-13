import CompilerCore

/// Conversions from compiler source ranges and diagnostics to LSP payloads.
enum LSPConvert {
    /// Converts a compiler `SourceRange` to an LSP range (0-based, UTF-16).
    static func range(_ sourceRange: SourceRange, _ sourceManager: SourceManager) -> LSPRange {
        let start = sourceManager.lspPosition(of: sourceRange.start)
        let end = sourceManager.lspPosition(of: sourceRange.end)
        return LSPRange(
            start: LSPPosition(line: start.line, character: start.character),
            end: LSPPosition(line: end.line, character: end.character)
        )
    }

    /// Converts a compiler `SourceRange` to an LSP location, deriving the
    /// document URI from the range's source file.
    static func location(_ sourceRange: SourceRange, _ sourceManager: SourceManager) -> LSPLocation {
        let path = sourceManager.path(of: sourceRange.start.file)
        return LSPLocation(uri: DocumentURI.uri(fromPath: path), range: range(sourceRange, sourceManager))
    }

    /// Converts a compiler `Diagnostic` to an LSP diagnostic anchored at the
    /// given range.
    static func diagnostic(_ diagnostic: Diagnostic, range: LSPRange) -> LSPDiagnostic {
        LSPDiagnostic(
            range: range,
            severity: severity(diagnostic.severity).rawValue,
            code: diagnostic.code,
            source: "kswiftk",
            message: diagnostic.message
        )
    }

    private static func severity(_ severity: DiagnosticSeverity) -> LSPDiagnosticSeverity {
        switch severity {
        case .error: .error
        case .warning: .warning
        case .note: .information
        case .info: .hint
        }
    }
}
