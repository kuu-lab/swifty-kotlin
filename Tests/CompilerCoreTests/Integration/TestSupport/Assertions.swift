#if canImport(Testing)
@testable import CompilerCore
import Testing

private struct TestRequirementFailure: Error, CustomStringConvertible {
    let description: String
}

func requireTestValue<T>(
    _ value: T?,
    _ message: @autoclosure () -> String
) throws -> T {
    guard let value else {
        throw TestRequirementFailure(description: message())
    }
    return value
}

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
    #expect(!(found), "Unexpected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))")
}

func assertDiagnosticCount(
    _ code: String,
    expected: Int,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let count = ctx.diagnostics.diagnostics.filter { $0.code == code }.count
    #expect(count == expected, "Expected \(expected) diagnostic(s) with code \(code), got \(count). All diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))")
}
#endif
