#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CollectionLiteralParsingTests {

    @Test("A collection literal initializer preserves its local declaration")
    func collectionLiteralInitializerPreservesLocalDeclaration() throws {
        let ctx = makeContextFromSources([
            """
            package collectionLiteralParsing
            fun values(): List<Int> {
                val x = [1, 2, 3]
                return x
            }
            """
        ])

        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
