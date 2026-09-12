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
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "SequenceJoinToStringKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(containsKotlinCallee("joinToString", in: callees))
            #expect(!callees.contains("kk_sequence_joinToString"), "Sequence.joinToString should no longer route through the retired native bridge, got: \(callees)")
            // KSP-621: the CallLowerer fallback that used to rescue unresolved
            // joinToString calls onto this runtime bridge has been removed; Sequence.joinToString
            // always binds to the bundled Kotlin source (SequenceAggregateHOF.kt).
            #expect(!callees.contains("__kk_iterable_joinToString"), "Sequence.joinToString should bind to bundled source, got: \(callees)")
        }
    }
}
#endif
