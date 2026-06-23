@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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

    func testCodegenSequenceLastOrNullUsesRuntimeHelper() throws {
        let source = """
        fun render(): Int? {
            return sequenceOf(1, 2, 3).lastOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceLastOrNullKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_sequence_lastOrNull"))
        }
    }
}

