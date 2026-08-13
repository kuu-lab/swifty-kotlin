#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceJoinToStringTests {
    @Test func testCodegenSequenceJoinToStringDoesNotUseRuntimeHelper() throws {
        let source = """
        fun render(): String {
            return sequenceOf(1, 2, 3).joinToString(separator = ":", prefix = "[", postfix = "]")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceJoinToStringKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(!callees.contains("kk_sequence_joinToString"), "Sequence.joinToString should no longer route through the retired native bridge, got: \(callees)")
        }
    }
}
#endif
