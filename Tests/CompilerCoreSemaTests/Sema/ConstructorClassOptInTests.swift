@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct ConstructorClassOptInTests {
    @Test(arguments: [
        (false, "WARNING", 3, DiagnosticSeverity.warning, false),
        (false, "ERROR", 3, DiagnosticSeverity.error, true),
        (true, "WARNING", 0, DiagnosticSeverity.warning, false),
        (true, "ERROR", 0, DiagnosticSeverity.error, false),
    ])
    func constructorsInheritTheirClassMarkerWithoutDuplicateDiagnostics(
        optedIn: Bool,
        level: String,
        expectedCount: Int,
        expectedSeverity: DiagnosticSeverity,
        expectedHasError: Bool
    ) throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        @RequiresOptIn(level = RequiresOptIn.Level.\(level))
        annotation class ConstructorMarker
        @ConstructorMarker class ExperimentalBox {
            constructor()
            @ConstructorMarker constructor(value: Int)
        }
        @ConstructorMarker class PrimaryBox(val value: Int)
        \(optedIn ? "@OptIn(ConstructorMarker::class)" : "")
        fun caller() { ExperimentalBox(); ExperimentalBox(7); PrimaryBox(9) }
        """, allowDefaultStdlibLibrary: true)
        try runSema(context)
        let diagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("ConstructorMarker")
        }
        #expect(diagnostics.count == expectedCount, "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == expectedSeverity })
        #expect(context.diagnostics.hasError == expectedHasError)
    }
}
