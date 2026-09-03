#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceForEachTests {

    @Test
    func testCodegenSequenceForEachVisitsElementsInOrder() throws {
        let source = """
        fun main() {
            sequenceOf(1, 2, 3).forEach { value -> println(value) }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceForEachRuntime", expected: "1\n2\n3\n")
    }

    @Test
    func testCodegenSequenceForEachOnEmptySequenceDoesNothing() throws {
        let source = """
        fun main() {
            emptySequence<Int>().forEach { value -> println(value) }
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceForEachEmpty", expected: "done\n")
    }

    @Test
    func testCodegenSequenceForEachAfterFilterChain() throws {
        let source = """
        fun main() {
            sequenceOf(1, 2, 3, 4, 5)
                .filter { value -> value % 2 == 0 }
                .forEach { value -> println(value) }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceForEachChained", expected: "2\n4\n")
    }

    @Test
    func testCodegenSequenceForEachUsesRuntimeHelper() throws {
        let source = """
        fun process(seq: Sequence<Int>) {
            seq.forEach { value -> println(value) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceForEachKIR",
                emit: .kirDump,
                outputPath: outputBase
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "process", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("kk_sequence_forEach"))
        }
    }
}
#endif
