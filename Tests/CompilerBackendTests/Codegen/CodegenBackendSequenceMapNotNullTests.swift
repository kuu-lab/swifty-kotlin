#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceMapNotNullTests {

    @Test
    func testCodegenSequenceMapNotNullFiltersNullMappedValues() throws {
        let source = """
        fun main() {
            val mapped = sequenceOf(1, 2, 3, 4).mapNotNull {
                if (it % 2 == 0) it * 10 else null
            }
            println(mapped.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceMapNotNullRuntime", expected: "[20, 40]\n")
    }

    /// KSP-441: `mapNotNull` comes from the bundled Kotlin transform pipeline.
    @Test
    func testCodegenSequenceMapNotNullUsesBundledSourceImplementation() throws {
        let source = """
        fun render(): Sequence<Int> {
            return sequenceOf(1, 2, 3, 4).mapNotNull {
                if (it % 2 == 0) it * 10 else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "SequenceMapNotNullKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            // Artifact imports may inline the source-backed transform; the
            // imported sequence factory plus retired-bridge absence is the
            // stable consumer invariant.
            #expect(containsKotlinCallee("sequenceOf", in: callees))
            #expect(!callees.contains(try runtimeABICallee("sequence_mapNotNull")))
        }
    }
}
#endif
