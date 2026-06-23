@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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

    func testCodegenSequenceMapUsesRuntimeHelper() throws {
        let source = """
        fun render(): Sequence<Int> {
            return sequenceOf(1, 2, 3).map { it * 3 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceMapKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_sequence_map"))
        }
    }
}

