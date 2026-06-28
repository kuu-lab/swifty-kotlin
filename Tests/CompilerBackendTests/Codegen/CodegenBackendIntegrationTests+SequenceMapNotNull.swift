@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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

    func testCodegenSequenceMapNotNullUsesRuntimeHelper() throws {
        let source = """
        fun render(): Sequence<Int> {
            return sequenceOf(1, 2, 3, 4).mapNotNull {
                if (it % 2 == 0) it * 10 else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceMapNotNullKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_sequence_mapNotNull"))
        }
    }
}

