#if canImport(Testing)
import Foundation
@testable import CompilerCore
import Testing

/// コンパイル結果に期待する診断 1 件分の条件。
///
/// `severity` が nil のときは severity 不問。`code` / `messageContains` は
/// 指定したときだけ絞り込みに使う（message は部分一致）。`count` は条件に
/// 合致すべき診断の件数。
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

    /// error 診断を期待する。`code` 省略時はコード不問。
    static func error(
        _ code: String? = nil,
        containing message: String? = nil,
        count: Int = 1
    ) -> ExpectedDiagnostic {
        ExpectedDiagnostic(severity: .error, code: code, messageContains: message, count: count)
    }

    /// warning 診断を期待する。`code` 省略時はコード不問。
    static func warning(
        _ code: String? = nil,
        containing message: String? = nil,
        count: Int = 1
    ) -> ExpectedDiagnostic {
        ExpectedDiagnostic(severity: .warning, code: code, messageContains: message, count: count)
    }

    /// note 診断を期待する。`code` 省略時はコード不問。
    static func note(
        _ code: String? = nil,
        containing message: String? = nil,
        count: Int = 1
    ) -> ExpectedDiagnostic {
        ExpectedDiagnostic(severity: .note, code: code, messageContains: message, count: count)
    }

    /// info 診断を期待する。`code` 省略時はコード不問。
    static func info(
        _ code: String? = nil,
        containing message: String? = nil,
        count: Int = 1
    ) -> ExpectedDiagnostic {
        ExpectedDiagnostic(severity: .info, code: code, messageContains: message, count: count)
    }

    /// severity 不問の診断を期待する。
    static func anySeverity(
        _ code: String? = nil,
        containing message: String? = nil,
        count: Int = 1
    ) -> ExpectedDiagnostic {
        ExpectedDiagnostic(severity: nil, code: code, messageContains: message, count: count)
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

/// `diagnostics` が `expected` の各要件を満たし、かつどの要件にも
/// 対応しない error 診断を含まないことを検証する。
///
/// - 各要件について、条件に合う診断が `count` 件あることを確認する。
/// - いずれの要件にも合致しない error 診断が 0 件であることを確認する。
///   warning / note / info は expected に列挙された分だけ検査し、
///   余分に出ていても失敗にしない。
///
/// 要件どうしは独立したフィルタとして扱う（1 件の診断が複数要件に
/// 合致してもよい）。同一診断を 2 要件で数えたい場合は使わないこと。
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

/// `CompilationContext` 版の `assertExpectedDiagnostics`。
func assertExpectedDiagnostics(
    _ expected: [ExpectedDiagnostic],
    in ctx: CompilationContext,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    assertExpectedDiagnostics(expected, in: ctx.diagnostics.diagnostics, sourceLocation: sourceLocation)
}

extension CompilationContext {
    /// error 深刻度の診断のみを返す。`diagnostics.diagnostics.filter { $0.severity == .error }`
    /// の置き換え用。
    var errorDiagnostics: [Diagnostic] {
        diagnostics.diagnostics.filter { $0.severity == .error }
    }

    /// warning 深刻度の診断のみを返す。
    var warningDiagnostics: [Diagnostic] {
        diagnostics.diagnostics.filter { $0.severity == .warning }
    }

    /// 指定コードの診断を返す。`severity` を渡すと深刻度でも絞る。
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

/// `sources` を 1 モジュールとして in-memory ソース登録し、
/// 指定フェーズまでパイプラインを実行して診断を検証し、ctx を返す。
///
/// 実ファイルを作らない（`makeContextFromSources` と同じ fake path +
/// `SourceManager.addFile` 方式）のでディスク IO が発生しない。
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

/// `source` を 1 モジュールとして frontend→Sema まで実行し、
/// 診断が `expected` と過不足なく一致することを確認して ctx を返す。
///
/// `expected` が空（既定）なら error 診断ゼロを要求する
/// （warning / note / info は不問）。返り値の ctx で symbol table /
/// AST / bindings を追加検査できる。`runSema` がパイプラインエラーで
/// throw した場合はそのまま伝播し、診断検証には到達しない。
///
/// 使い分け:
/// - クリーンコンパイル前提で sema / ast を検査する → `semaContext(from:)`
/// - KIR まで進めて `ctx.kir` を検査する → `kirContext(from:)`
/// - Lowering まで進める → `loweringContext(from:)`
/// - 実ファイルパスや特殊な emit/searchPaths が必要 → 従来どおり
///   `withTemporaryFile` + `makeCompilationContext` を使う
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

/// `sources` を 1 モジュールとして frontend→Sema まで実行する複数ファイル版。
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

/// `source` を frontend→KIR まで実行する版。`ctx.kir` が使える。
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

/// `sources` を 1 モジュールとして frontend→KIR まで実行する複数ファイル版。
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

/// `source` を frontend→Lowering まで実行する版。
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

/// `sources` を 1 モジュールとして frontend→Lowering まで実行する複数ファイル版。
func loweringContext(
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
