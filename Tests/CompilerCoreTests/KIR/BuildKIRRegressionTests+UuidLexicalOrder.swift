#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testUuidLexicalOrderCompanionPropertyLowersToRuntimeCallee() throws {
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
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_uuid_lexicalOrder"), "Expected Uuid.LEXICAL_ORDER runtime call")
        }
    }

    @Test func testABILoweringMarksUuidLexicalOrderAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(callees.contains(interner.intern("kk_uuid_lexicalOrder")))
        #expect(!(callees.contains(interner.intern("kk_uuid_parse"))))
    }
}
#endif
