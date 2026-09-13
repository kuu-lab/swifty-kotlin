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

/// Mirrors ``DiagnosticEngine/hasError`` for the plain diagnostic arrays that
/// `diagnosticsForPath` and `DriverResult` hand back, so tests spell the check
/// the same way whichever side they are holding.
extension Collection where Element == Diagnostic {
    var hasError: Bool { contains { $0.severity == .error } }
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

// The `CompilationContext` overloads below snapshot `ctx.diagnostics` once and
// delegate to the `[Diagnostic]` form, so a failure is reported at the calling
// test rather than inside this file.
//
// `Testing.SourceLocation` must stay qualified: CompilerCore declares its own
// `SourceLocation`, so the bare name is ambiguous in any file that also does
// `@testable import CompilerCore`.

func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    assertHasDiagnostic(code, in: ctx.diagnostics.diagnostics, sourceLocation: sourceLocation)
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
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    assertNoDiagnostic(code, in: ctx.diagnostics.diagnostics, sourceLocation: sourceLocation)
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
    assertDiagnosticCount(code, expected: expected, in: ctx.diagnostics.diagnostics, sourceLocation: sourceLocation)
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
