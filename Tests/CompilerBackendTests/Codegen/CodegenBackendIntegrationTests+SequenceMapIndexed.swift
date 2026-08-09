@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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

    func testCodegenSequenceMapIndexedUsesRuntimeHelper() throws {
        let source = """
        fun render(): Sequence<Int> {
            return sequenceOf(10, 20, 30).mapIndexed { index, value -> index + value }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceMapIndexedKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            // Sequence.mapIndexed is source-backed (KSP-441, SequenceTransformHOF.kt),
            // so lowering now calls the Kotlin declaration "mapIndexed" directly
            // instead of a kk_sequence_mapIndexed runtime bridge symbol.
            XCTAssertTrue(callees.contains("mapIndexed"))
        }
    }
}

