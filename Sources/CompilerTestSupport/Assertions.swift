#if canImport(Testing)
@testable import CompilerCore
import Testing

// 非テストターゲットでは TestingMacros プラグインがロードされないため、
// `#expect` ではなく `Issue.record` (sourceLocation 明示) で失敗を記録する。
func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    if !found {
        Issue.record(
            "Expected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))",
            severity: .error,
            sourceLocation: SourceLocation(
                fileID: fileID.description,
                filePath: file.description,
                line: Int(line),
                column: 1
            )
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
        Issue.record(
            "Unexpected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))",
            severity: .error,
            sourceLocation: SourceLocation(
                fileID: fileID.description,
                filePath: file.description,
                line: Int(line),
                column: 1
            )
        )
    }
}
#endif
