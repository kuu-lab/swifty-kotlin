#if canImport(Testing)
import Foundation
@testable import CompilerCore
import Testing

struct ExpectedDiagnostic: Sendable {
    var severity: DiagnosticSeverity?
    var code: String?
    var messageContains: String?
    var count: Int

    init(
        severity: DiagnosticSeverity? = nil,
        code: String? = nil,
        messageContains: String? = nil,
        count: Int = 1
    ) {
        self.severity = severity
        self.code = code
        self.messageContains = messageContains
        self.count = count
    }

    static func error(
        _ code: String? = nil,
        containing message: String? = nil,
        count: Int = 1
    ) -> ExpectedDiagnostic {
        ExpectedDiagnostic(severity: .error, code: code, messageContains: message, count: count)
    }

    static func warning(
        _ code: String? = nil,
        containing message: String? = nil,
        count: Int = 1
    ) -> ExpectedDiagnostic {
        ExpectedDiagnostic(severity: .warning, code: code, messageContains: message, count: count)
    }

    func matches(_ diagnostic: Diagnostic) -> Bool {
        if let severity, diagnostic.severity != severity { return false }
        if let code, diagnostic.code != code { return false }
        if let messageContains, !diagnostic.message.contains(messageContains) { return false }
        return true
    }
}

private func describe(_ expectation: ExpectedDiagnostic) -> String {
    var parts: [String] = []
    if let severity = expectation.severity {
        parts.append("severity=\(severity)")
    } else {
        parts.append("severity=any")
    }
    if let code = expectation.code {
        parts.append("code=\(code)")
    }
    if let message = expectation.messageContains {
        parts.append("message~\"\(message)\"")
    }
    parts.append("count=\(expectation.count)")
    return parts.joined(separator: " ")
}

private func describeAll(_ diagnostics: [Diagnostic]) -> String {
    diagnostics
        .map { "\($0.severity) \($0.code): \($0.message)" }
        .joined(separator: " | ")
}

func assertExpectedDiagnostics(
    _ expected: [ExpectedDiagnostic],
    in diagnostics: [Diagnostic],
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    for expectation in expected {
        let matches = diagnostics.filter(expectation.matches)
        #expect(
            matches.count == expectation.count,
            "Expected \(expectation.count) diagnostic(s) matching \(describe(expectation)), got \(matches.count). All diagnostics: \(describeAll(diagnostics))",
            sourceLocation: sourceLocation
        )
    }
    let unexpectedErrors = diagnostics.filter { diagnostic in
        diagnostic.severity == .error && !expected.contains { $0.matches(diagnostic) }
    }
    #expect(
        unexpectedErrors.isEmpty,
        "Unexpected error diagnostic(s) not covered by expectations: \(describeAll(unexpectedErrors)). All diagnostics: \(describeAll(diagnostics))",
        sourceLocation: sourceLocation
    )
}

func assertExpectedDiagnostics(
    _ expected: [ExpectedDiagnostic],
    in ctx: CompilationContext,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    assertExpectedDiagnostics(expected, in: ctx.diagnostics.diagnostics, sourceLocation: sourceLocation)
}

extension CompilationContext {
    var errorDiagnostics: [Diagnostic] {
        diagnostics.diagnostics.filter { $0.severity == .error }
    }

    var warningDiagnostics: [Diagnostic] {
        diagnostics.diagnostics.filter { $0.severity == .warning }
    }

    func diagnosticsWithCode(
        _ code: String,
        severity: DiagnosticSeverity? = nil
    ) -> [Diagnostic] {
        diagnostics.diagnostics.filter {
            $0.code == code && (severity == nil || $0.severity == severity)
        }
    }
}

private enum CompileThrough {
    case sema
    case kir
    case lowering
}

private func compileContext(
    from sources: [String],
    through phase: CompileThrough,
    expecting expected: [ExpectedDiagnostic],
    moduleName: String,
    frontendFlags: [String],
    includeStdlib: Bool,
    stdlibLibraryPath: String?,
    allowDefaultStdlibLibrary: Bool,
    sourceLocation: Testing.SourceLocation
) throws -> CompilationContext {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let fakePaths = sources.indices.map {
        directory.appendingPathComponent("input\($0).kt").path
    }
    let ctx = makeCompilationContext(
        inputs: fakePaths,
        moduleName: moduleName,
        emit: .kirDump,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
    )
    for (path, source) in zip(fakePaths, sources) {
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
    }
    switch phase {
    case .sema:
        try runSema(ctx)
    case .kir:
        try runToKIR(ctx)
    case .lowering:
        try runToLowering(ctx)
    }
    assertExpectedDiagnostics(expected, in: ctx, sourceLocation: sourceLocation)
    return ctx
}

func semaContext(
    from source: String,
    expecting expected: [ExpectedDiagnostic] = [],
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    includeStdlib: Bool = true,
    stdlibLibraryPath: String? = nil,
    allowDefaultStdlibLibrary: Bool = false,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> CompilationContext {
    try compileContext(
        from: [source],
        through: .sema,
        expecting: expected,
        moduleName: moduleName,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
        sourceLocation: sourceLocation
    )
}

func semaContext(
    from sources: [String],
    expecting expected: [ExpectedDiagnostic] = [],
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    includeStdlib: Bool = true,
    stdlibLibraryPath: String? = nil,
    allowDefaultStdlibLibrary: Bool = false,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> CompilationContext {
    try compileContext(
        from: sources,
        through: .sema,
        expecting: expected,
        moduleName: moduleName,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
        sourceLocation: sourceLocation
    )
}

func kirContext(
    from source: String,
    expecting expected: [ExpectedDiagnostic] = [],
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    includeStdlib: Bool = true,
    stdlibLibraryPath: String? = nil,
    allowDefaultStdlibLibrary: Bool = false,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> CompilationContext {
    try compileContext(
        from: [source],
        through: .kir,
        expecting: expected,
        moduleName: moduleName,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
        sourceLocation: sourceLocation
    )
}

func kirContext(
    from sources: [String],
    expecting expected: [ExpectedDiagnostic] = [],
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    includeStdlib: Bool = true,
    stdlibLibraryPath: String? = nil,
    allowDefaultStdlibLibrary: Bool = false,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> CompilationContext {
    try compileContext(
        from: sources,
        through: .kir,
        expecting: expected,
        moduleName: moduleName,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
        sourceLocation: sourceLocation
    )
}

func loweringContext(
    from source: String,
    expecting expected: [ExpectedDiagnostic] = [],
    moduleName: String = "TestModule",
    frontendFlags: [String] = [],
    includeStdlib: Bool = true,
    stdlibLibraryPath: String? = nil,
    allowDefaultStdlibLibrary: Bool = false,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> CompilationContext {
    try compileContext(
        from: [source],
        through: .lowering,
        expecting: expected,
        moduleName: moduleName,
        frontendFlags: frontendFlags,
        includeStdlib: includeStdlib,
        stdlibLibraryPath: stdlibLibraryPath,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
        sourceLocation: sourceLocation
    )
}

#endif
