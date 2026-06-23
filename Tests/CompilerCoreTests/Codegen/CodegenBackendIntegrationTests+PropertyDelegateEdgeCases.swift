@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value = lazyOf(42)
            println(value.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LazyOfValueRead",
            expected:
                """
                42
                """ + "\n"
        )
    }
}

