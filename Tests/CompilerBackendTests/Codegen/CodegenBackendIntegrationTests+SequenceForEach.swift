@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceForEachVisitsElementsInOrder() throws {
        let source = """
        fun main() {
            sequenceOf(1, 2, 3).forEach { value -> println(value) }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceForEachRuntime", expected: "1\n2\n3\n")
    }

    func testCodegenSequenceForEachOnEmptySequenceDoesNothing() throws {
        let source = """
        fun main() {
            emptySequence<Int>().forEach { value -> println(value) }
            println("done")
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceForEachEmpty", expected: "done\n")
    }

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

    func testCodegenSequenceForEachUsesRuntimeHelper() throws {
        let source = """
        fun process(seq: Sequence<Int>) {
            seq.forEach { value -> println(value) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceForEachKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "process", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_sequence_forEach"))
        }
    }
}

