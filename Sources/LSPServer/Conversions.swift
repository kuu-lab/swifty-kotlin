import CompilerCore

enum LSPConvert {
    static func range(_ sourceRange: SourceRange, _ sourceManager: SourceManager) -> LSPRange {
        let start = sourceManager.lspPosition(of: sourceRange.start)
        let end = sourceManager.lspPosition(of: sourceRange.end)
        return LSPRange(
            start: LSPPosition(line: start.line, character: start.character),
            end: LSPPosition(line: end.line, character: end.character)
        )
    }

    static func location(_ sourceRange: SourceRange, _ sourceManager: SourceManager) -> LSPLocation {
        let path = sourceManager.path(of: sourceRange.start.file)
        return LSPLocation(uri: DocumentURI.uri(fromPath: path), range: range(sourceRange, sourceManager))
    }

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
