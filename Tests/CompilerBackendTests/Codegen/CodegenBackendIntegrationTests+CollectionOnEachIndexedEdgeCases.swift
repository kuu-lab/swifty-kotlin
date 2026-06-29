@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionOnEachIndexedRunsActionAndReturnsReceiver() throws {
        let source = """
        fun consume(values: List<Int>) {
            var trace = ""
            val returned = values.onEachIndexed { index, value -> trace += "$index:$value;" }
            println(trace)
            println(returned)
        }

        fun main() {
            val values = listOf(10, 20, 30)
            var localTrace = ""
            val localReturned = values.onEachIndexed { index, value -> localTrace += "$index=${value / 10};" }
            println(localTrace)
            println(localReturned)
            consume(values)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionOnEachIndexedEdgeCases", expected: "0=1;1=2;2=3;\n[10, 20, 30]\n0:10;1:20;2:30;\n[10, 20, 30]\n")
    }
}

