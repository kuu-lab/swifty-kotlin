#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceLastOrNullTests {

    @Test
    func testCodegenSequenceLastOrNullReturnsLastElementOrNull() throws {
        let source = """
        fun main() {
            val ints = sequenceOf(1, 2, 3)
            println(ints.lastOrNull() ?: -1)

            val emptyInts = emptySequence<Int>()
            println(emptyInts.lastOrNull() ?: -1)

            val words = sequenceOf("alpha", "beta")
            println(words.lastOrNull() ?: "missing")

            val emptyWords = emptySequence<String>()
            println(emptyWords.lastOrNull() ?: "missing")
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceLastOrNullRuntime", expected: "3\n-1\nbeta\nmissing\n")
    }

    @Test
    func testCodegenSequenceLastOrNullUsesRuntimeHelper() throws {
        let source = """
        fun render(): Int? {
            return sequenceOf(1, 2, 3).lastOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceLastOrNullKIR",
                emit: .kirDump,
                outputPath: outputBase,
                stdlibLibraryPath: try testStdlibArtifactPath(),
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let legacyCallee = try runtimeABICallee("sequence_lastOrNull")
            #expect(
                containsKotlinCallee("lastOrNull", in: callees) && !callees.contains(legacyCallee),
                "Expected Sequence.lastOrNull to resolve through the stdlib artifact, got callees: \(callees.sorted())"
            )
        }
    }
}
#endif
