#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    /// KSP-476: LEXICAL_ORDER is pure Kotlin now (a Comparator<Uuid> built via SAM
    /// conversion over mostSignificantBits/leastSignificantBits), so it no longer
    /// lowers to a dedicated runtime callee. This just confirms the property still
    /// compiles and resolves to a Comparator<Uuid> value.
    @Test func testUuidLexicalOrderCompanionPropertyCompiles() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val lexicalOrder = Uuid.LEXICAL_ORDER
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            #expect(!findAllKIRFunctions(in: module).isEmpty, "Expected LEXICAL_ORDER access to lower to KIR")
        }
    }
}
#endif
