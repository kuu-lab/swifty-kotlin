#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
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

func diagnosticsForPath(
    _ path: String,
    in ctx: CompilationContext
) -> [Diagnostic] {
    guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
    return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
}

func diagnosticsForPath(
    _ path: String,
    withCode code: String,
    in ctx: CompilationContext
) -> [Diagnostic] {
    diagnosticsForPath(path, in: ctx).filter { $0.code == code }
}

func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    CompilerTestSupport.assertHasDiagnostic(code, in: ctx, file: file, line: line)
}

func assertHasDiagnostic(
    _ code: String,
    in diagnostics: [Diagnostic],
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    let found = diagnostics.contains { $0.code == code }
    #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map(\.code))", sourceLocation: sourceLocation)
}

func assertNoDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    CompilerTestSupport.assertNoDiagnostic(code, in: ctx, file: file, line: line)
}

func assertNoDiagnostic(
    _ code: String,
    in diagnostics: [Diagnostic],
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    let found = diagnostics.contains { $0.code == code }
    #expect(!(found), "Unexpected diagnostic \(code), got: \(diagnostics.map(\.code))", sourceLocation: sourceLocation)
}

func assertDiagnosticCount(
    _ code: String,
    expected: Int,
    in ctx: CompilationContext,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    let count = ctx.diagnostics.diagnostics.filter { $0.code == code }.count
    #expect(count == expected, "Expected \(expected) diagnostic(s) with code \(code), got \(count). All diagnostics: \(ctx.diagnostics.diagnostics.map(\.code))", sourceLocation: sourceLocation)
}

func assertDiagnosticCount(
    _ code: String,
    expected: Int,
    in diagnostics: [Diagnostic],
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    let count = diagnostics.filter { $0.code == code }.count
    #expect(count == expected, "Expected \(expected) diagnostic(s) with code \(code), got \(count). All diagnostics: \(diagnostics.map(\.code))", sourceLocation: sourceLocation)
}
#endif
