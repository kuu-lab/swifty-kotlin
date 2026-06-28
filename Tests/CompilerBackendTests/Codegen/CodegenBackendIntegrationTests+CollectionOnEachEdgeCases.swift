@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionOnEachRunsActionAndReturnsReceiver() throws {
        let source = """
        fun consume(values: List<Int>) {
            var trace = ""
            val returned = values.onEach { trace += "$it;" }
            println(trace)
            println(returned)
        }

        fun main() {
            val values = listOf(1, 2, 3)
            var localTrace = ""
            val localReturned = values.onEach { localTrace += "${it * 10};" }
            println(localTrace)
            println(localReturned)
            consume(values)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionOnEachEdgeCases", expected: "10;20;30;\n[1, 2, 3]\n1;2;3;\n[1, 2, 3]\n")
    }
}

