#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceMapIndexedTests {

    @Test
    func testCodegenSequenceMapIndexedReturnsLazyIndexedMappedSequence() throws {
        let source = """
        var counter = 0

        fun main() {
            val mapped = sequenceOf(10, 20, 30, 40)
                .mapIndexed { index, value -> counter++; index + value }

            println(mapped.take(2).toList())
            println(counter)
            println(mapped.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceMapIndexedRuntime", expected: "[10, 21]\n2\n[10, 21, 32, 43]\n")
    }

    @Test
    func testCodegenSequenceMapIndexedUsesBundledSourceImplementation() throws {
        let source = """
        fun render(): Sequence<Int> {
            return sequenceOf(10, 20, 30).mapIndexed { index, value -> index + value }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "SequenceMapIndexedKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            // The artifact may inline this Kotlin source implementation, so a
            // direct mapIndexed callee is not stable in consumer KIR.  The
            // imported sequence factory and retired-bridge absence are stable.
            #expect(containsKotlinCallee("sequenceOf", in: callees))
            #expect(!callees.contains(try runtimeABICallee("sequence_mapIndexed")), "Sequence.mapIndexed should no longer route through the retired native bridge, got: \(callees)")
        }
    }
}
#endif
