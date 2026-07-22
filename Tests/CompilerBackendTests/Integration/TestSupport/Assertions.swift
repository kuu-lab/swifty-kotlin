@testable import CompilerCore
@testable import CompilerBackend
import XCTest

func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    XCTAssertTrue(found, "Expected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))", file: file, line: line)
}

func assertNoDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    XCTAssertFalse(found, "Unexpected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))", file: file, line: line)
}
