#if canImport(Testing)
@testable import CompilerCore
import Testing

func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    #expect(found, "Expected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))")
}

func assertNoDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    #expect(!found, "Unexpected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))")
}
#endif
