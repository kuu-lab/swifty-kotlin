@testable import CompilerCore
import Testing

@Suite
struct ConstructorClassOptInTests {
    @Test(arguments: [false, true], ["WARNING", "ERROR"])
    func constructorsInheritTheirClassMarkerWithoutDuplicateDiagnostics(optedIn: Bool, level: String) throws {
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
        #expect(diagnostics.count == (optedIn ? 0 : 3), "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == (level == "ERROR" ? .error : .warning) })
        #expect(context.diagnostics.hasError == (!optedIn && level == "ERROR"))
    }
}
