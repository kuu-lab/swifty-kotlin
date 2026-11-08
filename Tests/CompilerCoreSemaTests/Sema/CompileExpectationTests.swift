#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// Self-tests for the compile-expectation DSL in
/// `Sources/CompilerTestSupport/CompileExpectations.swift`. These exercise
/// the helpers end-to-end through the real pipeline; the negative paths
/// (a mismatch failing the test) are covered by the helpers' use in the
/// migrated suites rather than here.
@Suite
struct CompileExpectationTests {
    @Test func semaContextReturnsCompiledContextForCleanSource() throws {
        let ctx = try semaContext(
            from: "fun answer(): Int = 42",
            includeStdlib: false
        )
        #expect(ctx.sema != nil)
        #expect(ctx.ast != nil)
        #expect(ctx.errorDiagnostics.isEmpty)
    }

    @Test func semaContextAcceptsExpectedErrorDiagnostic() throws {
        let ctx = try semaContext(
            from: "fun broken() = missingName",
            expecting: [.error("KSWIFTK-SEMA-0022", containing: "Unresolved reference 'missingName'")],
            includeStdlib: false
        )
        #expect(ctx.sema != nil)
        #expect(ctx.errorDiagnostics.count == 1)
    }

    @Test func semaContextCompilesMultipleSourcesAsOneModule() throws {
        let ctx = try semaContext(
            from: [
                "fun meaning(): Int = 42",
                "fun useMeaning(): Int = meaning()",
            ],
            includeStdlib: false
        )
        #expect(ctx.sema != nil)
        #expect(ctx.errorDiagnostics.isEmpty)
    }

    @Test func kirContextRunsThroughKIRBuild() throws {
        let ctx = try kirContext(
            from: "fun compose(a: Int, b: Int): Int = a + b",
            includeStdlib: false
        )
        #expect(ctx.kir != nil)
        #expect(ctx.errorDiagnostics.isEmpty)
    }

    @Test func loweringContextRunsThroughLowering() throws {
        let ctx = try loweringContext(
            from: "fun answer(): Int = 42",
            includeStdlib: false
        )
        #expect(ctx.kir != nil)
        #expect(ctx.errorDiagnostics.isEmpty)
    }

    @Test func diagnosticQueriesFilterBySeverityAndCode() throws {
        let ctx = try semaContext(
            from: "fun broken() = missingName",
            expecting: [.error("KSWIFTK-SEMA-0022")],
            includeStdlib: false
        )
        #expect(ctx.errorDiagnostics.count == 1)
        #expect(ctx.warningDiagnostics.isEmpty)
        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-0022").count == 1)
        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-0022", severity: .error).count == 1)
        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-0022", severity: .warning).isEmpty)
        #expect(ctx.diagnosticsWithCode("KSWIFTK-SEMA-0001").isEmpty)
    }

    @Test func assertExpectedDiagnosticsMatchesFabricatedDiagnostics() {
        let diagnostics = [
            Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0022",
                message: "Unresolved reference 'foo'.",
                primaryRange: nil,
                secondaryRanges: []
            ),
            Diagnostic(
                severity: .warning,
                code: "KSWIFTK-SEMA-0102",
                message: "Deprecated.",
                primaryRange: nil,
                secondaryRanges: []
            ),
        ]
        assertExpectedDiagnostics(
            [
                .error("KSWIFTK-SEMA-0022", containing: "Unresolved reference"),
                .warning("KSWIFTK-SEMA-0102"),
            ],
            in: diagnostics
        )
    }
}
#endif
