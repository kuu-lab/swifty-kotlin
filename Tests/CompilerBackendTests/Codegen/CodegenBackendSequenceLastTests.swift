#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceLastTests {

    @Test
    func testCodegenSequenceLastReturnsFinalElement() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 3).last())
            println(sequenceOf("a", "b", "c").last())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceLastRuntime",
            expected:
                """
                3
                c
                """ + "\n"
        )
    }

    @Test
    func testCodegenSequenceLastUsesRuntimeHelper() throws {
        let source = """
        fun render(): Int {
            return sequenceOf(1, 2, 3).last()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "SequenceLastKIR",
                emit: .kirDump
            )
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let legacyCallee = try runtimeABICallee("sequence_last")
            #expect(
                containsKotlinCallee("last", in: callees) && !callees.contains(legacyCallee),
                "Expected Sequence.last to resolve through the stdlib artifact, got callees: \(callees.sorted())"
            )
        }
    }
}
#endif
