#if canImport(Testing)
@testable import CompilerCore
import Testing

// 非テストターゲットでは TestingMacros プラグインがロードされないため、
// `#expect`/`#require` ではなく `Issue.record` (sourceLocation 明示) で失敗を記録する。
func recordTestIssue(
    _ comment: Comment,
    fileID: StaticString,
    file: StaticString,
    line: UInt
) {
    Issue.record(
        comment,
        sourceLocation: SourceLocation(
            fileID: fileID.description,
            filePath: file.description,
            line: Int(line),
            column: 1
        )
    )
}

func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    if !found {
        recordTestIssue(
            "Expected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))",
            fileID: fileID, file: file, line: line
        )
    }
}

func assertNoDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    if found {
        recordTestIssue(
            "Unexpected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))",
            fileID: fileID, file: file, line: line
        )
    }
}
#endif
