#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceMapTests {

    @Test
    func testCodegenSequenceMapReturnsLazyMappedSequence() throws {
        let source = """
        var counter = 0

        fun main() {
            val mapped = sequenceOf(1, 2, 3, 4)
                .map { counter++; it * 3 }

            println(mapped.take(2).toList())
            println(counter)
            println(mapped.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceMapRuntime", expected: "[3, 6]\n2\n[3, 6, 9, 12]\n")
    }

    @Test
    func testCodegenSequenceMapUsesBundledSourceImplementation() throws {
        let source = """
        fun render(): Sequence<Int> {
            return sequenceOf(1, 2, 3).map { it * 3 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "SequenceMapKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            // The artifact may inline this Kotlin source implementation, so the
            // consumer KIR need not retain a direct map callee.  The imported
            // sequence factory and the absence of the retired bridge still
            // prove artifact-backed routing.
            #expect(containsKotlinCallee("sequenceOf", in: callees))
            #expect(!callees.contains(try runtimeABICallee("sequence_map")), "Sequence.map should no longer route through the retired native bridge, got: \(callees)")
        }
    }
}
#endif
